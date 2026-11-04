package org.wikipedia.bitdriftdev

import android.content.Context
import android.util.Log
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
                        ?: return@registerCommand error("invalid_profiling_type", requestedType, code = CommandErrorCode.InvalidArguments)
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
        durationMs: Long,
        result: AppProfiler.Result,
    ): CommandResult =
        when (result) {
            is AppProfiler.Result.Saved -> {
                val bytes = withContext(Dispatchers.IO) { File(result.path).takeIf(File::exists)?.readBytes() }
                if (bytes == null) {
                    error("profiling_failed", "trace file missing")
                } else {
                    success(
                        attachment = CommandAttachment(bytes, contentType = "application/vnd.bitdrift.perfetto-trace"),
                        context =
                            mapOf(
                                "profiling_type" to profilingType.name,
                                "duration_ms" to durationMs.toString(),
                                "trace_bytes" to bytes.size.toString(),
                            ),
                    )
                }
            }
            is AppProfiler.Result.Failure ->
                error(
                    "profiling_failed",
                    result.message,
                    context = listOfNotNull(result.errorName?.let { "error" to it }).toMap(),
                )
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
