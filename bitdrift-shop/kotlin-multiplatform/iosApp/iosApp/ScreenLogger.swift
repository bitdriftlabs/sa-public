import Foundation
import Capture
import os.log

// Centralised logging that writes to both os.log (local console) and the
// bitdrift dashboard.  All screen transitions and key events flow through here.
enum ScreenLogger {
    private static let osLogger = os.Logger(
        subsystem: "com.example.shoppingdemo.kmp",
        category: "ScreenLogger"
    )

    // Called by ScreenContainer.onAppear for every screen transition.
    static func logScreenView(_ screenName: String) {
        osLogger.info("_screen_name: \(screenName)")
        Logger.logScreenView(screenName: screenName)
    }

    static func logInfo(_ message: String, fields: [String: String] = [:]) {
        printLog("INFO", message, fields)
        Logger.logInfo(message, fields: fields)
    }

    static func logWarning(_ message: String, fields: [String: String] = [:]) {
        printLog("WARNING", message, fields)
        Logger.logWarning(message, fields: fields)
    }

    static func logError(_ message: String, fields: [String: String] = [:]) {
        printLog("ERROR", message, fields)
        Logger.logError(message, fields: fields)
    }

    static func logError(_ message: String, error: Error, fields: [String: String] = [:]) {
        printLog("ERROR", message, fields)
        Logger.logError(message, error: error, fields: fields)
    }

    // MARK: - Private

    private static func printLog(_ level: String, _ message: String, _ fields: [String: String]) {
        var output = "[\(level)] \(message)"
        if !fields.isEmpty {
            let sorted = fields.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " | ")
            output += " | \(sorted)"
        }
        osLogger.info("\(output)")
    }
}
