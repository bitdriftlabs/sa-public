package ai.bitdrift.shop

import android.util.Log

/**
 * Centralized logging for screen views and user actions.
 */
object ScreenLogger {

    private const val TAG = "ScreenLogger"

    fun logInfo(message: String, fields: Map<String, String> = emptyMap()) {
        printLog("INFO", message, fields)
    }

    fun logInfo(fields: Map<String, String> = emptyMap(), message: () -> String) {
        logInfo(message(), fields)
    }

    fun logError(message: String, fields: Map<String, String> = emptyMap()) {
        printLog("ERROR", message, fields)
    }

    fun logError(fields: Map<String, String> = emptyMap(), message: () -> String) {
        logError(message(), fields)
    }

    fun logError(fields: Map<String, String> = emptyMap(), throwable: Throwable? = null, message: () -> String) {
        logError(message(), fields + (throwable?.let { mapOf("error" to (it.message ?: it.javaClass.simpleName)) } ?: emptyMap()))
    }

    fun logWarning(fields: Map<String, String> = emptyMap(), message: () -> String) {
        printLog("WARN", message(), fields)
    }

    fun addField(key: String, value: String) = Unit
    fun removeField(key: String) = Unit

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
