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
