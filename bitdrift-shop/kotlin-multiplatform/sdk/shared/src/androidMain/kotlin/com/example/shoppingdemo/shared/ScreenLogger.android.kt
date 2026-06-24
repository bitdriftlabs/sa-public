package com.example.shoppingdemo.shared

import android.util.Log
import io.bitdrift.capture.Capture.Logger

private const val TAG = "ScreenLogger"

internal actual fun platformLogScreenView(screenName: String) {
    Log.d(TAG, "_screen_name: $screenName")
    Logger.logScreenView(screenName)
}

internal actual fun platformLogInfo(message: String, fields: Map<String, String>) {
    Log.d(TAG, formatLog("INFO", message, fields))
    Logger.logInfo(fields) { message }
}

internal actual fun platformLogError(message: String, fields: Map<String, String>) {
    Log.e(TAG, formatLog("ERROR", message, fields))
    Logger.logError(fields) { message }
}

private fun formatLog(level: String, message: String, fields: Map<String, String>): String =
    buildString {
        append("[$level] $message")
        if (fields.isNotEmpty()) {
            append(" | ")
            append(fields.entries.sortedBy { it.key }.joinToString(" | ") { "${it.key}=${it.value}" })
        }
    }
