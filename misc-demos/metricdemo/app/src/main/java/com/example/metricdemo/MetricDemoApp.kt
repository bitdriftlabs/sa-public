package com.example.metricdemo

// bitdrift
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.session.SessionStrategy
import okhttp3.HttpUrl

import ai.bitdrift.metricdemo.BuildConfig
import android.app.Application
import android.os.SystemClock
import android.util.Log

class MetricDemoApp : Application() {

    override fun onCreate() {
        appStartNs = SystemClock.elapsedRealtimeNanos()
        super.onCreate()

    // Initialize bitdrift
    Logger.start(
        apiKey = BuildConfig.BITDRIFT_SDK_KEY,
        apiUrl = HttpUrl.Builder().scheme("https").host(BuildConfig.BITDRIFT_API_HOST).build(),
        sessionStrategy = SessionStrategy.Fixed(),
    )


        // Register lifecycle callbacks
        registerActivityLifecycleCallbacks(AppLifecycleCallbacks())

        // Log app launch
        Log.d(TAG, "App launched")
    }

    companion object {
        var appStartNs: Long = 0
        private const val TAG = "MetricDemoApp"
    }
}
