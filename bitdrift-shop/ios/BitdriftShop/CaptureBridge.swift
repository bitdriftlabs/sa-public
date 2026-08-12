import Capture
import Foundation

/// SDK lifecycle and the few helpers the Swift Capture API doesn't ship that the
/// Kotlin one does. Everything else goes through `ScreenLogger`.
enum CaptureBridge {

    /// True process start time, read from the kernel.
    ///
    /// Deliberately *not* `Date()` captured in a stored property: Swift statics
    /// initialise lazily, on first access, so a `Date()` here would be stamped at
    /// the moment TTI is computed and yield ~0 (in practice a small negative
    /// value, which the SDK rejects outright). Asking the kernel makes the value
    /// independent of when it is first touched, and includes pre-`main` time —
    /// dyld, runtime setup, and the SDK's own start — which is what a
    /// time-to-interactive number is supposed to cover.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return Date()
        }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }()

    /// Time from process start to now. Returns nil if the clock produced
    /// something unusable, so callers never report a non-positive TTI.
    static var timeToInteractive: TimeInterval? {
        let elapsed = Date().timeIntervalSince(processStart)
        return elapsed > 0 ? elapsed : nil
    }

    static var sdkVersion: String { Logger.sdkVersion }

    /// Starts the Capture SDK. Must run before any logging.
    ///
    /// bitdrift SDK: `Logger.start(withAPIKey:sessionStrategy:configuration:fieldProviders:)`
    /// initialises the SDK with the API key, endpoint, session strategy, and field
    /// providers. The returned `LoggerIntegrator` is what turns on automatic
    /// URLSession capture.
    /// POC: crash detection, memory monitoring, visual performance (OOTB — no
    /// extra calls); session management.
    static func start() {
        // bitdrift SDK: `.enableIntegrations([.urlSession()])` swizzles URLSession so
        // every request and response is logged in the session timeline with no
        // per-call code. Equivalent to the Android app's automatic OkHttp
        // instrumentation via the Gradle plugin.
        // POC: network monitoring — unsampled latency, error rates, throughput per endpoint.
        Logger.start(
            withAPIKey: AppConfig.apiKey,
            sessionStrategy: .fixed(),
            configuration: .init(apiURL: AppConfig.apiURL),
            fieldProviders: [UserIDFieldProvider()]
        )?.enableIntegrations([.urlSession()])

        Logger.setEntityID("demo")

        // bitdrift SDK: logInfo() emits a structured event at app launch.
        Logger.logInfo("app_launched")

        // bitdrift SDK: addField() sets a global field attached to every log, span,
        // and network request for the lifetime of this process. Not persisted — it
        // is re-added on each start.
        // POC: insights & visualization — slice any dashboard, Workflow, or alert
        // by global field value.
        Logger.addField(withKey: "app_variant", value: "ios-sdk-demo")
        Logger.addField(withKey: "platform", value: "ios")

        reportPreviousRun()
    }

    /// Reports how the previous run ended, and where the user was when it did.
    ///
    /// This closes the gap that no in-session field can. A watchdog hang or a
    /// jetsam kill produces no log at the moment it happens — the process is
    /// simply gone, and the OS's report arrives on the *next* launch. So the
    /// screen views leading up to it live in one session and the termination is
    /// attributed to another, which is exactly why a crash-terminated Sankey
    /// cannot close for those classes.
    ///
    /// Pairing `Logger.previousRunInfo` with the last screen persisted by
    /// `ScreenLogger.logScreenView` turns an unattributable out-of-session
    /// termination into an ordinary, groupable log line in *this* session.
    ///
    /// Must run before any new screen view is logged, or the persisted value has
    /// already been overwritten with this launch's first screen.
    private static func reportPreviousRun() {
        // Snapshot and clear before doing anything else, whether or not there is a
        // previous run to report.
        //
        // The value describes the run that just ended. Leaving it in place means a
        // launch that dies *before* reaching its first screen — precisely the
        // scene-create watchdog case — inherits the previous process's screen on
        // the launch after that, instead of correctly reporting `unknown`. Clearing
        // it here is what makes the pre-screen bucket honest.
        let lastScreen = Prefs.screen.string(Prefs.keyLastScreen) ?? "unknown"
        // Cleared for the same reason as `keyLastScreen`: a stale trail carried
        // into a later launch would misattribute the path just as badly as a
        // stale final screen.
        let screenTrail = Prefs.screen.string(Prefs.keyScreenTrail) ?? "unknown"
        Prefs.screen.remove(Prefs.keyLastScreen)
        Prefs.screen.remove(Prefs.keyScreenTrail)
        Prefs.screen.flush()

        guard let info = Logger.previousRunInfo else { return }
        let fields = [
            "termination_reason": info.terminationReason.rawValue,
            "fatal": String(info.hasFatallyTerminated),
            "clean": String(info.wasCleanTermination),
            // Named distinctly from the live `last_screen` global field so a query
            // can tell "where the user is now" from "where the previous run died".
            "crashed_on_screen": lastScreen,
            // Same value again under the key `screen_visit` logs use, so a
            // workflow can compute crashes-per-visit as a grouped `rate`. A
            // grouped rate requires both sides bucketed by an identical field
            // key; `crashed_on_screen` is kept for existing charts that already
            // group by it.
            "screen": lastScreen,
            // The path the dead run took, newest first, joined by `>`. An
            // in-process crash carries this on the report itself via the
            // `screen_prev_N` global fields; a hang or jetsam kill leaves no
            // report at all, so this persisted copy is the only way those
            // terminations get a journey rather than just a final screen.
            "crashed_on_trail": screenTrail,
        ]

        if info.hasFatallyTerminated {
            ScreenLogger.logError("previous_run_terminated", fields)
        } else {
            ScreenLogger.logInfo("previous_run_terminated", fields)
        }
    }

    /// Kotlin's `Logger.trackSpan { … }` has no Swift counterpart — `startSpan`
    /// returns a `Span` the caller must end by hand. This restores the scoped
    /// form: the span ends SUCCESS on return and FAILURE if the body throws.
    ///
    /// bitdrift SDK: wraps work in a span and records its duration in the session
    /// timeline.
    /// POC: event tracking — unsampled duration histogram (p50/p95) for any operation.
    @discardableResult
    static func trackSpan<T>(
        _ name: String,
        level: LogLevel = .info,
        fields: [String: String] = [:],
        _ body: () throws -> T
    ) rethrows -> T {
        let span = Logger.startSpan(name: name, level: level, fields: ScreenLogger.encode(fields))
        do {
            let result = try body()
            span?.end(.success)
            return result
        } catch {
            span?.end(.failure)
            throw error
        }
    }
}

/// Exposes the currently signed-in `user_id` on every log.
///
/// Reading from `UserDefaults` on each call — rather than capturing the value
/// once — means the field survives `startNewSession()` and process restarts.
/// `user_id` is a special bitdrift field: when present it appears in the
/// Timeline session header.
struct UserIDFieldProvider: FieldProvider {
    func getFields() -> Fields {
        guard let id = Prefs.userSession.string(Prefs.keyUserID), !id.isEmpty else { return [:] }
        return ["user_id": id]
    }
}
