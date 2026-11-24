package org.wikipedia.bitdriftdev

import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import io.bitdrift.capture.Capture
import io.bitdrift.capture.commands.CommandArgument
import io.bitdrift.capture.commands.CommandAttachment
import io.bitdrift.capture.commands.CommandErrorCode
import io.bitdrift.capture.commands.CommandHandle
import io.bitdrift.capture.commands.CommandResult
import io.bitdrift.capture.commands.CommandScope
import io.bitdrift.capture.commands.argument
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.MainScope
import org.wikipedia.BuildConfig
import org.wikipedia.WikipediaApp
import org.wikipedia.auth.AccountUtil
import org.wikipedia.concurrency.FlowEventBus
import org.wikipedia.events.LoggedInEvent
import org.wikipedia.login.LoginClient
import org.wikipedia.login.LoginEmailAuthResult
import org.wikipedia.login.LoginOATHResult
import org.wikipedia.login.LoginResult
import org.wikipedia.notifications.PollNotificationWorker
import org.wikipedia.readinglist.sync.ReadingListSyncAdapter
import org.wikipedia.settings.Prefs
import org.wikipedia.settings.SettingsActivity
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Handlers for the device commands in bitdrift's staging command catalog, adapted from the Capture
 * SDK's gradle-test-app (SampleCommands.kt and MainViewModel.kt). The key must also exist in the
 * server catalog, and a command only reaches this app when the catalog entry's platform targets
 * include it.
 */
object BitdriftCommands {
    private const val TAG = "BitdriftCommands"
    private const val DEFAULT_TRACE_DURATION_MS = 5_000L

    private val flags = ConcurrentHashMap<String, Boolean>()
    private val handles = mutableListOf<CommandHandle>()
    private var appContext: Context? = null

    @Synchronized
    fun register(context: Context) {
        if (handles.isNotEmpty()) return
        appContext = context.applicationContext
        handles += registerAll()
        Log.i(TAG, "Registered commands: ${handles.joinToString { it.key }}")
    }

