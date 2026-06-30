package com.example.metricdemo

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log

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
        }
    }

    override fun onActivityStopped(activity: Activity) {
        activityCount--
        if (activityCount == 0) {
            Log.d(TAG, "app_close (trigger=onActivityStopped)")
        }
    }

    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            Log.w(TAG, "memory_pressure (level=$level)")
        }
    }

    override fun onLowMemory() {
        Log.w(TAG, "low_memory")
    }

    companion object {
        private const val TAG = "AppLifecycle"
    }
}
