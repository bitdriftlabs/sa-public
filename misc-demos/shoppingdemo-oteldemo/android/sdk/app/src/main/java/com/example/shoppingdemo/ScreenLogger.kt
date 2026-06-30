package com.example.shoppingdemo

import android.util.Log
import io.bitdrift.capture.Capture.Logger

/**
 * Centralized logging for screen views and user actions.
 */
object ScreenLogger {

    private const val TAG = "ScreenLogger"

    fun logScreenView(screenName: String) {
        Log.d(TAG, "_screen_name: $screenName")
        // Workshop 2 (Screen Views): log each screen transition to bitdrift so it
        // appears as a breadcrumb in user journeys and powers Sankey diagrams in the dashboard.
        // https://docs.bitdrift.io/sdk/quickstart#android
        //
        // ScreenContainer already calls ScreenLogger.logScreenView via DisposableEffect for
        // every screen — it was previously only using Log.d. Wiring in Logger.logScreenView()
        // here is the single change that covers all 15 screens automatically.
        Logger.logScreenView(screenName)
    }

    fun logInfo(message: String, fields: Map<String, String> = emptyMap()) {
        printLog("INFO", message, fields)
        Logger.logInfo(fields) { message }
    }

    fun logError(message: String, fields: Map<String, String> = emptyMap()) {
        printLog("ERROR", message, fields)
        Logger.logError(fields) { message }
    }

    fun logSimulationStart(runs: Int) {
        logInfo("simulation_start", mapOf("total_runs" to runs.toString()))
    }

    fun logSimulationEnd(runs: Int) {
        logInfo("simulation_end", mapOf("total_runs" to runs.toString()))
    }

    private fun printLog(level: String, message: String, fields: Map<String, String>) {
        val output = buildString {
            append("[$level] $message")
            if (fields.isNotEmpty()) {
                append(" | ")
                append(fields.entries.sortedBy { it.key }.joinToString(" | ") { "${it.key}=${it.value}" })
            }
        }
        Log.d(TAG, output)
    }
}
