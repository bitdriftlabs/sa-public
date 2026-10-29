package org.wikipedia.bitdriftdev

import android.app.Activity
import android.app.Application
import android.os.*
import android.view.*
import io.bitdrift.capture.Capture.Logger
import kotlin.math.abs

/**
 * Adds a one-finger long-press (~3s) listener to every Activity window.
 * Trigger area is a bottom-right "safe corner" to avoid clashes with other long-press UI.
 * When triggered, shows a simple dialog with:
 *  - Start Slow Leak
 *  - Force OOM Now
 *  - Native Crash (SIGSEGV)
 *  - Force ANR (blocks the main thread)
 *
 * Touches are observed by wrapping the window's callback rather than with an overlay view.
 * An overlay that returns false on ACTION_DOWN never sees the matching UP, so a quick tap
 * would arm the timer and open the menu anyway. The wrapper sees the whole gesture and
 * passes every event through untouched, so the app stays usable.
 */
object GlobalDebugGesture : Application.ActivityLifecycleCallbacks {

    private const val PRESS_MS = 3000L

    fun install(app: Application) {
        app.registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityResumed(activity: Activity) {
        val window = activity.window ?: return
        val original = window.callback ?: return
        if (original is GestureCallback) return
        window.callback = GestureCallback(activity, original)
    }

    private class GestureCallback(
        private val activity: Activity,
        private val delegate: Window.Callback
    ) : Window.Callback by delegate {

        private val handler = Handler(Looper.getMainLooper())
        private val trigger = Runnable {
            armed = false
            if (!activity.isFinishing && !activity.isDestroyed) showDialog(activity)
        }
        private var armed = false
        private var downX = 0f
        private var downY = 0f
        private val touchSlop = ViewConfiguration.get(activity).scaledTouchSlop * 0.6f // stricter

        // Safe-corner geometry (bottom-right 96dp box with 24dp margin)
        private val density get() = activity.resources.displayMetrics.density
        private val boxPx get() = (96 * density)
        private val marginPx get() = (24 * density)

        private fun isInSafeCorner(x: Float, y: Float): Boolean {
            val root = activity.window?.decorView ?: return false
            val minX = root.width - boxPx - marginPx
            val minY = root.height - boxPx - marginPx
            return x >= minX && y >= minY
        }

        override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    cancel()
                    // Only arm if the DOWN occurs in the safe corner
                    if (isInSafeCorner(ev.x, ev.y)) {
                        armed = true
                        downX = ev.x
                        downY = ev.y
                        handler.postDelayed(trigger, PRESS_MS)
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    if (armed) {
                        val dx = abs(ev.x - downX)
                        val dy = abs(ev.y - downY)
                        if (dx > touchSlop || dy > touchSlop) cancel()
                    }
                }
                // A second finger, a lift or a cancel all abort the long-press.
                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> cancel()
            }
            return delegate.dispatchTouchEvent(ev) // don't consume; app still gets touches
        }

        private fun cancel() {
            armed = false
            handler.removeCallbacks(trigger)
        }
    }

    private fun showDialog(activity: Activity) {
        android.app.AlertDialog.Builder(activity)
            .setTitle("Debug Menu")
            .setItems(arrayOf("Start Slow Leak (+256 KB / 500ms)", "Force OOM Now", "Native Crash (SIGSEGV)", "Force ANR (block main thread 60s)")) { _, which ->
                if (which == 3) {
                    Logger.logWarning(
                        mapOf("type" to "forceAnr", "screen" to activity::class.java.simpleName)
                    ) { "ANR Simulation Started" }
                    // Post so the dialog dismisses first; the tap that triggers the ANR needs a visible window.
                    Handler(Looper.getMainLooper()).post { DebugCrasher.forceAnr() }
                } else if (which == 2) {
                    Logger.logWarning(
                        mapOf("type" to "nativeCrash", "screen" to activity::class.java.simpleName)
                    ) { "Native Crash Simulation Started" }
                    DebugCrasher.forceNativeCrash()
                } else if (which == 0) {
                    DebugLeaker.startSlowLeak()
                    Logger.logWarning(
                        mapOf(
                            "type" to "slowLeak",
                            "rate" to "256KB/500ms",
                            "screen" to (activity::class.java.simpleName ?: "UnknownActivity")
                        )
                    ) { "Memory Leak Simulation Started" }
                } else {
                    DebugLeaker.forceOutOfMemoryCrash()
                    Logger.logWarning(
                        mapOf(
                            "type" to "forceOOM",
                            "chunk" to "1MB/50ms",
                            "screen" to (activity::class.java.simpleName ?: "UnknownActivity")
                        )
                    ) { "Force OOM Simulation Started" }
                }
            }
            // Re-arm reliably even if the user taps outside the dialog
            .setOnDismissListener { /* no-op; overlay re-arms on next DOWN */ }
            .show()
    }

    // Unused callbacks:
    override fun onActivityCreated(a: Activity, s: android.os.Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivityPaused(a: Activity) {}
    override fun onActivityStopped(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, outState: android.os.Bundle) {}
    override fun onActivityDestroyed(a: Activity) {}
}
