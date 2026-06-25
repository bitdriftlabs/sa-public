package com.example.shoppingdemo.shared

/**
 * Centralized logging for screen views and user actions.
 * Delegates to platform-specific implementations via expect/actual:
 *   - Android: io.bitdrift.capture.Capture.Logger
 *   - iOS: println (bitdrift instrumented at the Swift layer)
 */
object ScreenLogger {

    fun logScreenView(screenName: String) {
        platformLogScreenView(screenName)
    }

    fun logInfo(message: String, fields: Map<String, String> = emptyMap()) {
        platformLogInfo(message, fields)
    }

    fun logError(message: String, fields: Map<String, String> = emptyMap()) {
        platformLogError(message, fields)
    }

    fun logSimulationStart(runs: Int) {
        logInfo("simulation_start", mapOf("total_runs" to runs.toString()))
    }

    fun logSimulationEnd(runs: Int) {
        logInfo("simulation_end", mapOf("total_runs" to runs.toString()))
    }
}

internal expect fun platformLogScreenView(screenName: String)
internal expect fun platformLogInfo(message: String, fields: Map<String, String>)
internal expect fun platformLogError(message: String, fields: Map<String, String>)
