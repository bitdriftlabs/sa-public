package ai.bitdrift.shop

import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Process
import android.os.SystemClock


class ShoppingDemoApp : Application() {

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext

        // Register lifecycle callbacks
        installCrashLoopHandler()

    }

    private fun installCrashLoopHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
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

    }
}


