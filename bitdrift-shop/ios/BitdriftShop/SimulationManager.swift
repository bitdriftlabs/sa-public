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

    /// The spec persona id (personas.yaml), which selects the journey's probability tables.
    var id: String {
        switch self {
        case .control: return "control"
        case .variantA: return "variant_a"
        case .variantB: return "variant_b"
        }
    }

    var label: String {
        switch self {
        case .control: return "Control"
        case .variantA: return "Variant A"
        case .variantB: return "Variant B"
        }
    }
}

/// Automated simulation of user journeys through the app. The journey itself is data
/// (spec/journey.yaml), interpreted by `JourneyEngine` — identically on Android, React
/// Native and Flutter — so all platforms feed the same `bd-shop-*` workflows. This class
/// keeps only what is iOS-specific: navigation, the API client, the SDK calls, and how
/// each fault physically happens (`SimAdapter`).
///
/// Every simulation is seeded: the engine draws from mulberry32 keyed on (sim_seed, run),
/// so the same seed replays the same journeys. Autorun takes `-sim_seed`; every other
/// entry point draws a fresh random seed per simulation (logged on `journey_started`).
@MainActor
final class SimulationManager: ObservableObject {

    @Published private(set) var isSimulating = false
    @Published private(set) var currentRun = 0
    @Published private(set) var totalRuns = 0
    @Published private(set) var activeVariant: SimVariant = .control

    @Published var recommendationsV2Enabled = false
    @Published var crashLoopEnabled = false

    /// The crash loop is on, or the test harness named a crash (`-crash <name>`). Kept apart from
    /// `crashLoopEnabled` because that flag is promoted into UserDefaults at startup, and a one-off
    /// harness crash must not arm the crash loop for the launches that follow.
    private var crashArmed: Bool { crashLoopEnabled || Autorun.crash != nil }

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

    private var isCancelled = false
    private var runTask: Task<Void, Never>?

    /// Seed for the current simulation: the autorun seed, else random (0..<2^31).
    private var simSeed: Int64 = 0

    /// Navigator of the simulation in flight; the adapter navigates through it.
    private var navigator: Navigator?

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
        Logger.setFeatureFlagExposure(withName: SpecFlags.checkoutFlow, variant: checkoutFlow)
        Logger.setFeatureFlagExposure(withName: SpecFlags.paymentUi, variant: paymentUI)
        Logger.setFeatureFlagExposure(withName: SpecFlags.cartAbandonRate, variant: cartAbandon)
        // Also set as global fields so every log carries the active flag values.
        Logger.addField(withKey: SpecFields.ffCheckoutFlow, value: checkoutFlow)
        Logger.addField(withKey: SpecFields.ffPaymentUi, value: paymentUI)
        Logger.addField(withKey: SpecFields.ffCartAbandonRate, value: cartAbandon)
        Logger.addField(withKey: SpecFields.ffVariant, value: variant.label)

        Logger.setFeatureFlagExposure(withName: SpecFlags.paymentAndroidPay, variant: androidPay)
        Logger.addField(withKey: SpecFields.ffPaymentAndroidPay, value: androidPay)

        let orderSummary = crashLoopEnabled ? "v2" : "v1"
        Logger.setFeatureFlagExposure(withName: SpecFlags.orderSummary, variant: orderSummary)
        Logger.addField(withKey: SpecFields.ffOrderSummary, value: orderSummary)

        let hangState = appHangEnabled ? "enabled" : "disabled"
        Logger.setFeatureFlagExposure(withName: SpecFlags.anrA, variant: hangState)
        Logger.addField(withKey: SpecFields.ffAnrA, value: hangState)

        let forceQuitState = forceQuitEnabled ? "enabled" : "disabled"
        Logger.setFeatureFlagExposure(withName: SpecFlags.forceQuit, variant: forceQuitState)
        Logger.addField(withKey: SpecFields.ffForceQuit, value: forceQuitState)

