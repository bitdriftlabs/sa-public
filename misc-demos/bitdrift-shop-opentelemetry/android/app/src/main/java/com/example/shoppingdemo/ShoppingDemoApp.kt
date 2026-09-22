package com.example.shoppingdemo

import android.app.Application
import android.content.Context
import android.os.SystemClock
import android.util.Log

import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.session.SessionStrategy
import okhttp3.HttpUrl

class ShoppingDemoApp : Application() {

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext

        // Workshop 1 - Initialization (android, basic sdk)
        // Uncomment this block during the workshop to enable bitdrift startup.

        Logger.start(
        apiKey = BuildConfig.BITDRIFT_SDK_KEY,
        apiUrl = HttpUrl.Builder().scheme("https").host(BuildConfig.BITDRIFT_API_HOST).build(),
        sessionStrategy = SessionStrategy.Fixed(),
        )
        // Register lifecycle callbacks
        registerActivityLifecycleCallbacks(AppLifecycleCallbacks())

        // Log app launch
        Log.d(TAG, "App launched")

        // Workshop 4c — Logging (android, basic sdk)
        // workshop-301.md § "4c — Logging Examples"
        // Structured log: stable event name + fields for variable data.
        Logger.logInfo { "app_launched" }

        // Workshop 5 — Global Fields (android, basic sdk)
        // workshop-301.md § "5 — Global Fields"
        // Set once at startup; attached to every log, span, and network request automatically.
        // Not persisted to disk — re-add on every process start.
        Logger.addField("app_variant", "otel-demo")

    }

    companion object {
        private const val TAG = "ShoppingDemoApp"
        lateinit var appContext: Context
            private set

        // Workshop 3 — App Launch TTI (android, basic sdk)
        // https://github.com/nicholasgasior/bitdrift → workshop-301.md § "3 — App Launch TTI"
        // Record the process-level start time so MainActivity can compute time-to-interactive.
        val appStartUptimeMs: Long = SystemClock.uptimeMillis()
    }
}
