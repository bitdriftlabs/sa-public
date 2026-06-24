package ai.bitdrift.shop

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Bundle
import io.bitdrift.capture.Capture.Logger

class AppLifecycleCallbacks : Application.ActivityLifecycleCallbacks, ComponentCallbacks2 {

    private var activityCount = 0

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
        }
    }

    override fun onActivityStopped(activity: Activity) {
        activityCount--
        if (activityCount == 0) {
            // bitdrift SDK: logInfo() emits a structured event for foreground/background transitions.
            Logger.logInfo(mapOf("trigger" to "onActivityStopped")) { "app_close" }
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
