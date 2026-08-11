import Capture
import Foundation
import os.log

/// Centralised logging for screen views and user actions. Every call writes to
/// both `os.log` (Xcode console, debug builds only) and bitdrift.
enum ScreenLogger {

    private static let osLogger = os.Logger(subsystem: "ai.bitdrift.shop.ios", category: "ScreenLogger")

    /// bitdrift SDK: logScreenView() records the transition so it appears as a
    /// breadcrumb in session timelines and powers Sankey diagrams in the
    /// dashboard. Called centrally from `Navigator` for every navigation, so it
    /// fires identically for user taps and for simulator-driven navigation.
    /// POC: User Journey Sankey diagram; per-screen crash analytics.
    static func logScreenView(_ screenName: String) {
        printLog("SCREEN", "_screen_name: \(screenName)", [:])
        Logger.logScreenView(screenName: screenName)

        // Also carry the screen as a *global field*, not just a breadcrumb.
        //
        // `logScreenView` writes one event into the session timeline, which is
        // fine to read by hand but cannot be aggregated: answering "which screen
        // were users on when we crashed" would mean correlating two events across
        // a session, and a crash report frequently is not in the same session as
        // the screen views preceding it. A global field rides along on every
        // subsequent log *and on the crash report itself*, so crashes can simply
        // be grouped by `last_screen`.
        Logger.addField(withKey: "last_screen", value: screenName)

        // A plain log carrying the screen under a key that the termination log
        // also uses (`screen`). This exists purely so a workflow can compute a
        // *rate* — crashes on a screen divided by visits to that screen.
        //
        // A grouped `rate` needs its numerator and denominator bucketed by the
        // same field key, and the two sides otherwise disagree: screen views
        // carry the SDK-owned `_screen_name`, while `previous_run_terminated`
        // carries `crashed_on_screen`. Neither can be renamed, so this emits a
        // third log whose key matches both sides deliberately.
        //
        // Without it the crash *rate* per screen cannot be charted natively and
        // a reader has to divide two charts by hand — which buries the one
        // number that distinguishes a risky screen from a merely popular one.
        logInfo("screen_visit", ["screen": screenName])

        // Persisted for the next launch: an out-of-session termination (watchdog
        // hang, jetsam kill) carries no field at all, so the only way to attribute
        // it is to remember where we were and report it after the restart.
        //
        // Flushed, unlike an ordinary preference write. This value exists purely to
        // survive the process dying abruptly, so an unflushed write can lose the
        // newest screen and attribute the next launch to a stale one — the same
        // reason every crash-state write in DemoPrefs flushes.
        Prefs.screen.set(Prefs.keyLastScreen, screenName)
        Prefs.screen.flush()
    }

    static func logInfo(_ message: String, _ fields: [String: String] = [:]) {
        printLog("INFO", message, fields)
        Logger.logInfo(message, fields: encode(fields))
    }

    static func logWarning(_ message: String, _ fields: [String: String] = [:]) {
        printLog("WARNING", message, fields)
        Logger.logWarning(message, fields: encode(fields))
    }

    static func logError(_ message: String, _ fields: [String: String] = [:]) {
        printLog("ERROR", message, fields)
        Logger.logError(message, fields: encode(fields))
    }

    /// bitdrift SDK: logError() with an error captures the failure in the session
    /// timeline alongside its fields.
    static func logError(_ message: String, error: Error, _ fields: [String: String] = [:]) {
        printLog("ERROR", message, fields)
        Logger.logError(message, fields: encode(fields), error: error)
    }

    static func logSimulationStart(_ runs: Int) {
        logInfo("simulation_start", ["total_runs": String(runs)])
    }

    static func logSimulationEnd(_ runs: Int) {
        logInfo("simulation_end", ["total_runs": String(runs)])
    }

    // MARK: - Field helpers

    /// `Capture.Fields` is `[String: any Encodable & Sendable]`; the app builds
    /// plain `[String: String]` everywhere, so widen it in one place.
    static func encode(_ fields: [String: String]) -> Fields? {
        fields.isEmpty ? nil : fields.mapValues { $0 as any Encodable & Sendable }
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
        osLogger.info("\(output, privacy: .public)")
        #endif
    }
}
