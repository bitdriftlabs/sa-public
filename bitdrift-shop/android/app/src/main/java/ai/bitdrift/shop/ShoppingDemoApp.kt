package ai.bitdrift.shop

import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Process
import android.os.SystemClock

import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.Fields
import io.bitdrift.capture.providers.session.SessionConfiguration
import okhttp3.HttpUrl

class ShoppingDemoApp : Application() {

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext

        // bitdrift SDK: Logger.start() initializes the SDK with the API key, endpoint, session
        // configuration, and startup fields. Must be called before any logging.
        // POC: crash detection, memory monitoring, visual performance (OOTB — no extra calls); session management
        //
        // SessionConfiguration() with no inactivityTimeout matches the old SessionStrategy.Fixed():
        // a fresh session ID on every process start, never persisted/reused across restarts.
        //
        // user_id is seeded here from SharedPreferences rather than via a FieldProvider (deprecated
        // in favor of initialFields + addField/removeField) -- the sign-in/sign-out call sites in
        // Screens.kt already call Logger.addField("user_id", ...)/removeField("user_id") directly,
        // so this seed only matters for a process restart while already signed in, where addField's
        // in-memory state from the prior process is gone but the persisted value isn't.
        Logger.start(
            apiKey = BuildConfig.BITDRIFT_SDK_KEY,
            apiUrl = HttpUrl.Builder().scheme("https").host(BuildConfig.BITDRIFT_API_HOST).build(),
            sessionConfiguration = SessionConfiguration(),
            initialFields = readPersistedUserIdField(applicationContext),
        )
        Logger.setEntityId("demo")
        // Register lifecycle callbacks
        registerActivityLifecycleCallbacks(AppLifecycleCallbacks())

        // Log app launch
        // bitdrift SDK: logInfo() emits a structured event at app launch.
        Logger.logInfo { "app_launched" }

        // bitdrift SDK: addField() sets a global field attached to every log, span, and network
        // request for the lifetime of this process. Not persisted — re-added on each start.
        // POC: insights & visualization — slice any dashboard, Workflow, or alert by global field value
        Logger.addField("app_variant", "sdk-demo")
        // Matches the iOS app's `platform` field so a single chart can group or filter
        // across both apps. The span names are already identical between platforms, so
        // this field is the missing piece for cross-platform comparison — without it the
        // only discriminator is `app_id`, which works but reads as an opaque bundle id.
        Logger.addField("platform", "android")

        installCrashLoopHandler()

        // bitdrift SDK: opens the `app_cold_start` root span plus its `sdk_init` child.
        // Everything above — Logger.start() itself, setEntityId, addField, the
        // crash-loop handler install — is what `sdk_init` measures, so this must be
        // the last statement here, not the first.
        // POC: event tracking — granular per-phase cold-start histograms plus a
        // Timeline waterfall, instead of one opaque TTI number. See ColdStartSpans
        // and bd-shop-20 in workflows/.
        ColdStartSpans.beginRoot()
    }

    private fun installCrashLoopHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            // Always let bitdrift's own handler run first -- it's the only entry point
            // that builds and persists the structured crash Report. The crash-loop
            // branch used to skip this entirely, so JVM crashes never produced a real
            // captured report while crash-loop mode was active -- only native signals
            // did, since those go through a separate handler this chain never touches.
            defaultHandler?.uncaughtException(thread, throwable)
            val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
            if (prefs.getBoolean(KEY_ACTIVE, false)) {
                // Pre-schedule restart via AlarmManager before the process dies.
                // This fires even for native signals (SIGSEGV/SIGBUS/etc.) where the
                // JVM handler is never called -- the alarm is already armed before the crash.
                scheduleRestart(applicationContext, RESTART_DELAY_MS)
            }
            Process.killProcess(Process.myPid())
            System.exit(1)
        }
    }

    companion object {
        const val PREFS = "crash_loop"
        const val KEY_ACTIVE = "active"
        // Combined crash-type + foreground/background combo index (0 until Crashes.all.size * 2).
        // comboIdx / 2 -> crash type; comboIdx % 2 -> 0=foreground, 1=background.
        const val KEY_NEXT_COMBO_INDEX = "next_combo_index"
        const val KEY_FAST_MODE = "fast_mode"
        // When true, the crash loop cycles only through Crashes.oomOnly instead of
        // Crashes.all — set by the "OOMs" button in the Advanced screen.
        const val KEY_OOM_ONLY = "oom_only"
        private const val RESTART_DELAY_MS = 800L
        private const val RESTART_REQUEST_CODE = 4242

        lateinit var appContext: Context
            private set

        /**
         * Schedules a MainActivity restart via AlarmManager. Must be called BEFORE
         * triggering the crash — AlarmManager survives even SIGSEGV/SIGBUS where the
         * JVM uncaught-exception handler cannot run.
         */
        fun scheduleRestart(ctx: Context, delayMs: Long) {
            val intent = Intent(ctx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            val pi = PendingIntent.getActivity(
                ctx,
                RESTART_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
            )
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.set(AlarmManager.ELAPSED_REALTIME, SystemClock.elapsedRealtime() + delayMs, pi)
        }

        // bitdrift SDK: Record the process-level start time so MainActivity can compute TTI.
        val appStartUptimeMs: Long = SystemClock.uptimeMillis()
    }
}

/**
 * Reads the currently signed-in user_id from SharedPreferences, if any, to seed as an
 * initial field at SDK startup. user_id is a special bitdrift field: it appears in the
 * Timeline session header when present. Kept in sync thereafter by the sign-in/sign-out
 * addField/removeField calls in Screens.kt, not by re-reading this on every log.
 */
private fun readPersistedUserIdField(context: Context): Fields {
    val id = context
        .getSharedPreferences("user_session", Context.MODE_PRIVATE)
        .getString("user_id", null)
    return if (id.isNullOrEmpty()) emptyMap() else mapOf("user_id" to id)
}
