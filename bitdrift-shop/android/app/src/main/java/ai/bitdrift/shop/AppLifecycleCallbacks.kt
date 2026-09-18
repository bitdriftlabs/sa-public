package ai.bitdrift.shop

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Bundle
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.Span
import io.bitdrift.capture.events.span.SpanResult

class AppLifecycleCallbacks : Application.ActivityLifecycleCallbacks, ComponentCallbacks2 {

    private var activityCount = 0

    // Duration-only: the SDK's own automatic AppStart/AppStop lifecycle logs (used by
    // bd-shop-13/15 for count/rate) turned out not to reliably pair up across a
    // two-step "measure time between steps" workflow at real cycling volume - the
    // bitdrift workflow debugger showed the AppStop step never advancing past 0
    // matches despite AppStart matching every time. A span sidesteps that class of
    // problem entirely: its end log carries _duration_ms on itself, no cross-log
    // correlation required. See workflows/foreground-session-metrics.md.
    private var foregroundSpan: Span? = null

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
    override fun onConfigurationChanged(newConfig: Configuration) {}

    override fun onActivityStarted(activity: Activity) {
        activityCount++
        if (activityCount == 1) {
            // bitdrift SDK: logInfo() emits a structured event with a stable name and field map.
            // POC: Workflow matching, Timeline breadcrumbs, alert triggers — stable event names are queryable
            Logger.logInfo(mapOf("trigger" to "onActivityStarted")) { "app_open" }
            foregroundSpan = Logger.startSpan("foreground_session", LogLevel.INFO)
        }
    }

    override fun onActivityStopped(activity: Activity) {
        activityCount--
        if (activityCount == 0) {
            // bitdrift SDK: logInfo() emits a structured event for foreground/background transitions.
            Logger.logInfo(mapOf("trigger" to "onActivityStopped")) { "app_close" }
            foregroundSpan?.end(SpanResult.SUCCESS)
            foregroundSpan = null
        }
    }

    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            // bitdrift SDK: logWarning() emits a warning-level event; severity is queryable in the dashboard.
            // POC: alert triggers — create a Workflow that fires when memory_pressure rate exceeds threshold
            Logger.logWarning(mapOf("level" to level.toString())) { "memory_pressure" }
        }
    }

    override fun onLowMemory() {
        // bitdrift SDK: logWarning() with no fields — event name alone is sufficient for this signal.
        Logger.logWarning { "low_memory" }
    }

}