        let recommendationsV2State = recommendationsV2Enabled ? "enabled" : "disabled"
        Logger.setFeatureFlagExposure(withName: SpecFlags.recommendationsV2, variant: recommendationsV2State)
        Logger.addField(withKey: SpecFields.ffRecommendationsV2, value: recommendationsV2State)

        // Explicit log so flag exposure is verifiable in the raw log stream.
        ScreenLogger.logInfo(SpecEvents.featureFlagExposureSet)

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
        ScreenLogger.logInfo(SpecEvents.simulationCancelled, [
            SpecFields.completedRuns: String(currentRun),
            SpecFields.totalRuns: String(totalRuns),
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
    func simulate(runs: Int, nav: Navigator, seed: Int64? = nil) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.simSeed = seed ?? Self.newSimSeed()
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

    /// Test-harness autorun (launch arguments, see `Autorun`): runs `Autorun.runs` journeys as the
    /// requested persona and seed, then logs `sim_autorun_complete` so the script driving the app knows to
    /// stop waiting.
    func autorun(nav: Navigator) {
        let runs = Autorun.runs
        setVariant(Autorun.variant)
        simulate(runs: runs, nav: nav, seed: Autorun.simSeed)
        let task = runTask
        Task {
            await task?.value
            ScreenLogger.logInfo(SpecEvents.simAutorunComplete, [
                SpecFields.totalRuns: String(runs),
                SpecFields.simSeed: String(Autorun.simSeed),
                SpecFields.persona: Autorun.persona,
            ])
        }
    }

    /// A/B split sim: runs `runsEach` journeys as each variant in sequence. Each
    /// run is a flag transition, maximising workflow matches in the dashboard.
    func abSimulate(runsEach: Int, nav: Navigator) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.simSeed = Self.newSimSeed()
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = runsEach * SimVariant.allCases.count
            self.currentRun = 0

            ScreenLogger.logInfo(SpecEvents.abSimulationStart, [SpecFields.runsEach: String(runsEach)])

            let variants = SimVariant.allCases
            for i in 0..<self.totalRuns {
                if self.isCancelled { break }
                self.activeVariant = variants[i % variants.count]
                self.currentRun += 1
                await self.runSingleJourney(nav)
                await self.sleep(0.05)
            }

            ScreenLogger.logInfo(SpecEvents.abSimulationEnd, [SpecFields.totalRuns: String(self.currentRun)])
            self.finish(nav)
        }
    }

    /// Runs infinite simulation until cancelled.
    func infiniteSimulate(nav: Navigator) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            self.simSeed = Self.newSimSeed()
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

            ScreenLogger.logInfo(SpecEvents.infiniteSimulationStart)

            while !self.isCancelled {
                self.currentRun += 1
                await self.runSingleJourney(nav)
                await self.sleep(0.05)
            }

            ScreenLogger.logInfo(SpecEvents.infiniteSimulationEnd, [SpecFields.totalRuns: String(self.currentRun)])
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

            ScreenLogger.logInfo(SpecEvents.cardinalitySimulationStart)

            while !self.isCancelled {
                self.currentRun += 1
                _ = try? await ApiClient.inventoryLookup(Self.searchQueries.randomElement()!)
                await self.sleep(self.stepDelay)
            }

            ScreenLogger.logInfo(SpecEvents.cardinalitySimulationEnd, [SpecFields.totalRuns: String(self.currentRun)])
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

    private static func newSimSeed() -> Int64 { Int64.random(in: 0..<(1 << 31)) }

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

    // MARK: - Fault injection

