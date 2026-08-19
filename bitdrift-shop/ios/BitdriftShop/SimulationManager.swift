import Capture
import Foundation
import UIKit

/// Drives `setFeatureFlagExposure()` calls so every log in a run is tagged with
/// the active cohort, enabling dashboard slicing by `checkout_flow`,
/// `payment_ui`, and `cart_abandon_rate`.
enum SimVariant: String, CaseIterable {
    case control       // baseline: fully random, no variant bias
    case variantA      // digital native: snap decisions, skips research, guest + digital pay
    case variantB      // deliberate shopper: reads everything, huge cart churn, signin + card

    var label: String {
        switch self {
        case .control: return "Control"
        case .variantA: return "Variant A"
        case .variantB: return "Variant B"
        }
    }
}

/// Automated simulation of user journeys through the app. Randomly selects
/// paths at each decision point to generate varied journey data.
///
/// The probabilities, event names, field names and span structure are identical
/// to the Android app's, so both platforms feed the same `bd-shop-*` workflows.
@MainActor
final class SimulationManager: ObservableObject {

    @Published private(set) var isSimulating = false
    @Published private(set) var currentRun = 0
    @Published private(set) var totalRuns = 0
    @Published private(set) var activeVariant: SimVariant = .control

    @Published var recommendationsV2Enabled = false
    @Published var crashLoopEnabled = false

    /// Fast crash mode: skips the shopping journey entirely and fires the next
    /// crash combo immediately on every relaunch (see `fireFastCrash`). Selected
    /// on the startup config screen alongside `crashLoopEnabled`, not from
    /// Advanced settings.
    @Published var fastCrashModeEnabled = false

    /// Surfaces what `fireFastCrash()` is about to do so the UI can show a
    /// full-screen splash instead of looking hung — fast mode skips all
    /// navigation and UI by design, so without this there is no on-device signal
    /// distinguishing "about to crash in 300ms" from "stuck".
    struct FastCrashStatus {
        let kind: String
        let context: String
        let oomOnly: Bool
    }

    @Published private(set) var fastCrashStatus: FastCrashStatus?

    /// Main-thread hang injection. Named `anr_a` in every log field and feature
    /// flag for parity with Android, where this is an ANR — iOS has no ANR, the
    /// equivalent fault is a main-thread hang picked up by MetricKit.
    @Published var appHangEnabled = false

    @Published var forceQuitEnabled = false

    /// True while a background-half crash is armed and the app is still in the
    /// foreground. Surfaced on the fast-crash splash so it is obvious the app is
    /// waiting to be backgrounded rather than stuck.
    @Published private(set) var awaitingBackground = false

    private var pendingBackgroundCrash: (() -> Void)?
    private var backgroundObserver: NSObjectProtocol?

    /// Where in a journey a crash is allowed to fire.
    ///
    /// Firing every crash at Confirmation — as this used to — makes crash data
    /// useless for the question teams actually ask, which is *where in the funnel
    /// are we losing people*. Every issue would report the same last screen, and
    /// the Sankey would show a single crash point that says nothing.
    ///
    /// All the points sit in the back half deliberately: a crash on the Welcome
    /// screen is not a realistic e-commerce failure and would drown out the
    /// checkout-and-payment region that matters. The chosen point is recorded on
    /// the crash as `crash_journey_point`, so issues can be grouped by it.
    private enum JourneyCrashPoint: String, CaseIterable {
        case cart
        case checkout
        case payment
        case paymentFailed = "payment_failed"
        case confirmation
    }

    private var journeyCrashPoint: JourneyCrashPoint = .confirmation
    private var crashFiredThisJourney = false

    private var eligibleForceQuitJourneysSinceInject = 0
    private var eligibleHangGuestJourneysSinceInject = 0

    private var isCancelled = false
    private var runTask: Task<Void, Never>?

    /// Delay between navigation steps.
    private let stepDelay: TimeInterval = 0.05

    /// Infinite simulation mode (`-1` means infinite).
    var isInfiniteMode: Bool { totalRuns == -1 }

    // MARK: - Feature flag exposure

    /// bitdrift SDK: setFeatureFlagExposure() records the variant choice at the
    /// moment it is selected, tagging all subsequent logs with the active flag
    /// values for dashboard slicing.
    /// POC: insights & visualization — A/B cohort comparison in dashboards,
    /// Workflows, and alerts.
    func setVariant(_ variant: SimVariant) {
        activeVariant = variant

        let checkoutFlow: String
        let paymentUI: String
        let cartAbandon: String
        let androidPay: String
        switch variant {
        case .control:  checkoutFlow = "random"; paymentUI = "random";  cartAbandon = "medium"; androidPay = "enabled"
        case .variantA: checkoutFlow = "guest";  paymentUI = "digital"; cartAbandon = "high";   androidPay = "enabled"
        case .variantB: checkoutFlow = "signin"; paymentUI = "card";    cartAbandon = "low";    androidPay = "disabled"
        }

        // Feature flag exposures are per-session and trigger workflow transitions.
        Logger.setFeatureFlagExposure(withName: "checkout_flow", variant: checkoutFlow)
        Logger.setFeatureFlagExposure(withName: "payment_ui", variant: paymentUI)
        Logger.setFeatureFlagExposure(withName: "cart_abandon_rate", variant: cartAbandon)
        // Also set as global fields so every log carries the active flag values.
        Logger.addField(withKey: "ff_checkout_flow", value: checkoutFlow)
        Logger.addField(withKey: "ff_payment_ui", value: paymentUI)
        Logger.addField(withKey: "ff_cart_abandon_rate", value: cartAbandon)
        Logger.addField(withKey: "ff_variant", value: variant.label)

        Logger.setFeatureFlagExposure(withName: "payment_android_pay", variant: androidPay)
        Logger.addField(withKey: "ff_payment_android_pay", value: androidPay)

        let orderSummary = crashLoopEnabled ? "v2" : "v1"
        Logger.setFeatureFlagExposure(withName: "order_summary", variant: orderSummary)
        Logger.addField(withKey: "ff_order_summary", value: orderSummary)

        let hangState = appHangEnabled ? "enabled" : "disabled"
        Logger.setFeatureFlagExposure(withName: "anr_a", variant: hangState)
        Logger.addField(withKey: "ff_anr_a", value: hangState)

        let forceQuitState = forceQuitEnabled ? "enabled" : "disabled"
        Logger.setFeatureFlagExposure(withName: "force_quit", variant: forceQuitState)
        Logger.addField(withKey: "ff_force_quit", value: forceQuitState)

        let recommendationsV2State = recommendationsV2Enabled ? "enabled" : "disabled"
        Logger.setFeatureFlagExposure(withName: "recommendations_v2", variant: recommendationsV2State)
        Logger.addField(withKey: "ff_recommendations_v2", value: recommendationsV2State)

        // Explicit log so flag exposure is verifiable in the raw log stream.
        ScreenLogger.logInfo("feature_flag_exposure_set")

        // Every Advanced-screen toggle routes through here, so this is the one
        // hook that keeps the on-disk state the scripts read in step with the UI.
        DemoStateFile.publish()
    }

    // MARK: - Persisted state sync

    func syncAppHangEnabledState() {
        appHangEnabled = Prefs.appHang.bool(Prefs.keyActive)
    }

