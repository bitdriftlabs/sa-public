package ai.bitdrift.shop

import ai.bitdrift.shop.BuildConfig
import android.util.Log
import io.bitdrift.capture.Capture.Logger

/**
 * Centralized logging for screen views and user actions.
 */
object ScreenLogger {

    private const val TAG = "ScreenLogger"

    fun logScreenView(screenName: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, "_screen_name: $screenName")
        // bitdrift SDK: logScreenView() records the transition so it appears as a breadcrumb in
        // session timelines and powers Sankey diagrams in the dashboard. Called automatically for
        // every navigation via OnDestinationChangedListener in MainActivity.
        // POC: User Journey Sankey diagram; per-screen crash analytics
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
        if (!BuildConfig.DEBUG) return
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
