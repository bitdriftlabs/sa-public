package com.example.shoppingdemo

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
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
            Log.d(TAG, "app_open (trigger=onActivityStarted)")
            // Workshop 4c — Logging (android, basic sdk)
            // workshop-301.md § "4c — Logging Examples"
            // Use a stable event name with structured fields instead of interpolated strings.
            Logger.logInfo(mapOf("trigger" to "onActivityStarted")) { "app_open" }
        }
    }

    override fun onActivityStopped(activity: Activity) {
        activityCount--
        if (activityCount == 0) {
            Log.d(TAG, "app_close (trigger=onActivityStopped)")
            // Workshop 4c — Logging (android, basic sdk)
            // workshop-301.md § "4c — Logging Examples"
            Logger.logInfo(mapOf("trigger" to "onActivityStopped")) { "app_close" }
        }
    }

    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            Log.w(TAG, "memory_pressure (level=$level)")
            // Workshop 4c — Logging (android, basic sdk)
            // workshop-301.md § "4c — Logging Examples"
            Logger.logWarning(mapOf("level" to level.toString())) { "memory_pressure" }
        }
    }

    override fun onLowMemory() {
        Log.w(TAG, "low_memory")
        // Workshop 4c — Logging (android, basic sdk)
        // workshop-301.md § "4c — Logging Examples"
        Logger.logWarning { "low_memory" }
    }

    companion object {
        private const val TAG = "AppLifecycle"
    }
}
