import Foundation
import os.log

/// Centralised logging for screen views and user actions. Writes to `os.log`
/// (Xcode console, debug builds only).
enum ScreenLogger {

    private static let osLogger = os.Logger(subsystem: "ai.bitdrift.shop.ios", category: "ScreenLogger")


    /// Records a screen transition. Called centrally from `Navigator` for every
    /// navigation, so it fires identically for user taps and for simulator-driven
    /// navigation.
    static func logScreenView(_ screenName: String) {
        printLog("SCREEN", "_screen_name: \(screenName)", [:])
    }

    static func logInfo(_ message: String, _ fields: [String: String] = [:]) {
        printLog("INFO", message, fields)
    }

    static func logWarning(_ message: String, _ fields: [String: String] = [:]) {
        printLog("WARNING", message, fields)
    }

    static func logError(_ message: String, _ fields: [String: String] = [:]) {
        printLog("ERROR", message, fields)
    }

    static func logError(_ message: String, error: Error, _ fields: [String: String] = [:]) {
        printLog("ERROR", message, fields.merging(["error": String(describing: error)]) { a, _ in a })
    }

    static func logSimulationStart(_ runs: Int) {
        logInfo("simulation_start", ["total_runs": String(runs)])
    }

    static func logSimulationEnd(_ runs: Int) {
        logInfo("simulation_end", ["total_runs": String(runs)])
    }


    // MARK: - Private

    private static func printLog(_ level: String, _ message: String, _ fields: [String: String]) {
        #if DEBUG
        var output = "[\(level)] \(message)"
        if !fields.isEmpty {
            output += " | " + fields.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " | ")
        }
        // Dispatch to the matching os.Logger level so Console severity filtering
        // can tell a failure from an informational event.
        switch level {
        case "ERROR":   osLogger.error("\(output, privacy: .public)")
        case "WARNING": osLogger.warning("\(output, privacy: .public)")
        default:        osLogger.info("\(output, privacy: .public)")
        }
        #endif
    }
}
