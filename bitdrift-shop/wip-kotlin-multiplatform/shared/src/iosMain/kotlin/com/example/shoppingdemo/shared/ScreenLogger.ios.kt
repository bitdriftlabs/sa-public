package ai.bitdrift.shop.shared

// iOS bitdrift instrumentation is at the Swift layer (ScreenLogger.swift / ShoppingDemoKMPApp.swift).
// Kotlin-side actuals write to stdout for local debugging only.

internal actual fun platformLogScreenView(screenName: String) {
    println("[SCREEN] _screen_name: $screenName")
}

internal actual fun platformLogTrace(message: String, fields: Map<String, String>) {
    println(formatLog("TRACE", message, fields))
}

internal actual fun platformLogDebug(message: String, fields: Map<String, String>) {
    println(formatLog("DEBUG", message, fields))
}

internal actual fun platformLogInfo(message: String, fields: Map<String, String>) {
    println(formatLog("INFO", message, fields))
}

internal actual fun platformLogWarning(message: String, fields: Map<String, String>) {
    println(formatLog("WARNING", message, fields))
}

internal actual fun platformLogError(message: String, fields: Map<String, String>) {
    println(formatLog("ERROR", message, fields))
}

// On iOS, field/entity/flag management is performed at the Swift layer.
internal actual fun platformAddField(key: String, value: String) {}
internal actual fun platformRemoveField(key: String) {}
internal actual fun platformSetEntityId(entityId: String) {}
internal actual fun platformSetFeatureFlagExposure(name: String, variant: String) {}

private fun formatLog(level: String, message: String, fields: Map<String, String>): String =
    buildString {
        append("[$level] $message")
        if (fields.isNotEmpty()) {
            append(" | ")
            append(fields.entries.sortedBy { it.key }.joinToString(" | ") { "${it.key}=${it.value}" })
        }
    }
