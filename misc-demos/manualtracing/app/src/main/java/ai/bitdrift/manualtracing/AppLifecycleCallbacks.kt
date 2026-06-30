package ai.bitdrift.manualtracing

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Bundle
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.LogLevel

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
            Logger.log(LogLevel.INFO) { "app_open" }
        }
    }

    override fun onActivityStopped(activity: Activity) {
        activityCount--
        if (activityCount == 0) {
            Logger.log(LogLevel.INFO) { "app_close" }
        }
    }

    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            Logger.log(LogLevel.WARNING, mapOf("level" to level.toString())) { "memory_pressure" }
        }
    }

    override fun onLowMemory() {
        Logger.log(LogLevel.WARNING) { "low_memory" }
    }
}