    func syncForceQuitEnabledState() {
        forceQuitEnabled = Prefs.forceQuit.bool(Prefs.keyActive)
    }

    func restoreVariantFromPrefs() {
        var variantName = Prefs.appHang.string(Prefs.keyRestartVariant)
        if variantName != nil {
            Prefs.appHang.remove(Prefs.keyRestartVariant)
        } else {
            variantName = Prefs.forceQuit.string(Prefs.keyRestartVariant)
            if variantName != nil { Prefs.forceQuit.remove(Prefs.keyRestartVariant) }
        }
        guard let variantName, let variant = SimVariant(rawValue: variantName) else { return }
        setVariant(variant)
    }

    func cancel() {
        isCancelled = true
        ScreenLogger.logInfo("simulation_cancelled", [
            "completed_runs": String(currentRun),
            "total_runs": String(totalRuns),
        ])
    }

    // MARK: - Auto start

    private enum AutoStartMode { case none, single, infinite }

    private var pendingAutoStartMode = AutoStartMode.none

    func scheduleAutoStart() { pendingAutoStartMode = .single }

    func scheduleAutoStartInfinite() { pendingAutoStartMode = .infinite }

    func tryAutoStart(_ nav: Navigator) {
        switch pendingAutoStartMode {
        case .none:
            return
        case .single:
            pendingAutoStartMode = .none
            simulate(runs: 1, nav: nav)
        case .infinite:
            pendingAutoStartMode = .none
            infiniteSimulate(nav: nav)
        }
    }

    // MARK: - Simulation entry points

    /// Runs the simulation for a specified number of journeys.
    func simulate(runs: Int, nav: Navigator) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = runs
            self.currentRun = 0
            ScreenLogger.logSimulationStart(runs)

            for i in 1...max(runs, 1) {
                if self.isCancelled { break }
                self.currentRun = i
                await self.runSingleJourney(nav)
                if self.isCancelled { break }
                await self.sleep(0.05)
            }

