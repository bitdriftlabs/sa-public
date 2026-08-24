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
        // `.activityBased` persists the session ID to disk and resumes it on the
        // next launch if the gap is under `inactivityThresholdMins`, where
        // `.fixed()` mints a fresh one on every process start.
        //
        // The reason to care: a crash the OS reports on the *next* launch is
        // emitted into whatever session is current at that moment. Under
        // `.fixed()` that is always a brand-new session, so the crash is
        // permanently divorced from the screen views that preceded it. Under
        // `.activityBased` the relaunch resumes the session that died, so the
        // crash report and the journey land together and a session timeline
        // reads as one continuous story.
        //
        // This DOES make a crash-terminal Sankey close (bd-shop-19,
        // ai.bitdrift.shop.ios: 26/26 flow completions matched exactly against
        // a standalone crash count). The fatal issue handler reads the crash
        // report on the next launch and replays it into the timeline carrying
        // a snapshot of the field state from the moment of death; under
        // .fixed() that replay lands in a brand-new session, disconnected from
        // whatever flow was mid-progress when the process died, and the flow
        // can never see it. Under .activityBased() the replay lands inside the
        // SAME session the flow was already walking, and it closes.
        //
        // The dependency this creates: it only works if the relaunch lands
        // within `inactivityThresholdMins` of the crash. A slow relaunch ages
        // the session out and you are back to a `.fixed()`-shaped empty Sankey
        // with no visible change in configuration — test your own relaunch
        // latency against the default 30 min before relying on this.
        //
        // Untested: whether the same mechanism closes a flow for
        // APP_IOS_BUILT_IN_ANR (hangs) — plausible, since it is the same
        // fatal-issue-handler family, but not verified. `unknown` screen
        // attribution in bd-shop-18's Ripsaw script is a separate,
        // field-existence question, not a session one: OOM/jetsam kills have
        // no distinct ExitReason on iOS at all (PreviousRunInfo's enum has no
        // memory-pressure value), so they may never get this treatment
        // regardless of session strategy.
        //
        // 30 minutes is the SDK default. During a crash loop that merges many
        // journeys into one long session, which is good for testing continuity
        // and worse for reading any single journey in isolation.
        Logger.start(
            withAPIKey: AppConfig.apiKey,
            sessionStrategy: .activityBased(),
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

        // bitdrift SDK: opens the `app_cold_start` root span plus its `sdk_init`
        // child. Everything this method did above — Logger.start() itself,
        // setEntityID, addField, reportPreviousRun — is what `sdk_init` measures,
        // so this must be the last line of `start()`, not the first.
        // POC: event tracking — granular per-phase P50/P90/P99 cold-start
        // histograms plus a Timeline waterfall, instead of one opaque TTI number.
        // See `ColdStartSpans` below and `bd-shop-20` in workflows/.
        ColdStartSpans.beginRoot()
    }

    /// Reports how the previous run ended, and where the user was when it did.
    ///
    /// This closes a gap the shift register alone cannot: a watchdog hang or a
    /// jetsam kill produces no log at the moment it happens — the process is
    /// simply gone, and the OS's report arrives on the *next* launch, with no
    /// in-process field snapshot to fall back on. Under `.activityBased()`
    /// that report can still land in the resumed session (same as the crash
    /// case in `start()`), but whether the OOTB `APP_IOS_BUILT_IN_ANR`
    /// condition replays a field snapshot the way `APP_IOS_BUILT_IN_CRASH`
    /// does — and so whether a flow can close on a hang the same way — is
    /// untested. OOM/jetsam kills have no distinct `ExitReason` on iOS at all,
    /// so `Logger.previousRunInfo` cannot even distinguish them from `unknown`.
    ///
    /// Pairing `Logger.previousRunInfo` with the last screen persisted by
    /// `ScreenLogger.logScreenView` gives every termination class an ordinary,
    /// groupable log line regardless of which of the above is true for it.
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
    /// `parentSpanID` nests this span under a caller-supplied parent (e.g. a
    /// SimulationManager journey/discovery/checkout span). The body closure
    /// receives the span itself so *its* children can nest further, in turn,
    /// by passing `span?.id` down — see `RecommendationEngine.scoreProducts`'s
    /// `parse_catalog`/`similarity_pass` children for an example.
    ///
    /// bitdrift SDK: wraps work in a span and records its duration in the session
    /// timeline.
    /// POC: event tracking — unsampled duration histogram (p50/p95) for any operation.
    @discardableResult
    static func trackSpan<T>(
        _ name: String,
        level: LogLevel = .info,
        fields: [String: String] = [:],
        parentSpanID: UUID? = nil,
        _ body: (Span?) throws -> T
    ) rethrows -> T {
        let span = Logger.startSpan(
            name: name, level: level, fields: ScreenLogger.encode(fields), parentSpanID: parentSpanID
        )
        do {
            let result = try body(span)
            span?.end(.success)
            return result
        } catch {
            span?.end(.failure)
            throw error
        }
    }

    /// `async` counterpart of `trackSpan(_:level:fields:parentSpanID:_:)` — for wrapping a
    /// SwiftUI `.task` body (or any other `await`-ing operation) instead of purely synchronous
    /// work. Same semantics: SUCCESS on return, FAILURE on throw, span passed into the body for
    /// further nesting.
    @discardableResult
    static func trackSpan<T>(
        _ name: String,
        level: LogLevel = .info,
        fields: [String: String] = [:],
        parentSpanID: UUID? = nil,
        _ body: (Span?) async throws -> T
    ) async rethrows -> T {
        let span = Logger.startSpan(
            name: name, level: level, fields: ScreenLogger.encode(fields), parentSpanID: parentSpanID
        )
        do {
            let result = try await body(span)
            span?.end(.success)
            return result
        } catch {
            // A cancelled SwiftUI `.task` (view disappeared, or its `id` changed) is not a
            // failure, and its partial duration would skew a latency histogram if recorded
            // as one — `SpanResult.canceled` keeps those distinguishable from real errors.
            // Both spellings matter: URLSession throws `CancellationError` when the Task is
            // already cancelled before the request starts, but `URLError.cancelled` when an
            // in-flight request is torn down.
            span?.end(Self.isCancellation(error) ? .canceled : .failure)
            throw error
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

/// Breaks cold start into a span waterfall instead of the single opaque number
/// `CaptureBridge.timeToInteractive` reports: one root span covering the whole sequence,
/// with a child span per phase.
///
/// bitdrift SDK: `startSpan(parentSpanID:)` nests spans into a hierarchy (Spans docs,
/// "Spans Hierarchy") so the whole sequence renders as one waterfall in Timeline instead of
/// unrelated flat spans. `startTimeInterval`/`endTimeInterval` back-date a span's recorded
/// duration to an instant before the `Span` object itself could exist — used here for `root`
/// and `sdk_init`, both of which need to start at the real kernel process-start time
/// (`CaptureBridge.processStart`), which is earlier than `Logger.start()` and therefore
/// earlier than the first moment any span can be created at all. Per `Span.end(...)`, the
/// custom-duration math only applies when *both* the start and end times passed to a given
/// span are custom — passing only one silently falls back to the default (real-time-elapsed)
/// clock, so `root`'s `.end()` call below must pass `endTimeInterval` explicitly even though
/// its own creation already carried a custom start time.
///
/// POC: event tracking — per-phase P50/P90/P99 histograms (Workflow > Histogram action on
/// `_duration_ms`, one flow per phase, plus a combined flow grouped by `_span_name` for
/// side-by-side comparison) instead of a single TTI number, and a Timeline waterfall showing
/// where a given cold start's time actually went. See `bd-shop-20` in `workflows/`.
enum ColdStartSpans {
    private static var root: Span?
    private static var currentPhase: Span?

    /// Opens `root` and its `sdk_init` child. Must run as the very last line of
    /// `CaptureBridge.start()` — everything that method did (the `Logger.start()` call
    /// itself, `setEntityID`, `addField`, `reportPreviousRun`) is what `sdk_init` measures,
    /// and a span cannot be created before the SDK it will be measuring has started.
    static func beginRoot() {
        root = Logger.startSpan(
            name: "app_cold_start",
            level: .info,
            fields: [:],
            startTimeInterval: CaptureBridge.processStart.timeIntervalSince1970
        )

        // Both endpoints of `sdk_init` are already known at this point (process start, and
        // "now"), so it is created and ended in the same call rather than left open like the
        // phases below.
        let now = Date().timeIntervalSince1970
        Logger.startSpan(
            name: "app_cold_start.sdk_init",
            level: .info,
            fields: [:],
            startTimeInterval: CaptureBridge.processStart.timeIntervalSince1970,
            parentSpanID: root?.id
        )?.end(.success, endTimeInterval: now)

        // Opens for real, right now — everything from here (SwiftUI standing up the
        // WindowGroup, laying out the first frame, dispatching the `.task` that runs
        // `ContentView.runStartupSequence()`) needs no back-dating.
        currentPhase = Logger.startSpan(
            name: "app_cold_start.scene_render",
            level: .info,
            parentSpanID: root?.id
        )
    }

    /// Ends `scene_render` and opens `state_restore`. Must be the **first** statement of
    /// `ContentView.runStartupSequence()` — before `nav.logInitialScreen()`, and therefore
    /// before the `logAppLaunchTTI` call too. `logInitialScreen()` reaches
    /// `ScreenLogger.logScreenView`, which does a UserDefaults write + `synchronize()` (the
    /// `screen_view_persist` span): that is prefs bookkeeping, so it belongs to
    /// `state_restore`. Calling this any later charges that cost to `scene_render` instead.
    static func advanceToStateRestore() {
        currentPhase?.end(.success)
        currentPhase = Logger.startSpan(
            name: "app_cold_start.state_restore",
            level: .info,
            parentSpanID: root?.id
        )
    }

    /// Ends `state_restore` and `root` together. Call once per launch, on whichever path
    /// `runStartupSequence()` takes: the fast-crash branch calls it just before returning,
    /// and the normal path calls it after the resume-branch restoration (pending
    /// crash/hang/quit prefs, `restoreVariantFromPrefs()`) and the simplified-journey
    /// auto-start trigger — all still persisted-state restoration — but *before* the
    /// auto-start retry/sleep loop, which is the app running rather than starting up.
    static func finish() {
        currentPhase?.end(.success)
        currentPhase = nil
        // `root` was created with a custom *start* time, so its `.end()` needs an explicit
        // custom *end* time too, or the duration silently reverts to the default clock (see
        // the type doc above).
        root?.end(.success, endTimeInterval: Date().timeIntervalSince1970)
        root = nil
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