    @OptIn(ExperimentalBitdriftApi::class)
    private fun registerAll(): List<CommandHandle> =
        listOf(
            // Toggles a named flag and reports it as a feature flag exposure.
            Capture.Logger.registerCommand("flip_flag") {
                log()
                val flag = argument<String>("flag")
                val previous = flags[flag] ?: false
                flags[flag] = !previous
                Capture.Logger.setFeatureFlagExposure(flag, !previous)
                success(context = mapOf("flag" to flag, "from" to previous.toString(), "to" to (!previous).toString()))
            },
            // JVM heap numbers, as fields or as a JSON attachment.
            Capture.Logger.registerCommand("memory_dump") {
                log()
                val runtime = Runtime.getRuntime()
                val dump = """{"max":${runtime.maxMemory()},"total":${runtime.totalMemory()},"free":${runtime.freeMemory()}}"""
                if (arguments["is_attachment"].isTruthy()) {
                    success(attachment = CommandAttachment(dump.toByteArray(), contentType = "application/json"))
                } else {
                    success(context = mapOf("memory" to dump))
                }
            },
            // Perfetto stack sampling trace through ProfilingManager (Android 15+).
            Capture.Logger.registerCommand("system_trace") {
                log()
                val durationMs = if ("duration_ms" in arguments) argument<Long>("duration_ms") else DEFAULT_TRACE_DURATION_MS
                if (durationMs !in 1..60_000) {
                    return@registerCommand error("invalid_duration", code = CommandErrorCode.InvalidArguments)
                }
                val requestedType = if ("profiling_type" in arguments) argument<String>("profiling_type") else "STACK_SAMPLING"
                val profilingType =
                    AppProfiler.ProfilingType.entries.firstOrNull { it.name.equals(requestedType, ignoreCase = true) }
                        ?: return@registerCommand error("invalid_profiling_type", mapOf("profiling_type" to requestedType), code = CommandErrorCode.InvalidArguments)
                val context = appContext ?: return@registerCommand error("no_context")
                profileResult(profilingType, durationMs, AppProfiler.capture(context, profilingType.request(durationMs.toInt())))
            },
            // Perfetto heap profile (native or Java allocations) through ProfilingManager (Android 15+).
            Capture.Logger.registerCommand("heap_profile_demo") {
                log()
                val request =
                    AppProfiler.Request.HeapProfile(
                        durationMs = argument<Long>("duration_ms").toIntSaturated(),
                        bufferSizeKb = argument<Long>("buffer_size_kb").toIntSaturated(),
                        samplingIntervalBytes = argument<Long>("sampling_interval_bytes"),
                        trackJavaAllocations = argument<Boolean>("track_java_allocations"),
                    )
                val context = appContext ?: return@registerCommand error("no_context")
                profileResult(request.type, request.durationMs.toLong(), AppProfiler.capture(context, request))
            },
            // Perfetto Java heap dump (one snapshot) through ProfilingManager (Android 15+).
            Capture.Logger.registerCommand("java_heap_dump_demo") {
                log()
                val request = AppProfiler.Request.JavaHeapDump(bufferSizeKb = argument<Long>("buffer_size_kb").toIntSaturated())
                val context = appContext ?: return@registerCommand error("no_context")
                profileResult(request.type, durationMs = null, AppProfiler.capture(context, request))
            },
            // Perfetto system trace (CPU scheduling, thread states, frames) through ProfilingManager (Android 15+).
            // The catalog's system_trace only allows duration_ms, so it always records a stack sample.
            Capture.Logger.registerCommand("system_trace_iain") {
                log()
                val durationMs = argument<Long>("duration_ms")
                if (durationMs !in 1..60_000) {
                    return@registerCommand error("invalid_duration", code = CommandErrorCode.InvalidArguments)
                }
                val request = AppProfiler.Request.SystemTrace(durationMs.toInt())
                val context = appContext ?: return@registerCommand error("no_context")
                profileResult(request.type, durationMs, AppProfiler.capture(context, request))
            },
            // Opens the Settings screen, as the main screen's menu does.
            Capture.Logger.registerCommand("open_settings") {
                log()
                val context = appContext ?: return@registerCommand error("no_context")
                withContext(Dispatchers.Main) {
                    context.startActivity(SettingsActivity.newIntent(context).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                success(context = mapOf("screen" to "Settings"))
            },
            // Logs the reader out at once, as Settings does after its confirmation, and tells them with a
            // toast. Reports the account type, never the username.
            Capture.Logger.registerCommand("log_out_user") {
                log()
                val context = appContext ?: return@registerCommand error("no_context")
                if (!AccountUtil.isLoggedIn) {
                    return@registerCommand success(context = mapOf("status" to "not_logged_in"))
                }
                val accountType = if (AccountUtil.isTemporaryAccount) "temporary" else "permanent"
                withContext(Dispatchers.Main) {
                    WikipediaApp.instance.logOut()
                    Prefs.readingListsLastSyncTime = null
                    Prefs.isReadingListSyncEnabled = false
                    Prefs.isSuggestedEditsHighestPriorityEnabled = false
                    Toast.makeText(context, "You've been logged out", Toast.LENGTH_LONG).show()
                }
                success(context = mapOf("status" to "logged_out", "account_type" to accountType))
            },
            // Logs in with the demo account from local.properties (BITDRIFT_DEMO_USERNAME and
            // BITDRIFT_DEMO_PASSWORD), never from command arguments. Login can take longer than a command
            // may run, so this returns at once and logs the outcome as log_in_user.
            Capture.Logger.registerCommand("log_in_user") {
                log()
                val context = appContext ?: return@registerCommand error("no_context")
                val username = BuildConfig.BITDRIFT_DEMO_USERNAME
                val password = BuildConfig.BITDRIFT_DEMO_PASSWORD
                if (username.isEmpty() || password.isEmpty()) {
                    return@registerCommand error(
                        "no_demo_account: set BITDRIFT_DEMO_USERNAME and BITDRIFT_DEMO_PASSWORD in local.properties",
                    )
                }
                if (AccountUtil.isLoggedIn && !AccountUtil.isTemporaryAccount) {
                    return@registerCommand success(context = mapOf("status" to "already_logged_in"))
                }
                withContext(Dispatchers.Main) { startDemoLogin(context, username, password) }
                success(context = mapOf("status" to "logging_in"))
            },
            // Sleeps, to test cancellation. The test app owns this with a ViewModel; here it lives with the app.
            Capture.Logger.registerCommand("ui_state_slow") {
                log()
                val durationMs = if ("duration_ms" in arguments) argument<Long>("duration_ms") else 4_000L
                delay(durationMs)
                success(context = mapOf("slept_ms" to durationMs.toString()))
            },
        )

    private suspend fun CommandScope.profileResult(
        profilingType: AppProfiler.ProfilingType,
        durationMs: Long?,
        result: AppProfiler.Result,
    ): CommandResult =
        when (result) {
            is AppProfiler.Result.Saved -> {
                // Hand the SDK a file it owns rather than bytes: file attachments stream in chunks, while
                // in-memory attachments must fit the upload queue, which a heap dump (tens of MB) overflows.
                val owned = withContext(Dispatchers.IO) { takeOwnership(File(result.path)) }
                if (owned == null) {
                    error("profiling_failed: trace file missing")
                } else {
                    success(
                        attachment = CommandAttachment.file(owned, contentType = "application/vnd.bitdrift.perfetto-trace"),
                        context =
                            buildMap {
                                put("profiling_type", profilingType.name)
                                durationMs?.let { put("duration_ms", it.toString()) }
                                put("trace_bytes", owned.length().toString())
                            },
                    )
                }
            }
            is AppProfiler.Result.Failure ->
                // The SDK writes its own `error` field, so put the platform error name in the message
                // and under a separate key. Android's rate limiter allows one capture per hour by default.
                error(
                    listOfNotNull("profiling_failed", result.errorName, result.message.ifEmpty { null }).joinToString(": "),
                    context = listOfNotNull(result.errorName?.let { "profiling_error" to it }).toMap(),
                )
        }

    /** Moves the platform's trace out of the profiling directory into a file the SDK can own and delete. */
    private fun takeOwnership(source: File): File? {
        if (!source.isFile) return null
        val owned = File.createTempFile("command-profile-", ".perfetto-trace", checkNotNull(appContext).filesDir)
        if (!source.renameTo(owned)) {
            source.copyTo(owned, overwrite = true)
            source.delete()
        }
        return owned
    }

    /** The login screen's flow and its after-login steps, minus the screen. Steps a command can't complete are reported. */
    private fun startDemoLogin(context: Context, username: String, password: String) {
        fun report(status: String, detail: String? = null) {
            val fields = listOfNotNull("status" to status, detail?.let { "message_code" to it }).toMap()
            if (status == "logged_in") Capture.Logger.logInfo(fields) { "log_in_user" } else Capture.Logger.logWarning(fields) { "log_in_user" }
        }
        LoginClient().login(MainScope(), WikipediaApp.instance.wikiSite, username, password, cb = object : LoginClient.LoginCallback {
            override fun success(result: LoginResult) {
                if (!result.pass()) {
                    report(if (result.messageCode == "wrongpassword") "wrong_password" else "failed", result.messageCode)
                    return
                }
                AccountUtil.updateAccount(null, result)
                Prefs.isReadingListSyncEnabled = true
                Prefs.readingListPagesDeletedIds = emptySet()
                Prefs.readingListsDeletedIds = emptySet()
                Prefs.tempAccountWelcomeShown = false
                Prefs.tempAccountCreateDay = 0L
                Prefs.lastBackgroundLoginDateTime = ""
                ReadingListSyncAdapter.manualSyncWithForce()
                PollNotificationWorker.schedulePollNotificationJob(context)
                FlowEventBus.post(LoggedInEvent())
                Toast.makeText(context, "Logged in as the demo account", Toast.LENGTH_LONG).show()
                report("logged_in")
            }

            override fun uiPrompt(result: LoginResult, caught: Throwable, captchaId: String?, token: String?) {
                report(
                    when {
                        captchaId != null -> "needs_captcha"
                        result is LoginOATHResult -> "needs_2fa"
                        result is LoginEmailAuthResult -> "needs_email_code"
                        else -> "needs_more_steps"
                    },
                )
            }

            override fun hCaptchaPrompt(result: LoginResult, caught: Throwable, siteKey: String, token: String?) = report("needs_captcha")

            override fun passwordResetPrompt(token: String?) = report("needs_password_change")

            override fun error(caught: Throwable) = report("failed")
        })
    }

    private fun CommandScope.log() {
        Log.i(TAG, "Command $key invoked with ${arguments.ifEmpty { "no arguments" }} (commandId=$commandId)")
    }

    /** Accepts a boolean argument or the text "true", since the device console may send either. */
    private fun CommandArgument?.isTruthy(): Boolean =
        when (this) {
            is CommandArgument.Bool -> value
            is CommandArgument.Text -> value.toBoolean()
            else -> false
        }

    private fun Long.toIntSaturated(): Int = coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
}