            ScreenLogger.logSimulationEnd(self.isCancelled ? self.currentRun : runs)
            self.finish(nav)
        }
    }

    /// A/B split sim: runs `runsEach` journeys as each variant in sequence. Each
    /// run is a flag transition, maximising workflow matches in the dashboard.
    func abSimulate(runsEach: Int, nav: Navigator) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = runsEach * SimVariant.allCases.count
            self.currentRun = 0

            ScreenLogger.logInfo("ab_simulation_start", ["runs_each": String(runsEach)])

            let variants = SimVariant.allCases
            for i in 0..<self.totalRuns {
                if self.isCancelled { break }
                self.activeVariant = variants[i % variants.count]
                self.currentRun += 1
                await self.runSingleJourney(nav)
                await self.sleep(0.05)
            }

            ScreenLogger.logInfo("ab_simulation_end", ["total_runs": String(self.currentRun)])
            self.finish(nav)
        }
    }

    /// Runs infinite simulation until cancelled.
    func infiniteSimulate(nav: Navigator) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = -1
            self.currentRun = 0

            // With the crash loop enabled, persist a resume flag so the watchdog
            // relaunch picks the infinite loop back up after each crash.
            if self.crashLoopEnabled {
                Prefs.crashLoop.set(Prefs.keyResumeInfiniteWithCrash, true)
                Prefs.crashLoop.set(Prefs.keyRestartVariant, self.activeVariant.rawValue)
                Prefs.crashLoop.flush()
            }

            ScreenLogger.logInfo("infinite_simulation_start")

            while !self.isCancelled {
                self.currentRun += 1
                await self.runSingleJourney(nav)
                await self.sleep(0.05)
            }

            ScreenLogger.logInfo("infinite_simulation_end", ["total_runs": String(self.currentRun)])
            self.finish(nav)
        }
    }

    /// Cardinality demo: hammers `/api/inventory/lookup/{item}/{session}` with a
    /// fresh random session path segment on every request, flooding the bitdrift
    /// dashboard with unbounded-cardinality URLs. Runs until cancelled.
    func cardinalitySimulate(nav: Navigator) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = -1
            self.currentRun = 0

            ScreenLogger.logInfo("cardinality_simulation_start")

            while !self.isCancelled {
                self.currentRun += 1
                _ = try? await ApiClient.inventoryLookup(Self.searchQueries.randomElement()!)
                await self.sleep(self.stepDelay)
            }

            ScreenLogger.logInfo("cardinality_simulation_end", ["total_runs": String(self.currentRun)])
            self.finish(nav)
        }
    }

    private func finish(_ nav: Navigator) {
        nav.popToWelcome()
        isSimulating = false
        currentRun = 0
        totalRuns = 0
        isCancelled = false
        runTask = nil
    }

    // MARK: - Helpers

    private func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func nav(_ navigator: Navigator, _ screen: Screen) async {
        navigator.navigate(to: screen)
        await sleep(stepDelay)
    }

    private static let searchQueries = [
        "headphones", "jacket", "running shoes", "laptop", "watch",
        "camera", "speaker", "backpack", "tablet", "sneakers",
    ]

    private static let fallbackProductID = "prod_a1b2c3"

    private func ids(from json: JSON?, key: String) -> [String] {
        let ids = (json?[key].array ?? []).map { $0.str("id", Self.fallbackProductID) }
        return ids.isEmpty ? [Self.fallbackProductID] : ids
    }

    private func fetchBrowseIDs() async -> [String] {
        ids(from: try? await ApiClient.getBrowse(), key: "products")
    }

    private func fetchSearchIDs() async -> [String] {
        ids(from: try? await ApiClient.search(Self.searchQueries.randomElement()!), key: "products")
    }

    private func fetchFeaturedIDs() async -> [String] {
        ids(from: try? await ApiClient.getFeatured(), key: "featured_products")
    }

    private func fetchCategoryNames() async -> [String] {
        let names = ((try? await ApiClient.getCategories())?["categories"].array ?? [])
            .map { $0.str("name", "Electronics") }
        return names.isEmpty ? ["Electronics"] : names
    }

    private func fetchCategoryProductIDs(_ category: String) async -> [String] {
        ids(from: try? await ApiClient.getCategoryProducts(category), key: "products")
    }

    // MARK: - Fault injection

    /// Simulates the user force-quitting (swipe-up from the app switcher) on the
    /// ProductDetail screen. The Sankey shows ProductDetail → (dropout) since no
    /// subsequent screens are reached.
    ///
    /// iOS has no equivalent of Android's AlarmManager, so the app cannot
    /// schedule its own relaunch — `scripts/watchdog.sh` notices the dead process
    /// and relaunches it, which is what the persisted resume flags below are for.
    private func maybeInjectForceQuit() -> Bool {
        guard forceQuitEnabled else { return false }

        eligibleForceQuitJourneysSinceInject += 1
        let randomHit = Double.random(in: 0..<1) < Self.forceQuitProbability
        let forcedHit = isInfiniteMode && eligibleForceQuitJourneysSinceInject >= Self.forceQuitForceAfterJourneys
        guard randomHit || forcedHit else { return false }
        eligibleForceQuitJourneysSinceInject = 0

        Prefs.forceQuit.set(Prefs.keyRestartPending, true)
        Prefs.forceQuit.set(Prefs.keyResumeInfinite, isInfiniteMode)
        Prefs.forceQuit.set(Prefs.keyRestartVariant, activeVariant.rawValue)
        Prefs.forceQuit.flush()

        ScreenLogger.logError("force_quit_injected", [
            "force_quit_enabled": "true",
            "force_quit_screen": Self.forceQuitTargetScreen,
            "variant": activeVariant.label,
            "trigger_mode": forcedHit ? "forced_infinite" : "random",
        ])

        isCancelled = true

        // A user-initiated app-switcher kill is a clean termination, not a crash.
        // Give the SDK a moment to flush, then exit — the watchdog relaunches.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crashFlush) {
            exit(0)
        }
        return true
    }

    /// Simulates a main-thread hang on the CheckoutGuest screen — as if a
    /// synchronous post-checkout validation call blocked the main thread. Called
    /// after navigation and the API call complete so the screen is rendered and
    /// visible. The Sankey shows CheckoutGuest → (dropout) since Payment is never
    /// reached.
    ///
    /// This is the iOS analogue of Android's ANR. iOS has no ANR dialog; a hung
    /// main thread is picked up by MetricKit's hang diagnostics, which the SDK
    /// consumes. Event and field names deliberately keep Android's `anr_*`
    /// spelling so `bd-shop-05-anr-force-quit.json` matches both platforms.
    ///
    /// Unlike Android — where the freeze is unbounded and the watchdog dismisses
    /// the ANR dialog — the block here is bounded and followed by an exit, since
    /// nothing on the host side can detect or clear a hung iOS app. That leaves a
    /// permanently frozen Simulator as the only alternative.
    private func maybeInjectGuestHang(isGuest: Bool) -> Bool {
        guard appHangEnabled, activeVariant == .variantA, isGuest else { return false }

        eligibleHangGuestJourneysSinceInject += 1
        let randomHit = Double.random(in: 0..<1) < Self.hangProbability
        let forcedHit = isInfiniteMode && eligibleHangGuestJourneysSinceInject >= Self.hangForceAfterEligibleGuestJourneys
        guard randomHit || forcedHit else { return false }
        eligibleHangGuestJourneysSinceInject = 0

        Prefs.appHang.set(Prefs.keyRestartPending, true)
        Prefs.appHang.set(Prefs.keyResumeInfinite, isInfiniteMode)
        Prefs.appHang.set(Prefs.keyRestartVariant, activeVariant.rawValue)
        Prefs.appHang.flush()

        ScreenLogger.logError("guest_anr_injected", [
            "anr_a_enabled": "true",
            "journey_type": "guest",
            "anr_screen_name": Self.hangTargetScreenName,
            "variant": activeVariant.label,
            "trigger_mode": forcedHit ? "forced_infinite" : "random",
        ])

        isCancelled = true

        // Block the main thread so the OS records a real hang. This call is
        // already on the main actor, so sleeping here freezes the UI exactly as a
        // synchronous guest-session validation call would.
        Thread.sleep(forTimeInterval: Self.hangBlockDuration)
        exit(0)
    }

    // MARK: - Crash cycling

    /// OOM crash kinds need the longer restart delay — see
    /// `oomCrashRestartDelay` for why.
    private func restartDelay(for crashKind: String) -> TimeInterval {
        crashKind.hasPrefix("oom_") ? Self.oomCrashRestartDelay : Self.crashRestartDelay
    }

    /// Picks the next (crash type, foreground/background) combo in a
    /// deterministic sweep and advances the persisted index. `comboIdx` cycles
    /// `0..<(crashes.count * 2)`, so every crash type occurs in both foreground
    /// and background exactly once per full sweep, rather than relying on
    /// independent coin flips to eventually cover every combination.
    private func pickNextCrashCombo() -> (name: String, fire: () -> Void, fireInBackground: Bool) {
        let combo = Crashes.combo(
            atIndex: Prefs.crashLoop.int(Prefs.keyNextComboIndex),
            oomOnly: Prefs.crashLoop.bool(Prefs.keyOomOnly)
        )
        // Flush — the process dies moments later.
        let next = (Prefs.crashLoop.int(Prefs.keyNextComboIndex) + 1) % combo.totalCombos
        Prefs.crashLoop.set(Prefs.keyNextComboIndex, next)
        Prefs.crashLoop.flush()
        return (combo.name, combo.fire, combo.fireInBackground)
    }

    /// Fires `fire()`, either immediately after the `crashFlush` SDK-flush window
    /// or, for the background half of the sweep, once the app has genuinely moved
    /// to the background.
    ///
    /// Android can call `Activity.moveTaskToBack()`; iOS has no public equivalent,
    /// and the private `suspend` selector is both off-limits and useless here — a
    /// *suspended* app's main queue is frozen, so a crash scheduled on it never
    /// runs. So the background half is arranged rather than forced: the crash is
    /// armed, and when the app actually backgrounds (the user pressing Home, or
    /// `scripts/watchdog.sh` doing it) a background-task assertion keeps the
    /// process executing just long enough for the crash to land while
    /// `app_metrics.running_state` reads background. That split is what
    /// `bd-shop-06` / `bd-shop-07` chart.
    private func dispatchCrash(_ fire: @escaping () -> Void, fireInBackground: Bool) {
        guard fireInBackground else {
            // Foreground path: fire from a plain main-queue block with a blocking
            // flush window so the SDK persists the crash report and preceding logs
            // before the process dies.
            DispatchQueue.main.async {
                Thread.sleep(forTimeInterval: Self.crashFlush)
                fire()
            }
            return
        }
        armBackgroundCrash(fire)
    }

    private func armBackgroundCrash(_ fire: @escaping () -> Void) {
        pendingBackgroundCrash = fire
        awaitingBackground = true

        // Read by scripts/watchdog.sh, which backgrounds the app so an unattended
        // crash loop can get through the background half of the sweep on its own.
        Prefs.crashLoop.set(Prefs.keyAwaitingBackground, true)
        Prefs.crashLoop.flush()
        DemoStateFile.publish(awaitingBackground: true)

        ScreenLogger.logInfo("background_crash_armed", [
            "hint": "waiting for the app to background",
        ])

        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.firePendingBackgroundCrash() }
        }
    }

    private func firePendingBackgroundCrash() {
        guard let fire = pendingBackgroundCrash else { return }
        pendingBackgroundCrash = nil
        Prefs.crashLoop.set(Prefs.keyAwaitingBackground, false)
        Prefs.crashLoop.flush()
        DemoStateFile.publish(awaitingBackground: false)

        // Without this assertion the app is suspended the moment it backgrounds
        // and the scheduled block never runs. Holding a background task keeps the
        // process alive (~30s of wall clock, far more than `backgroundSettle`)
        // long enough for the crash to fire from the background state.
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "bitdrift-shop-background-crash") {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.backgroundSettle) {
            fire()
        }
    }

    /// Fires the next crash if `point` is this journey's chosen crash point.
    ///
    /// `.confirmation` doubles as the fallback: a journey that picked, say,
    /// `.paymentFailed` but whose payment succeeded would otherwise complete
    /// without crashing, and the deterministic sweep would stall.
    @discardableResult
    private func maybeFireCrash(at point: JourneyCrashPoint) -> Bool {
        guard crashLoopEnabled, !crashFiredThisJourney else { return false }
        guard point == journeyCrashPoint || point == .confirmation else { return false }
        crashFiredThisJourney = true
        Logger.addField(withKey: "crash_journey_point", value: point.rawValue)
        fireCrashNow()
        return true
    }

    /// Picks the next crash combo, logs it, then dispatches it.
    private func fireCrashNow() {
        guard crashLoopEnabled else { return }
        let combo = pickNextCrashCombo()
        let crashContext = combo.fireInBackground ? "background" : "foreground"
        Logger.addField(withKey: "crash_kind", value: combo.name)
        Logger.addField(withKey: "crash_context", value: crashContext)
        ScreenLogger.logWarning("about_to_crash: \(combo.name) (context=\(crashContext))")
        // Persist the resume intent before the crash — on iOS the relaunch comes
        // from the host watchdog, which reads these flags back on next start.
        persistCrashResumeIntent(restartDelay: restartDelay(for: combo.name))
        // Stop the simulator loop so it does not start another journey (and a
        // fresh session) racing the crash — the crash must land in the session
        // holding the about_to_crash breadcrumb.
        isCancelled = true
        dispatchCrash(combo.fire, fireInBackground: combo.fireInBackground)
    }

    /// Draws the next crash for the simplified journey — same persisted index
    /// and rotation as `pickNextCrashCombo()`, but excludes every hang-shaped
    /// combo (`Crashes.combo(excludeHangs:)`: `watchdog_*` and
    /// `lock_contention`). Foreground only: this mode has no external actor
    /// backgrounding the app, and the point is a clean, known crash, not
    /// exercising the background-crash path.
    private func pickNextCrashOnlyCombo() -> (name: String, fire: () -> Void) {
        let combo = Crashes.combo(
            atIndex: Prefs.crashLoop.int(Prefs.keyNextComboIndex),
            oomOnly: Prefs.crashLoop.bool(Prefs.keyOomOnly),
            excludeHangs: true
        )
        let next = (Prefs.crashLoop.int(Prefs.keyNextComboIndex) + 1) % combo.totalCombos
        Prefs.crashLoop.set(Prefs.keyNextComboIndex, next)
        Prefs.crashLoop.flush()
        return (combo.name, combo.fire)
    }

    /// The simplified journey's step-5 crash, on CheckoutGuest. Mirrors
    /// `fireCrashNow()`'s dispatch mechanics exactly, but draws from
    /// `pickNextCrashOnlyCombo()` so
    /// a hang can never fire here in either of the catalog's two hang-shaped
    /// forms — `watchdog_scene_create`/`_scene_update`/`_process_exit`, which
    /// arm an OS-detected hang, and `lock_contention`, which deliberately
    /// blocks the main thread before converting itself to a crash. Without
    /// this exclusion the sweep can land on either and the app appears to
    /// "start and hang" rather than crash at the known step this mode exists
    /// to guarantee.
    private func fireSimplifiedCrashNow() {
        guard crashLoopEnabled else { return }
        let combo = pickNextCrashOnlyCombo()
        Logger.addField(withKey: "crash_kind", value: combo.name)
        Logger.addField(withKey: "crash_context", value: "foreground")
        ScreenLogger.logWarning("about_to_crash: \(combo.name) (context=foreground)")
        persistCrashResumeIntent(restartDelay: restartDelay(for: combo.name))
        isCancelled = true
        dispatchCrash(combo.fire, fireInBackground: false)
    }

    /// Fast crash-loop entry point: skips the shopping journey entirely. Picks
    /// the next combo and fires immediately, relying on the host watchdog to
    /// relaunch — the startup config screen is wired to be skipped while fast
    /// mode is active, and the Welcome screen re-invokes this on every relaunch.
    /// Self-sustaining across process restarts; no Sim button or journey involved.
    func fireFastCrash() {
        guard crashLoopEnabled, fastCrashModeEnabled else { return }
        let combo = pickNextCrashCombo()
        let crashContext = combo.fireInBackground ? "background" : "foreground"
        fastCrashStatus = FastCrashStatus(
            kind: combo.name,
            context: crashContext,
            oomOnly: Prefs.crashLoop.bool(Prefs.keyOomOnly)
        )
        Logger.startNewSession()
        Logger.addField(withKey: "crash_kind", value: combo.name)
        Logger.addField(withKey: "crash_context", value: crashContext)
        ScreenLogger.logWarning("about_to_crash (fast): \(combo.name) (context=\(crashContext))")
        persistCrashResumeIntent(restartDelay: restartDelay(for: combo.name))
        dispatchCrash(combo.fire, fireInBackground: combo.fireInBackground)
    }

    /// Records how long the watchdog should wait before relaunching. OOM crashes
    /// materialise on their own schedule, so relaunching too early leaves the
    /// still-running leaked thread from the previous attempt accumulating
    /// alongside whatever the relaunch fires next.
    private func persistCrashResumeIntent(restartDelay: TimeInterval) {
        Prefs.crashLoop.set("restart_delay_ms", Int(restartDelay * 1000))
        Prefs.crashLoop.set(Prefs.keyRestartVariant, activeVariant.rawValue)
        Prefs.crashLoop.flush()
        DemoStateFile.publish()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Fully random journey simulator — each journey walks through every major
    // step of the shopping funnel, randomly choosing a branch at each decision
    // point.
    //
    //  Welcome
    //    → discovery: Browse | Search | Categories→CategoryBrowse (random)
    //    → maybe Featured (coin flip)
    //    → ProductDetail
    //    → maybe Reviews (coin flip)
    //    → maybe Wishlist (coin flip)
    //    → Cart
    //    → checkout: CheckoutGuest | CheckoutSignIn (random)
    //    → payment: Card | Apple Pay | PayPal | Android Pay (random)
    //    → Confirmation
    // ═══════════════════════════════════════════════════════════════════════

    private func runSingleJourney(_ navigator: Navigator) async {
        // Keep force-quit runs in the startup session so workflows that begin
        // with SDK configuration and end with app termination match in a single
        // session.
        if !forceQuitEnabled {
            Logger.startNewSession()
            ScreenLogger.logInfo("journey_started", [
                "run": String(currentRun),
                "variant": activeVariant.label,
            ])
            // Give the SDK time to fully initialise the new session before
            // recording exposures.
            await sleep(0.2)
            // Re-apply flag exposures after startNewSession() — exposure is
            // per-session, so it must be recorded again on the new session for
            // the dashboard to detect it.
            setVariant(activeVariant)
            await sleep(0.2)
        }

        // Pick where in the back half of this journey a crash may fire, so crash
        // data spreads across the funnel instead of piling up on Confirmation.
        journeyCrashPoint = JourneyCrashPoint.allCases.randomElement() ?? .confirmation
        crashFiredThisJourney = false

        // Rotate through the fixed entity list so each journey appears as a
        // different user in the bitdrift Entities view. `currentRun` is 1-indexed.
        let entity = Self.demoEntities[(max(currentRun, 1) - 1) % Self.demoEntities.count]
        // bitdrift SDK: setEntityID() associates all subsequent logs with this
        // user identity.
        // POC: ad-hoc debugging — search any entity in the dashboard to retrieve
        // all their sessions on demand.
        Logger.setEntityID(entity)

        if AppConfig.simplifiedJourneyEnabled {
            await runSimplifiedJourney(navigator, entity: entity)
            return
        }

        // bitdrift SDK: startSpan() opens a root span for the journey. All logs
        // are correlated via _span_id; child spans form a two-level hierarchy in
        // the timeline.
        // POC: spans waterfall visualization in Timeline; query _duration_ms for
        // p50/p95 of any flow.
        let journeySpan = Logger.startSpan(
            name: "journey",
            level: .info,
            fields: ScreenLogger.encode(["variant": activeVariant.label, "entity": entity])
        )
        // Tracks the discovery phase: Welcome → Browse/Search/Categories →
        // ProductDetail → Cart. Ends SUCCESS when the first item hits the cart.
        let discoverySpan = Logger.startSpan(
            name: "product_discovery",
            level: .info,
            fields: ScreenLogger.encode(["variant": activeVariant.label]),
            parentSpanID: journeySpan?.id
        )

        // ── Step 1: Welcome ──────────────────────────────────────────────
        navigator.popToWelcome()
        _ = try? await ApiClient.getWelcome()
        await sleep(stepDelay)

        // ── Step 2: Discovery — Browse, Search, or Categories ────────────
        // Variant-biased but still random:
        //   A (digital native) — 45% Search, 40% Browse, 15% Categories
        //   B (deliberate)     — 50% Categories, 25% Browse, 25% Search
        //   Control            — equal 33 / 33 / 33
        var productIDs: [String] = []
        var source = ""
        let discoveryRoll = Double.random(in: 0..<1)
        let discoveryChoice: Int
        switch activeVariant {
        case .variantA: discoveryChoice = discoveryRoll < 0.40 ? 0 : (discoveryRoll < 0.85 ? 1 : 2)
        case .variantB: discoveryChoice = discoveryRoll < 0.25 ? 0 : (discoveryRoll < 0.50 ? 1 : 2)
        case .control:  discoveryChoice = Int.random(in: 0...2)
        }

        // bitdrift SDK: trackSpan() isolates the discovery-method fetch (whichever
        // of browse/search/categories was picked this run) as its own sub-phase of
        // product_discovery, distinct from the ProductDetail/Reviews/Wishlist steps
        // that follow.
        // POC: event tracking — sub-phase waterfall within an existing span, not
        // just a single lump duration. Demo-only caveat: the branch taken is a
        // randomized per-variant roll, so this reflects whichever backend endpoint
        // got hit that run, not a stable operation.
        await CaptureBridge.trackSpan("discovery_fetch", parentSpanID: discoverySpan?.id) { _ in
            switch discoveryChoice {
            case 0:
                await nav(navigator, .browse)
                productIDs = await fetchBrowseIDs()
                source = "browse"
            case 1:
                await nav(navigator, .search)
                productIDs = await fetchSearchIDs()
                source = "search"
            default:
                await nav(navigator, .categories)
                let category = (await fetchCategoryNames()).randomElement()!
                await nav(navigator, .categoryBrowse(category: category))
                productIDs = await fetchCategoryProductIDs(category)
                source = "categories"
            }
        }

        // ── Maybe visit Featured — A skips it (15%), B almost always (75%)
        let featuredProb: Double
        switch activeVariant {
        case .control:  featuredProb = 0.5
        case .variantA: featuredProb = 0.15  // decisive, goes straight to product
        case .variantB: featuredProb = 0.75  // comparison shopper, checks everything
        }
        if Double.random(in: 0..<1) < featuredProb {
            await nav(navigator, .featured)
            productIDs = await fetchFeaturedIDs()
            source = "featured"
        }

        let pid = productIDs.randomElement()!

        // ── Step 3: ProductDetail ────────────────────────────────────────
        // bitdrift SDK: trackSpan() wraps ProductDetail + the maybe-Reviews visit
        // as one product_discovery sub-phase. `maybeInjectForceQuit()` below aborts
        // the *whole journey*, not just this span — a bare `return` inside the
        // closure would only exit the closure, so the abort is signalled back out
        // via the return value instead, and the actual early return happens after
        // the span has already closed normally.
        // POC: event tracking — sub-phase waterfall within product_discovery.
        let forceQuitInjected = await CaptureBridge.trackSpan(
            "product_view", parentSpanID: discoverySpan?.id
        ) { _ -> Bool in
            await nav(navigator, .productDetail(source: source, productID: pid))
            _ = try? await ApiClient.getProduct(pid)

            // Force-quit injection: fires after ProductDetail renders and the API
            // completes. Simulates the user swiping the app away on an uninteresting
            // product page.
            if maybeInjectForceQuit() { return true }

            // ── Maybe visit Reviews — A rarely (10%), B almost always (90%)
            let reviewsProb: Double
            switch activeVariant {
            case .control:  reviewsProb = 0.5
            case .variantA: reviewsProb = 0.10  // trusts the product, skips reviews
            case .variantB: reviewsProb = 0.90  // reads every review before deciding
            }
            if Double.random(in: 0..<1) < reviewsProb {
                await nav(navigator, .reviews(source: source, productID: pid))
                _ = try? await ApiClient.getReviews(pid)
            }
            return false
        }
        if forceQuitInjected { return }

        // ── Maybe visit Wishlist — A almost never (5%), B very often (75%)
        let wishlistProb: Double
        switch activeVariant {
        case .control:  wishlistProb = 0.4
        case .variantA: wishlistProb = 0.05  // immediate buyer, doesn't save for later
        case .variantB: wishlistProb = 0.75  // saves many items before committing
        }
        if Double.random(in: 0..<1) < wishlistProb {
            // bitdrift SDK: trackSpan() wraps the wishlist visit — only opens when
            // the roll actually adds to wishlist, so it doesn't inflate the
            // discovery-phase span count on runs that skip it.
            // POC: event tracking — sub-phase waterfall within product_discovery.
            await CaptureBridge.trackSpan("wishlist_add", parentSpanID: discoverySpan?.id) { _ in
                await nav(navigator, .wishlist(productID: pid))
                _ = try? await ApiClient.addToWishlist(pid)
            }
        }

        // ── Step 4: Cart — A adds just 1, B loads up with 3-5 ────────────
        var cartItems = [pid]
        await nav(navigator, .cart(productID: pid))
        _ = try? await ApiClient.addToCart(pid)
        // Discovery phase complete — first item is in the cart.
        discoverySpan?.end(.success, fields: ScreenLogger.encode(["source": source, "product_id": pid]))

        // bitdrift SDK: trackSpan() wraps the whole cart-assembly block — extra
        // items, view, maybe-remove, maybe-empty-and-rebuild, maybe-flip, final
        // view — as one sibling span alongside product_discovery and checkout,
        // parented directly off the journey span. Previously this ran inside no
        // span at all.
        // POC: event tracking — multi-step cart operations as one measurable
        // sub-phase. Demo-only caveat: branch counts/probabilities are
        // variant-driven random walks, and the fixed `sleep(stepDelay)` calls
        // interspersed below are artificial demo pacing, not real work — they
        // inflate this span's duration by a constant that has nothing to do with
        // the underlying API calls.
        await CaptureBridge.trackSpan("cart_assembly", parentSpanID: journeySpan?.id) { _ in
            let extraCount: Int
            switch activeVariant {
            case .control:  extraCount = Int.random(in: 1...3)  // 1-3 extra
            case .variantA: extraCount = Int.random(in: 0...1)  // usually 1 item, occasionally a second
            case .variantB: extraCount = Int.random(in: 2...4)  // loads up the cart
            }
            for _ in 0..<extraCount {
                let extraPid = productIDs.randomElement()!
                cartItems.append(extraPid)
                _ = try? await ApiClient.addToCart(extraPid, quantity: Int.random(in: 1...3))
                await sleep(stepDelay)
            }

            // View the cart
            _ = try? await ApiClient.getCart()
            await sleep(stepDelay)

            // Maybe remove an item — A almost never (10%), B almost always (90%)
            let removeProb: Double
            switch activeVariant {
            case .control:  removeProb = 0.6
            case .variantA: removeProb = 0.10  // keeps what they add
            case .variantB: removeProb = 0.90  // constant second-guessing
            }
            if Double.random(in: 0..<1) < removeProb, cartItems.count > 1 {
                let removePid = cartItems.remove(at: Int.random(in: 0..<cartItems.count))
                _ = try? await ApiClient.deleteCartItem(removePid)
                await sleep(stepDelay)
            }

            // Maybe empty cart and re-add — A almost never (5%), B very often (60%)
            let emptyCartProb: Double
            switch activeVariant {
            case .control:  emptyCartProb = 0.2
            case .variantA: emptyCartProb = 0.05  // commits to their choice
            case .variantB: emptyCartProb = 0.60  // starts over frequently
            }
            if Double.random(in: 0..<1) < emptyCartProb {
                for item in cartItems {
                    _ = try? await ApiClient.deleteCartItem(item)
                    await sleep(stepDelay)
                }
                cartItems.removeAll()
                // Re-add one product so checkout works
                let rePid = productIDs.randomElement()!
                cartItems.append(rePid)
                _ = try? await ApiClient.addToCart(rePid)
                await sleep(stepDelay)
            }

            // Maybe remove and re-add same item — A almost never (5%), B often (70%)
            let flipProb: Double
            switch activeVariant {
            case .control:  flipProb = 0.3
            case .variantA: flipProb = 0.05  // no quantity dithering
            case .variantB: flipProb = 0.70  // changes quantity repeatedly
            }
            if Double.random(in: 0..<1) < flipProb, let flippedPid = cartItems.randomElement() {
                _ = try? await ApiClient.deleteCartItem(flippedPid)
                await sleep(stepDelay)
                _ = try? await ApiClient.addToCart(flippedPid, quantity: Int.random(in: 1...5))
                await sleep(stepDelay)
            }

            // View cart one more time before checkout
            _ = try? await ApiClient.getCart()
            await sleep(stepDelay)
        }

        if maybeFireCrash(at: .cart) { return }

        // ── Cart abandonment — A: 15%, Control: 5%, B: 0% ────────────────
        let cartAbandonProb: Double
        switch activeVariant {
        case .control:  cartAbandonProb = 0.05
        case .variantA: cartAbandonProb = 0.15
        case .variantB: cartAbandonProb = 0.0
        }
        if Double.random(in: 0..<1) < cartAbandonProb {
            ScreenLogger.logInfo("cart_abandoned", [
                "items_in_cart": String(cartItems.count),
                "variant": activeVariant.label,
            ])
            await sleep(0.2)
            journeySpan?.end(.canceled, fields: ScreenLogger.encode(["reason": "cart_abandoned"]))
            return
        }

        let checkoutPid = cartItems.last ?? pid

        // ── Step 5: Checkout — A almost always guest, B almost always signin
        let guestProb: Double
        switch activeVariant {
        case .control:  guestProb = 0.5   // 50/50 baseline
        case .variantA: guestProb = 0.95  // never bothers with an account
        case .variantB: guestProb = 0.05  // always signs in for loyalty points
        }
        // Keep hang injection deterministic across environments: when it is
        // enabled and Variant A is selected, always take the guest branch.
        let isGuest = (appHangEnabled && activeVariant == .variantA)
            ? true
            : Double.random(in: 0..<1) < guestProb

        // Checkout span: child of the journey span, covers Checkout → Payment →
        // Confirmation. `parentSpanID` links it to the root journey span so both
        // appear together in the timeline.
        let checkoutSpan = Logger.startSpan(
            name: "checkout",
            level: .info,
            fields: ScreenLogger.encode(["checkout_type": isGuest ? "guest" : "signin"]),
            parentSpanID: journeySpan?.id
        )

        let session: String
        if isGuest {
            await nav(navigator, .checkoutGuest(productID: checkoutPid))
            session = (try? await ApiClient.checkoutGuest())?.str("checkout_session") ?? ""
            // Hang injection: fires after the checkout API call completes, which
            // gives SwiftUI time to render the screen. The Sankey shows
            // CheckoutGuest → (dropout) since Payment is never reached.
            if maybeInjectGuestHang(isGuest: isGuest) { return }
        } else {
            await nav(navigator, .checkoutSignIn(productID: checkoutPid))
            session = (try? await ApiClient.checkoutSignIn())?.str("checkout_session") ?? ""
        }

        if maybeFireCrash(at: .checkout) { return }

        // ── Checkout dropout — A: 35%, B: 5%, Control: 0% ────────────────
        let checkoutDropoutProb: Double
        switch activeVariant {
        case .control:  checkoutDropoutProb = 0.0
        case .variantA: checkoutDropoutProb = 0.35
        case .variantB: checkoutDropoutProb = 0.05
        }
        if Double.random(in: 0..<1) < checkoutDropoutProb {
            ScreenLogger.logInfo("checkout_abandoned", [
                "checkout_type": isGuest ? "guest" : "signin",
                "variant": activeVariant.label,
            ])
            await sleep(0.2)
            checkoutSpan?.end(.canceled, fields: ScreenLogger.encode(["reason": "checkout_abandoned"]))
            journeySpan?.end(.canceled, fields: ScreenLogger.encode(["reason": "checkout_abandoned"]))
            return
        }

        // ── Step 6: Payment ─────────────────────────────────────────────
        // 0=card, 1=apple_pay, 2=paypal, 3=android_pay
        let paymentChoice: Int
        switch activeVariant {
        case .control:
            paymentChoice = Int.random(in: 0...3)          // equal 25/25/25/25
        case .variantA:                                     // 5% card, 40% Apple Pay, 35% PayPal, 20% Android Pay
            let r = Double.random(in: 0..<1)
            paymentChoice = r < 0.05 ? 0 : (r < 0.45 ? 1 : (r < 0.80 ? 2 : 3))
        case .variantB:                                     // 95% card, 3% Apple Pay, 2% PayPal
            let r = Double.random(in: 0..<1)
            paymentChoice = r < 0.95 ? 0 : (r < 0.98 ? 1 : 2)
        }
        let paymentMethod = Self.paymentMethodName(paymentChoice)

        // ── Payment failure simulation ──────────────────────────────────
        // Android Pay carries its own elevated failure rates; other methods use
        // variant-level rates.
        let failureProb: Double
        if paymentMethod == "android_pay" {
            switch activeVariant {
            case .control:  failureProb = 0.30
            case .variantA: failureProb = 0.20
            case .variantB: failureProb = 0.0  // never reaches here — signin doesn't use Android Pay
            }
        } else {
            switch activeVariant {
            case .control:  failureProb = 0.15
            case .variantA: failureProb = 0.35
            case .variantB: failureProb = 0.05
            }
        }
        let willPaymentFail = Double.random(in: 0..<1) < failureProb

        let orderID = await runPayment(
            navigator, choice: paymentChoice, session: session, parentSpanID: checkoutSpan?.id
        )

        if maybeFireCrash(at: .payment) { return }

        if willPaymentFail {
            ScreenLogger.logError("payment_failed", [
                "payment_method": paymentMethod,
                "checkout_session": session,
                "variant": activeVariant.label,
            ])

            // Navigate to the PaymentFailed screen so it appears in the Sankey.
            await nav(navigator, .paymentFailed(paymentMethod: paymentMethod, checkoutSession: session))
            await sleep(0.2)

            if maybeFireCrash(at: .paymentFailed) { return }

            // ── Payment retry: 50% chance to retry with a different method
            if Double.random(in: 0..<1) < 0.50 {
                let retryChoice = [0, 1, 2, 3].filter { $0 != paymentChoice }.randomElement()!
                let retryMethod = Self.paymentMethodName(retryChoice)
                let retryOrderID = await runPayment(
                    navigator, choice: retryChoice, session: session,
                    parentSpanID: checkoutSpan?.id, retried: true
                )

                ScreenLogger.logInfo("payment_retry", [
                    "original_method": paymentMethod,
                    "retry_method": retryMethod,
                    "variant": activeVariant.label,
                ])

                // Retry succeeds — proceed to confirmation with the retried order.
                setVariant(activeVariant)
                await sleep(0.1)
                await nav(navigator, .confirmation(orderID: retryOrderID))
                ScreenLogger.logInfo("confirmation_reached", [
                    "_screen_name": "Confirmation",
                    "payment_retried": "true",
                    "retry_method": retryMethod,
                ])
                // bitdrift SDK: trackSpan() isolates the confirmation fetch as its
                // own checkout sub-phase, closing the checkout -> payment ->
                // confirmation waterfall (checkout_screen_load/payment_screen_load
                // in Screens.swift cover the first two on the screen side).
                // POC: event tracking — sub-phase waterfall within checkout.
                await CaptureBridge.trackSpan(
                    "checkout.confirmation", parentSpanID: checkoutSpan?.id
                ) { _ in
                    _ = try? await ApiClient.getConfirmation(retryOrderID)
                }
                await sleep(0.2)
                checkoutSpan?.end(.success, fields: ScreenLogger.encode([
                    "payment_method": retryMethod, "retried": "true",
                ]))
                journeySpan?.end(.success)
                maybeFireCrash(at: .confirmation)
            }
            return
        }

        // ── Step 7: Confirmation ────────────────────────────────────────
        // Re-assert flag exposure right before Confirmation to guarantee it is
        // on this session.
        setVariant(activeVariant)
        await sleep(0.1)
        await nav(navigator, .confirmation(orderID: orderID))
        // Explicit tagged log so fields are verifiable in the raw stream.
        let checkoutFlow: String
        switch activeVariant {
        case .control:  checkoutFlow = "random"
        case .variantA: checkoutFlow = "guest"
        case .variantB: checkoutFlow = "signin"
        }
        ScreenLogger.logInfo("confirmation_reached", [
            "_screen_name": "Confirmation",
            "checkout_flow": checkoutFlow,
        ])
        // bitdrift SDK: trackSpan() isolates the confirmation fetch as its own
        // checkout sub-phase — see the retry path above for the same pattern.
        // POC: event tracking — sub-phase waterfall within checkout.
        await CaptureBridge.trackSpan("checkout.confirmation", parentSpanID: checkoutSpan?.id) { _ in
            _ = try? await ApiClient.getConfirmation(orderID)
        }
        await sleep(0.2)
        checkoutSpan?.end(.success, fields: ScreenLogger.encode(["payment_method": paymentMethod]))
        journeySpan?.end(.success)
        maybeFireCrash(at: .confirmation)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Simplified journey — `AppConfig.simplifiedJourneyEnabled`. A fixed,
    // non-random 7-step path, built for a concrete before/after test of
    // whether a workflow's flow actually closes on a crash:
    //
    //   1. Welcome
    //   2. Browse
    //   3. ProductDetail
    //   4. Cart
    //   5. CheckoutGuest  ← crash fires HERE, unconditionally, when the crash
    //                        loop is on. No random crash-point selection.
    //   6. PaymentCard
    //   7. Confirmation
    //
    // With the crash loop OFF, every journey reaches step 7 — the "before":
    // proof the path itself is sound and fully populates a Sankey/funnel.
    // With it ON, every journey stops at exactly step 5 — the "after": proof
    // of precisely where the flow died, with no ambiguity about which step.
    //
    // Two things fix the shape of this path:
    //
    // The steps map 1:1 onto `bd-shop-17`'s funnel stages (Welcome, Discovery,
    // ProductDetail, Cart, Checkout, Payment, Confirmation), so the funnel
    // chart reads as a clean 7-bar staircase rather than something that has to
    // be mentally reconciled against a different set of screens.
    //
    // Crashing at step 5 specifically is what exercises `ScreenLogger`'s
    // 5-deep screen shift register: at crash time the trail holds steps 1-5
    // exactly, so a crash report carries `screen_current` plus four real
    // `screen_prev_N` values with no `none` padding. Crashing earlier (step 3,
    // as this originally did) left `screen_prev_3`/`_4` permanently empty and
    // never demonstrated the window at all.
    // ═══════════════════════════════════════════════════════════════════════

    private func runSimplifiedJourney(_ navigator: Navigator, entity: String) async {
        let journeySpan = Logger.startSpan(
            name: "journey",
            level: .info,
            fields: ScreenLogger.encode([
                "variant": activeVariant.label,
                "entity": entity,
                "mode": "simplified",
            ])
        )

        // ── Step 1: Welcome ──────────────────────────────────────────────
        navigator.popToWelcome()
        _ = try? await ApiClient.getWelcome()
        await sleep(stepDelay)

        // ── Step 2: Browse ───────────────────────────────────────────────
        // bitdrift SDK: trackSpan() — the same discovery_fetch span the full
        // journey uses (see runSingleJourney), parented directly on journeySpan
        // since this mode has no separate discoverySpan. Without a call site
        // here, bd-shop-22's discovery_fetch chart never populates under the
        // app's default config (SIMPLIFIED_JOURNEY_ENABLED = YES).
        // POC: event tracking — sub-phase waterfall, populated regardless of
        // which journey mode is active.
        let productIDs = await CaptureBridge.trackSpan(
            "discovery_fetch", parentSpanID: journeySpan?.id
        ) { _ in
            await nav(navigator, .browse)
            return await fetchBrowseIDs()
        }
        let pid = productIDs.randomElement() ?? Self.fallbackProductID

        // ── Step 3: ProductDetail ────────────────────────────────────────
        // bitdrift SDK: trackSpan() — same product_view span the full journey
        // uses; this mode has no Reviews step, so it only covers the
        // ProductDetail fetch. Force-quit injection aborts the whole journey,
        // not just this span — same Bool-signal pattern as runSingleJourney's
        // product_view for why a bare `return` inside the closure won't do.
        // POC: event tracking — sub-phase waterfall.
        let forceQuitInjected = await CaptureBridge.trackSpan(
            "product_view", parentSpanID: journeySpan?.id
        ) { _ -> Bool in
            await nav(navigator, .productDetail(source: "browse", productID: pid))
            _ = try? await ApiClient.getProduct(pid)

            // Force-quit injection, same placement as the full journey: after
            // ProductDetail renders and its API call completes. Kept here so the
            // persisted force-quit toggle behaves identically in both modes — and
            // so `runSingleJourney`'s force-quit session suppression is never
            // applied to a mode that can't actually inject the quit.
            return maybeInjectForceQuit()
        }
        if forceQuitInjected {
            journeySpan?.end(.canceled, fields: ScreenLogger.encode(["reason": "force_quit_injected"]))
            return
        }

        // ── Step 4: Cart ─────────────────────────────────────────────────
        // bitdrift SDK: trackSpan() — same cart_assembly span the full journey
        // uses, though this mode only does the one plain addToCart (no extra
        // items/remove/flip logic).
        // POC: event tracking — sub-phase waterfall.
        await CaptureBridge.trackSpan("cart_assembly", parentSpanID: journeySpan?.id) { _ in
            await nav(navigator, .cart(productID: pid))
            _ = try? await ApiClient.addToCart(pid)
        }

        // ── Step 5: CheckoutGuest — the crash point ──────────────────────
        await nav(navigator, .checkoutGuest(productID: pid))
        let session = (try? await ApiClient.checkoutGuest())?.str("checkout_session") ?? ""

        // Hang injection, same placement as the full journey: after the guest
        // checkout API call, before anything else can terminate the journey.
        // This mode is always a guest checkout, so `isGuest` is fixed true.
        if maybeInjectGuestHang(isGuest: true) {
            journeySpan?.end(.canceled, fields: ScreenLogger.encode(["reason": "guest_hang_injected"]))
            return
        }

        if crashLoopEnabled {
            // Distinct value from the random sweep's `crash_journey_point`
            // (cart/checkout/payment/...) so this mode's crashes are
            // unambiguously identifiable in the raw log stream and in any
            // chart grouped by that field.
            Logger.addField(withKey: "crash_journey_point", value: "simplified_step_5_checkout_guest")
            ScreenLogger.logWarning("simplified_journey_crash_point (step 5 of 7): CheckoutGuest")
            fireSimplifiedCrashNow()
            journeySpan?.end(.canceled, fields: ScreenLogger.encode(["reason": "simplified_crash_step_5"]))
            return
        }

        // ── Step 6: PaymentCard ──────────────────────────────────────────
        // Card is choice 0 — fixed, not the random payment-method roll the
        // full journey uses, so this path stays deterministic. No separate
        // checkoutSpan exists in this mode — checkout.payment/.confirmation nest
        // directly under the flat journey span instead.
        let orderID = await runPayment(
            navigator, choice: 0, session: session, parentSpanID: journeySpan?.id
        )

        // ── Step 7: Confirmation ─────────────────────────────────────────
        await nav(navigator, .confirmation(orderID: orderID))
        await CaptureBridge.trackSpan("checkout.confirmation", parentSpanID: journeySpan?.id) { _ in
            _ = try? await ApiClient.getConfirmation(orderID)
        }

        ScreenLogger.logInfo("simplified_journey_completed", [
            "steps_completed": "7",
            "variant": activeVariant.label,
        ])
        await sleep(0.2)
        journeySpan?.end(.success)
    }

    /// Navigates to the payment screen for `choice` and calls its endpoint,
    /// returning the resulting order ID (empty on failure).
    ///
    /// `parentSpanID` is the caller's checkout-equivalent span (`checkoutSpan` in
    /// the full journey, `journeySpan` in the simplified one — see call sites).
    /// `retried` distinguishes a retry attempt from the first one on the span
    /// itself — the shipped `bd-shop-22` charts (per-span and compared) still
    /// aggregate all `checkout.payment` end spans together regardless of this
    /// field; it's there for ad-hoc filtering, not built into those charts.
    ///
    /// bitdrift SDK: trackSpan() wraps the single shared call site for all four
    /// payment variants — this is the actual "payment processing" sub-phase of
    /// checkout, previously bundled into `checkout`'s own duration along with
    /// checkout-entry and confirmation.
    /// POC: event tracking — sub-phase waterfall within checkout.
    private func runPayment(
        _ navigator: Navigator, choice: Int, session: String, parentSpanID: UUID?, retried: Bool = false
    ) async -> String {
        return await CaptureBridge.trackSpan(
            "checkout.payment", fields: ["retried": String(retried)], parentSpanID: parentSpanID
        ) { _ in
            switch choice {
            case 0:
                await nav(navigator, .paymentCard(checkoutSession: session))
                return (try? await ApiClient.payCard(session))?.str("order_id") ?? ""
            case 1:
                await nav(navigator, .paymentApplePay(checkoutSession: session))
                return (try? await ApiClient.payApplePay(session))?.str("order_id") ?? ""
            case 2:
                await nav(navigator, .paymentPayPal(checkoutSession: session))
                return (try? await ApiClient.payPayPal(session))?.str("order_id") ?? ""
            default:
                await nav(navigator, .paymentAndroidPay(checkoutSession: session))
                return (try? await ApiClient.payAndroidPay(session))?.str("order_id") ?? ""
            }
        }
    }

    private static func paymentMethodName(_ choice: Int) -> String {
        switch choice {
        case 0: return "card"
        case 1: return "apple_pay"
        case 2: return "paypal"
        default: return "android_pay"
        }
    }

    // MARK: - Constants

    private static let crashRestartDelay: TimeInterval = 2

    /// Published to the state file at startup so a stale per-crash value cannot
    /// outlive the run that wrote it.
    static let defaultRestartDelayMs = Int(crashRestartDelay * 1000)
    /// OOM crashes materialise on their own schedule (a background allocation
    /// loop running until the OS kills the process) instead of failing
    /// synchronously, so a short delay would have the watchdog relaunch the
    /// still-alive app while the previous attempt's leaked thread keeps
    /// accumulating. Also stays above `Crashes.oomGradualWait` (35s), which is
    /// deliberately paced so the session lasts long enough to collect several
    /// Resource Utilization snapshots and show a rising memory graph rather than
    /// one flat point.
    private static let oomCrashRestartDelay: TimeInterval = 45
    private static let crashFlush: TimeInterval = 0.3
    /// Longer than `crashFlush`: gives the OS time to actually move the process
    /// out of the foreground after `suspend`, before the crash fires.
    private static let backgroundSettle: TimeInterval = 2

    static let demoEntities = [
        "Groucho", "Harpo", "Chico", "Gummo", "Zeppo",
        "Moe", "Larry", "Curly", "Abbott", "Costello",
    ]

    private static let hangTargetScreenName = "CheckoutGuest"
    private static let hangProbability = 0.25
    private static let hangForceAfterEligibleGuestJourneys = 6
    private static let hangBlockDuration: TimeInterval = 15

    private static let forceQuitTargetScreen = "ProductDetail"
    private static let forceQuitProbability = 0.60
    private static let forceQuitForceAfterJourneys = 3
}
