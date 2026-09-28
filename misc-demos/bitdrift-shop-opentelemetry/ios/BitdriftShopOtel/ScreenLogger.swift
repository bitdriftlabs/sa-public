import Capture
import Foundation
import os.log

/// Centralized logging for screen views and user actions — mirrors `ScreenLogger.kt`. Both the
/// debug console line and the real bitdrift SDK call happen here so every call site (all 15
/// screens plus `SimulationManager`) gets both automatically.
enum ScreenLogger {
    private static let osLogger = os.Logger(subsystem: "ai.bitdrift.oteldemo", category: "ScreenLogger")

    static func logScreenView(_ screenName: String) {
        printLog("SCREEN", "_screen_name: \(screenName)", [:])
        Capture.Logger.shared?.logScreenView(screenName: screenName)
    }

    static func logInfo(_ message: String, _ fields: [String: String] = [:]) {
        printLog("INFO", message, fields)
        Capture.Logger.shared?.logInfo(message, fields: fields)
    }

    static func logWarning(_ message: String, _ fields: [String: String] = [:]) {
        printLog("WARNING", message, fields)
        Capture.Logger.shared?.logWarning(message, fields: fields)
    }

    static func logError(_ message: String, _ fields: [String: String] = [:]) {
        printLog("ERROR", message, fields)
        Capture.Logger.shared?.logError(message, fields: fields)
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
        osLogger.debug("\(output, privacy: .public)")
        #endif
    }
}
