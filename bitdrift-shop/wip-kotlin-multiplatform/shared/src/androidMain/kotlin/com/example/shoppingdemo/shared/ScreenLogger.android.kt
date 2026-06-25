package ai.bitdrift.shop.shared

import android.util.Log
import io.bitdrift.capture.Capture.Logger

private const val TAG = "ScreenLogger"

internal actual fun platformLogScreenView(screenName: String) {
    Log.d(TAG, "_screen_name: $screenName")
    Logger.logScreenView(screenName)
}

internal actual fun platformLogTrace(message: String, fields: Map<String, String>) {
    Log.v(TAG, formatLog("TRACE", message, fields))
    Logger.logTrace(fields) { message }
}

internal actual fun platformLogDebug(message: String, fields: Map<String, String>) {
    Log.d(TAG, formatLog("DEBUG", message, fields))
    Logger.logDebug(fields) { message }
}

internal actual fun platformLogInfo(message: String, fields: Map<String, String>) {
    Log.d(TAG, formatLog("INFO", message, fields))
    Logger.logInfo(fields) { message }
}

internal actual fun platformLogWarning(message: String, fields: Map<String, String>) {
    Log.w(TAG, formatLog("WARNING", message, fields))
    Logger.logWarning(fields) { message }
}

internal actual fun platformLogError(message: String, fields: Map<String, String>) {
    Log.e(TAG, formatLog("ERROR", message, fields))
    Logger.logError(fields) { message }
}

internal actual fun platformAddField(key: String, value: String) {
    Logger.addField(key, value)
}

internal actual fun platformRemoveField(key: String) {
    Logger.removeField(key)
}

internal actual fun platformSetEntityId(entityId: String) {
    Logger.setEntityId(entityId)
}

internal actual fun platformSetFeatureFlagExposure(name: String, variant: String) {
    Logger.setFeatureFlagExposure(name, variant)
}

private fun formatLog(level: String, message: String, fields: Map<String, String>): String =
    buildString {
        append("[$level] $message")
        if (fields.isNotEmpty()) {
            append(" | ")
            append(fields.entries.sortedBy { it.key }.joinToString(" | ") { "${it.key}=${it.value}" })
        }
    }
