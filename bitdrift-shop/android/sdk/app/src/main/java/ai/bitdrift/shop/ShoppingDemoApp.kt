package ai.bitdrift.shop

import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Process
import android.os.SystemClock

import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.FieldProvider
import io.bitdrift.capture.providers.Fields
import io.bitdrift.capture.providers.session.SessionStrategy
import okhttp3.HttpUrl

class ShoppingDemoApp : Application() {

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext

        // bitdrift SDK: Logger.start() initializes the SDK with the API key, endpoint, session
        // strategy, and field providers. Must be called before any logging.
        // POC: crash detection, memory monitoring, visual performance (OOTB — no extra calls); session management
        Logger.start(
            apiKey = BuildConfig.BITDRIFT_SDK_KEY,
            apiUrl = HttpUrl.Builder().scheme("https").host(BuildConfig.BITDRIFT_API_HOST).build(),
            sessionStrategy = SessionStrategy.Fixed(),
            fieldProviders = listOf(UserIdFieldProvider(applicationContext)),
        )
        // Register lifecycle callbacks
        registerActivityLifecycleCallbacks(AppLifecycleCallbacks())

        // Log app launch
        // bitdrift SDK: logInfo() emits a structured event at app launch.
        Logger.logInfo { "app_launched" }

        // bitdrift SDK: addField() sets a global field attached to every log, span, and network
        // request for the lifetime of this process. Not persisted — re-added on each start.
        // POC: insights & visualization — slice any dashboard, Workflow, or alert by global field value
        Logger.addField("app_variant", "sdk-demo")

        installCrashLoopHandler()
    }

    private fun installCrashLoopHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
            if (prefs.getBoolean(KEY_ACTIVE, false)) {
                // Pre-schedule restart via AlarmManager before the process dies.
                // This fires even for native signals (SIGSEGV/SIGBUS/etc.) where the
                // JVM handler is never called — the alarm is already armed before the crash.
                scheduleRestart(applicationContext, RESTART_DELAY_MS)
                Process.killProcess(Process.myPid())
                System.exit(1)
            } else {
                defaultHandler?.uncaughtException(thread, throwable)
                Process.killProcess(Process.myPid())
                System.exit(1)
            }
        }
    }

    companion object {
        const val PREFS = "crash_loop"
        const val KEY_ACTIVE = "active"
        const val KEY_NEXT_INDEX = "next_index"
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
 * FieldProvider that exposes the currently signed-in user_id on every log.
 * Reading from SharedPreferences means the field survives startNewSession() and
 * process restarts. user_id is a special bitdrift field: it appears in the
 * Timeline session header when present.
 */
class UserIdFieldProvider(private val context: Context) : FieldProvider {
    override fun invoke(): Fields {
        val id = context
            .getSharedPreferences("user_session", Context.MODE_PRIVATE)
            .getString("user_id", null)
        return if (id.isNullOrEmpty()) emptyMap() else mapOf("user_id" to id)
    }
}