    /// Simulates the user force-quitting (swipe-up from the app switcher) on the
    /// ProductDetail screen. The engine decided to inject it and logged
    /// `force_quit_injected`; this persists the restart intent and exits. The Sankey
    /// shows ProductDetail → (dropout) since no subsequent screens are reached.
    ///
    /// iOS has no equivalent of Android's AlarmManager, so the app cannot
    /// schedule its own relaunch — `scripts/watchdog.sh` notices the dead process
    /// and relaunches it, which is what the persisted resume flags below are for.
    private func performForceQuit() {
        Prefs.forceQuit.set(Prefs.keyRestartPending, true)
        Prefs.forceQuit.set(Prefs.keyResumeInfinite, isInfiniteMode)
        Prefs.forceQuit.set(Prefs.keyRestartVariant, activeVariant.rawValue)
        Prefs.forceQuit.flush()

        isCancelled = true

        // A user-initiated app-switcher kill is a clean termination, not a crash.
        // Give the SDK a moment to flush, then exit — the watchdog relaunches.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crashFlush) {
            exit(0)
        }
    }

    /// Simulates a main-thread hang on the CheckoutGuest screen — as if a
    /// synchronous post-checkout validation call blocked the main thread. The engine
    /// calls this after navigation and the API call complete (and has logged
    /// `guest_anr_injected`) so the screen is rendered and visible. The Sankey shows
    /// CheckoutGuest → (dropout) since Payment is never reached.
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
    private func performGuestHang() {
        Prefs.appHang.set(Prefs.keyRestartPending, true)
        Prefs.appHang.set(Prefs.keyResumeInfinite, isInfiniteMode)
        Prefs.appHang.set(Prefs.keyRestartVariant, activeVariant.rawValue)
        Prefs.appHang.flush()

        isCancelled = true

        // Block the main thread so the OS records a real hang. This call is
        // already on the main actor, so sleeping here freezes the UI exactly as a
        // synchronous guest-session validation call would.
        Thread.sleep(forTimeInterval: Self.hangBlockDuration)
        exit(0)
    }

    /// The simplified journey is not run by the engine, so it rolls its own faults
    /// (same probabilities as spec/faults.yaml) and reuses the physical mechanics above.
    private var simplifiedEligible: [String: Int] = [:]

    private func rollSimplifiedFault(_ id: String, probability: Double, forceAfter: Int) -> String? {
        simplifiedEligible[id, default: 0] += 1
        let randomHit = Double.random(in: 0..<1) < probability
        let forcedHit = isInfiniteMode && simplifiedEligible[id, default: 0] >= forceAfter
        guard randomHit || forcedHit else { return nil }
        simplifiedEligible[id] = 0
        return forcedHit && !randomHit ? "forced_infinite" : "random"
    }

    private func maybeInjectForceQuit() -> Bool {
        guard forceQuitEnabled,
              let mode = rollSimplifiedFault("force_quit", probability: 0.60, forceAfter: 3) else { return false }
        ScreenLogger.logError(SpecEvents.forceQuitInjected, [
            SpecFields.forceQuitEnabled: "true",
            SpecFields.forceQuitScreen: Self.forceQuitTargetScreen,
            SpecFields.variant: activeVariant.label,
            SpecFields.triggerMode: mode,
        ])
        performForceQuit()
        return true
    }

    private func maybeInjectGuestHang(isGuest: Bool) -> Bool {
        guard appHangEnabled, activeVariant == .variantA, isGuest,
              let mode = rollSimplifiedFault("anr", probability: 0.25, forceAfter: 6) else { return false }
        ScreenLogger.logError(SpecEvents.guestAnrInjected, [
            SpecFields.anrAEnabled: "true",
            SpecFields.journeyType: "guest",
            SpecFields.anrScreenName: Self.hangTargetScreenName,
            SpecFields.variant: activeVariant.label,
            SpecFields.triggerMode: mode,
        ])
        performGuestHang()
        return true
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
        // Test harness (`-crash <name>` launch argument): that crash, in the foreground, not the sweep.
        if let wanted = Autorun.crash, let entry = Crashes.all.first(where: { $0.name == wanted }) {
            return (entry.name, entry.fire, false)
        }
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

        ScreenLogger.logInfo(SpecEvents.backgroundCrashArmed, [
            SpecFields.hint: "waiting for the app to background",
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

    /// What the session shows just before a crash: the `about_to_crash` announcement and `crash_kind` fields, or,
    /// for a realistic crash, the lead-up a real app would log (no announcement, no crash_kind fields).
    /// Shared by every crash entry point so the new catalog entries behave the same in all of them.
    private func announceCrash(_ name: String, context: String, tag: String = "") {
        if let precursor = Crashes.precursors[name] {
            precursor()
        } else {
            Logger.addField(withKey: SpecFields.crashKind, value: name)
            Logger.addField(withKey: SpecFields.crashContext, value: context)
            ScreenLogger.logWarning("about_to_crash\(tag): \(name) (context=\(context))")
        }
    }

    /// Picks the next crash combo, logs it, then dispatches it.
    private func fireCrashNow() {
        guard crashArmed else { return }
        let combo = pickNextCrashCombo()
        let crashContext = combo.fireInBackground ? "background" : "foreground"
        announceCrash(combo.name, context: crashContext)
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
        // Test harness (`-crash <name>`): that crash, not the sweep.
        if let wanted = Autorun.crash, let entry = Crashes.all.first(where: { $0.name == wanted }) {
            return (entry.name, entry.fire)
        }
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
        guard crashArmed else { return }
        let combo = pickNextCrashOnlyCombo()
        announceCrash(combo.name, context: "foreground")
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
        announceCrash(combo.name, context: crashContext, tag: " (fast)")
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

    // The journey itself is data: spec/journey.yaml, interpreted by `JourneyEngine`
    // (identically on Android, React Native and Flutter). `runSingleJourney` hands the
    // engine one persona, run number and seed; `SimAdapter` below maps its calls onto
    // the navigator, `ApiClient`, the recording facade and the fault mechanics.

    /// Toggles the engine's `if`/`fault`/`crash_point` ops read (spec/faults.yaml ids).
    private var journeyToggles: Set<String> {
        var toggles: Set<String> = []
        if crashArmed { toggles.insert("crash_loop") }
        if appHangEnabled { toggles.insert("anr") }
        if forceQuitEnabled { toggles.insert("force_quit") }
        return toggles
    }

    private lazy var adapter = SimAdapter(self)
    private lazy var engine = JourneyEngine(bundleJson: SpecJourney.json, adapter: adapter)

    private func runSingleJourney(_ navigator: Navigator) async {
        self.navigator = navigator
        // journey_id is a global field for the whole journey: every log, span, network request and
        // (if it comes to that) crash report inside it carries the id.
        Logger.addField(withKey: SpecFields.journeyId, value: "j" + UUID().uuidString.prefix(8).lowercased())
        if AppConfig.simplifiedJourneyEnabled {
            await runSimplifiedPreamble(navigator)
            return
        }
        _ = await engine.run(
            persona: activeVariant.id, run: max(currentRun, 1), simSeed: simSeed,
            toggles: journeyToggles, infinite: isInfiniteMode
        )
    }

    /// Maps the engine's adapter calls onto the iOS app.
    private final class SimAdapter: JourneyAdapter {
        private unowned let sim: SimulationManager

        init(_ sim: SimulationManager) { self.sim = sim }

        func isCancelled() -> Bool { sim.isCancelled }

        // In `realistic` session mode the SDK's inactivity timeout owns session boundaries, so one
        // session spans several journeys; only `per_journey` (the default) starts one per journey.
        func startNewSession() { DemoSettings.startNewSessionForJourney() }

        /// Latest cart response, so checkout_started can carry it as cart_json.
        private var lastCart: JSON?

        func applyExposures(persona: String) { sim.setVariant(sim.activeVariant) }

        func setEntity(_ entity: String) {
            // bitdrift SDK: setEntityID() associates all subsequent logs with this
            // user identity.
            // POC: ad-hoc debugging — search any entity in the dashboard to retrieve
            // all their sessions on demand.
            Logger.setEntityID(entity)
        }

        func delay(ms: Int) async { await sim.sleep(Double(ms) / 1000) }

        func navigate(screen: String, args: [String: String]) async {
            guard let nav = sim.navigator else { return }
            func a(_ key: String) -> String { args[key] ?? "" }
            // `step` is a global field, so every log, span and crash report carries where the journey is.
            Logger.addField(withKey: SpecFields.step, value: screen)
            switch screen {
            case "welcome": nav.popToWelcome()
            case "browse": nav.navigate(to: .browse)
            case "search": nav.navigate(to: .search)
            case "featured": nav.navigate(to: .featured)
            case "categories": nav.navigate(to: .categories)
            case "category_browse": nav.navigate(to: .categoryBrowse(category: a("category")))
            case "product_detail": nav.navigate(to: .productDetail(source: a("source"), productID: a("productId")))
            case "reviews": nav.navigate(to: .reviews(source: a("source"), productID: a("productId")))
            case "cart": nav.navigate(to: .cart(productID: a("productId")))
            case "wishlist": nav.navigate(to: .wishlist(productID: a("productId")))
            case "checkout_guest": nav.navigate(to: .checkoutGuest(productID: a("productId")))
            case "checkout_signin": nav.navigate(to: .checkoutSignIn(productID: a("productId")))
            case "payment_card": nav.navigate(to: .paymentCard(checkoutSession: a("checkoutSession")))
            case "payment_apple_pay": nav.navigate(to: .paymentApplePay(checkoutSession: a("checkoutSession")))
            case "payment_paypal": nav.navigate(to: .paymentPayPal(checkoutSession: a("checkoutSession")))
            case "payment_android_pay": nav.navigate(to: .paymentAndroidPay(checkoutSession: a("checkoutSession")))
            case "payment_failed":
                nav.navigate(to: .paymentFailed(paymentMethod: a("paymentMethod"), checkoutSession: a("checkoutSession")))
            case "confirmation": nav.navigate(to: .confirmation(orderID: a("orderId")))
            default: assertionFailure("unknown journey screen \(screen)")
            }
        }

        func callApi(endpoint: String, args: [String: String]) async -> [String: Any]? {
            let result = await callApiRaw(endpoint: endpoint, args: args)
            switch endpoint {
            case "cart_get", "cart_add", "cart_delete": lastCart = result.map(JSON.init)
            case "confirmation" where result == nil:
                // Payment succeeded but the order cannot be shown: a business-critical failure.
                ScreenLogger.logCritical(SpecEvents.orderLost, [
                    SpecFields.orderId: args["id"] ?? "", SpecFields.reason: "confirmation_unavailable",
                ])
            default: break
            }
            return result
        }

        private func callApiRaw(endpoint: String, args: [String: String]) async -> [String: Any]? {
            func a(_ key: String) -> String { args[key] ?? "" }
            let json: JSON?
            switch endpoint {
            case "welcome": json = try? await ApiClient.getWelcome()
            case "browse": json = try? await ApiClient.getBrowse()
            case "search": json = try? await ApiClient.search(a("q"))
            case "featured": json = try? await ApiClient.getFeatured()
            case "categories": json = try? await ApiClient.getCategories()
            case "category_products": json = try? await ApiClient.getCategoryProducts(a("category"))
            case "product": json = try? await ApiClient.getProduct(a("id"))
            case "reviews": json = try? await ApiClient.getReviews(a("id"))
            case "cart_get": json = try? await ApiClient.getCart()
            case "cart_add": json = try? await ApiClient.addToCart(a("product_id"), quantity: Int(a("quantity")) ?? 1)
            case "cart_delete": json = try? await ApiClient.deleteCartItem(a("id"))
            case "wishlist_add": json = try? await ApiClient.addToWishlist(a("product_id"))
            case "checkout_guest": json = try? await ApiClient.checkoutGuest()
            case "checkout_signin": json = try? await ApiClient.checkoutSignIn()
            case "pay_card": json = try? await ApiClient.payCard(a("checkout_session"), cardLast4: args["card_last4"] ?? "4242")
            case "pay_apple_pay": json = try? await ApiClient.payApplePay(a("checkout_session"))
            case "pay_paypal": json = try? await ApiClient.payPayPal(a("checkout_session"))
            case "pay_android_pay": json = try? await ApiClient.payAndroidPay(a("checkout_session"))
            case "confirmation": json = try? await ApiClient.getConfirmation(a("id"))
            default: fatalError("unknown journey endpoint \(endpoint)")
            }
            return json?.raw as? [String: Any]
        }

        func log(level: String, event: String, fields: [String: String]) {
            // checkout_started carries the cart as one JSON field (JSON-path workflow metrics).
            var f = fields
            if event == SpecEvents.checkoutStarted { f[SpecFields.cartJson] = CartJson.from(lastCart) }
            switch level {
            case "critical": ScreenLogger.logCritical(event, f)
            case "error": ScreenLogger.logError(event, f)
            case "warning": ScreenLogger.logWarning(event, f)
            default: ScreenLogger.logInfo(event, f)
            }
        }

        // bitdrift SDK: startSpan() with parentSpanID builds the journey waterfall
        // (journey → product_discovery/cart_assembly/checkout → sub-phases); all logs are
        // correlated via _span_id.
        // POC: spans waterfall visualization in Timeline; query _duration_ms for
        // p50/p95 of any flow.
        func startSpan(name: String, parent: AnyObject?, fields: [String: String]) -> AnyObject? {
            RecordedSpan.start(
                name: name, level: .info, fields: ScreenLogger.encode(fields),
                parentSpanID: (parent as? RecordedSpan)?.id
            )
        }

        func endSpan(handle: AnyObject, result: String, fields: [String: String]) {
            let spanResult: SpanResult
            switch result {
            case "failure": spanResult = .failure
            case "canceled": spanResult = .canceled
            default: spanResult = .success
            }
            (handle as? RecordedSpan)?.end(spanResult, fields: ScreenLogger.encode(fields))
        }

        func addField(key: String, value: String) { Logger.addField(withKey: key, value: value) }

        func injectFault(id: String) {
            switch id {
            case "force_quit": sim.performForceQuit()
            case "anr": sim.performGuestHang()
            default: break
            }
        }

        func fireCrash() { sim.fireCrashNow() }
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

    /// The setup the engine would otherwise do (new session, journey_started, exposures,
    /// entity), then the fixed path.
    private func runSimplifiedPreamble(_ navigator: Navigator) async {
        // Keep force-quit runs in the startup session so workflows that begin
        // with SDK configuration and end with app termination match in a single
        // session.
        if !forceQuitEnabled {
            DemoSettings.startNewSessionForJourney()
            ScreenLogger.logInfo(SpecEvents.journeyStarted, [
                SpecFields.run: String(currentRun),
                SpecFields.simSeed: String(simSeed),
                SpecFields.variant: activeVariant.label,
            ])
            await sleep(0.2)
            setVariant(activeVariant)
            await sleep(0.2)
        }
        let entity = Self.demoEntities[(max(currentRun, 1) - 1) % Self.demoEntities.count]
        Logger.setEntityID(entity)
        await runSimplifiedJourney(navigator, entity: entity)
    }

    private func runSimplifiedJourney(_ navigator: Navigator, entity: String) async {
        let journeySpan = RecordedSpan.start(
            name: SpecSpans.journey,
            level: .info,
            fields: ScreenLogger.encode([
                SpecFields.variant: activeVariant.label,
                SpecFields.entity: entity,
                SpecFields.mode: "simplified",
            ])
        )

        // ── Step 1: Welcome ──────────────────────────────────────────────
        navigator.popToWelcome()
        _ = try? await ApiClient.getWelcome()
        await sleep(stepDelay)

        // ── Step 2: Browse ───────────────────────────────────────────────
        // bitdrift SDK: trackSpan() — the same discovery_fetch span the full
        // journey uses (see spec/journey.yaml), parented directly on journeySpan
        // since this mode has no separate discoverySpan. Without a call site
        // here, bd-shop-22's discovery_fetch chart is empty for anyone who opts
        // into this mode (SIMPLIFIED_JOURNEY_ENABLED = YES; the committed
        // default in local.xcconfig is NO, i.e. the full random journey).
        // POC: event tracking — sub-phase waterfall, populated regardless of
        // which journey mode is active.
        let productIDs = await CaptureBridge.trackSpan(
            SpecSpans.discoveryFetch, parentSpanID: journeySpan?.id
        ) { _ in
            await nav(navigator, .browse)
            return await fetchBrowseIDs()
        }
        let pid = productIDs.randomElement() ?? Self.fallbackProductID

        // ── Step 3: ProductDetail ────────────────────────────────────────
        // bitdrift SDK: trackSpan() — same product_view span the full journey
        // uses; this mode has no Reviews step, so it only covers the
        // ProductDetail fetch. Force-quit injection aborts the whole journey,
        // not just this span — same Bool-signal pattern as the full
        // journey's product_view for why a bare `return` inside the closure won't do.
        // POC: event tracking — sub-phase waterfall.
        let forceQuitInjected = await CaptureBridge.trackSpan(
            SpecSpans.productView, parentSpanID: journeySpan?.id
        ) { _ -> Bool in
            await nav(navigator, .productDetail(source: "browse", productID: pid))
            _ = try? await ApiClient.getProduct(pid)

            // Force-quit injection, same placement as the full journey: after
            // ProductDetail renders and its API call completes. Kept here so the
            // persisted force-quit toggle behaves identically in both modes — and
            // so the spec journey's force-quit session suppression is never
            // applied to a mode that can't actually inject the quit.
            return maybeInjectForceQuit()
        }
        if forceQuitInjected {
            journeySpan?.end(.canceled, fields: ScreenLogger.encode([SpecFields.reason: "force_quit_injected"]))
            return
        }

        // ── Step 4: Cart ─────────────────────────────────────────────────
        // bitdrift SDK: trackSpan() — same cart_assembly span the full journey
        // uses, though this mode only does the one plain addToCart (no extra
        // items/remove/flip logic).
        // POC: event tracking — sub-phase waterfall.
        await CaptureBridge.trackSpan(SpecSpans.cartAssembly, parentSpanID: journeySpan?.id) { _ in
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
            journeySpan?.end(.canceled, fields: ScreenLogger.encode([SpecFields.reason: "guest_hang_injected"]))
            return
        }

        if crashLoopEnabled {
            // Distinct value from the random sweep's `crash_journey_point`
            // (cart/checkout/payment/...) so this mode's crashes are
            // unambiguously identifiable in the raw log stream and in any
            // chart grouped by that field.
            Logger.addField(withKey: SpecFields.crashJourneyPoint, value: "simplified_step_5_checkout_guest")
            ScreenLogger.logWarning("simplified_journey_crash_point (step 5 of 7): CheckoutGuest")
            fireSimplifiedCrashNow()
            journeySpan?.end(.canceled, fields: ScreenLogger.encode([SpecFields.reason: "simplified_crash_step_5"]))
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
        await CaptureBridge.trackSpan(SpecSpans.checkoutConfirmation, parentSpanID: journeySpan?.id) { _ in
            _ = try? await ApiClient.getConfirmation(orderID)
        }

        ScreenLogger.logInfo(SpecEvents.simplifiedJourneyCompleted, [
            SpecFields.stepsCompleted: "7",
            SpecFields.variant: activeVariant.label,
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
            SpecSpans.checkoutPayment, fields: [SpecFields.retried: String(retried)], parentSpanID: parentSpanID
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

    private static let hangTargetScreenName = SpecScreen.checkoutGuest.screenName
    private static let hangProbability = 0.25
    private static let hangForceAfterEligibleGuestJourneys = 6
    private static let hangBlockDuration: TimeInterval = 15

    private static let forceQuitTargetScreen = SpecScreen.productDetail.screenName
    private static let forceQuitProbability = 0.60
    private static let forceQuitForceAfterJourneys = 3
}
