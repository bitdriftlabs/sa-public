import Foundation
import os.log

/// Centralised logging for screen views and user actions. Every call writes to
/// both `os.log` (Xcode console, debug builds only) and bitdrift.
enum ScreenLogger {

    private static let osLogger = os.Logger(subsystem: "ai.bitdrift.shop.ios", category: "ScreenLogger")

    /// Depth of the screen shift register — the current screen plus
    /// `screenTrailDepth - 1` previous ones.
    ///
    /// **Five is a deliberate ceiling, not a default to tune upward.** Every
    /// entry becomes a *global field*, and global fields attach to EVERY
    /// subsequent log, not just the crash report. Five means five extra
    /// key-values on every log line the app emits — already a real cost at
    /// production volume. Anyone reading this pattern as "capture the whole
    /// journey" and raising it to 100 would multiply the size of their entire
    /// telemetry stream to answer a question that only needs the tail of it.
    ///
    /// The recent path is what makes a crash actionable; the full journey is a
    /// different problem with a different tool — session timelines, or the
    /// single joined `keyScreenTrail` breadcrumb, which costs one field no
    /// matter how long it gets. If you need more history, lengthen that string
    /// rather than adding more fields.
    private static let screenTrailDepth = 5

    /// The most recent screens, newest first. Persisted so the next launch can
    /// report the path taken before an abrupt termination.
    private static var recentScreens: [String] = []

    /// Records a screen transition. Called centrally from `Navigator` for every
    /// navigation, so it fires identically for user taps and for simulator-driven
    /// navigation.
    static func logScreenView(_ screenName: String) {
        printLog("SCREEN", "_screen_name: \(screenName)", [:])

        // Shift register of the last `screenTrailDepth` screens, newest first.
        // Answers "how did they get here" on the launch after an abrupt termination.
        // Collapse consecutive repeats of the same screen. `Navigator` legitimately
        // logs the same screen twice in a row — `logInitialScreen()` on launch and
        // `popToWelcome()` at journey start both emit Welcome — and a user
        // bouncing on one screen does the same. Without this, duplicates consume
        // slots in a fixed-depth register and push real history off the end, so a
        // crash report shows `Welcome/Welcome/none/none/none` instead of the path
        // actually taken. The screen is still re-registered as a global field
        // below either way; only the trail skips the redundant entry.
        if recentScreens.first != screenName {
            recentScreens.insert(screenName, at: 0)
            if recentScreens.count > screenTrailDepth {
                recentScreens.removeLast()
            }
        }

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
        //
        Prefs.screen.set(Prefs.keyLastScreen, screenName)
        // Same reasoning for the trail: it must survive the process dying, so a
        // watchdog hang or jetsam kill still reports the path. Newest-first, joined.
        Prefs.screen.set(Prefs.keyScreenTrail, recentScreens.joined(separator: ">"))
        Prefs.screen.flush()
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
        osLogger.info("\(output, privacy: .public)")
        #endif
    }
}
