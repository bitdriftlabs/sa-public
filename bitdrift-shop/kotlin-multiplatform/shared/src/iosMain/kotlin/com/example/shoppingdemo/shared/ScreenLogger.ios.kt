package com.example.shoppingdemo.shared

// iOS bitdrift instrumentation is handled at the Swift layer (ShoppingDemoKMPApp.swift).
// Kotlin-side logging writes to the standard output for local debugging.

internal actual fun platformLogScreenView(screenName: String) {
    println("[SCREEN] _screen_name: $screenName")
}

internal actual fun platformLogInfo(message: String, fields: Map<String, String>) {
    println(formatLog("INFO", message, fields))
}

internal actual fun platformLogError(message: String, fields: Map<String, String>) {
    println(formatLog("ERROR", message, fields))
}

private fun formatLog(level: String, message: String, fields: Map<String, String>): String =
    buildString {
        append("[$level] $message")
        if (fields.isNotEmpty()) {
            append(" | ")
            append(fields.entries.sortedBy { it.key }.joinToString(" | ") { "${it.key}=${it.value}" })
        }
    }
