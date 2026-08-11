import Capture
import SwiftUI

enum StartupPhase {
    case config
    case app
}

struct ContentView: View {
    @StateObject private var nav = Navigator()
    @StateObject private var sim = SimulationManager()
    @StateObject private var metrics = MetricsDemoManager()

    @State private var phase: StartupPhase = ContentView.initialPhase()

    var body: some View {
        Group {
            switch phase {
            case .config:
                StartupConfigScreen(sim: sim) { phase = .app }
            case .app:
                appBody
            }
        }
    }

    /// Fast crash mode restarts through the same startup flow as every other
    /// crash — skip the splash/countdown for it too, or every fast-mode restart
    /// would pay a mandatory 5s delay, defeating the point of "fast".
    private static func initialPhase() -> StartupPhase {
        let resumeRequested = Prefs.appHang.bool(Prefs.keyRestartPending)
            || Prefs.forceQuit.bool(Prefs.keyRestartPending)
            || Prefs.appHang.bool(Prefs.keyResumeInfinite)
            || Prefs.forceQuit.bool(Prefs.keyResumeInfinite)
        let fastCrashActive = Prefs.crashLoop.bool(Prefs.keyActive)
            && Prefs.crashLoop.bool(Prefs.keyFastMode)
        return resumeRequested || fastCrashActive ? .app : .config
    }

    private var appBody: some View {
        NavigationStack(path: $nav.path) {
            WelcomeScreen(sim: sim)
                .navigationDestination(for: Screen.self) { screen in
                    destination(for: screen)
                        .navigationBarBackButtonHidden()
                        .toolbar(.hidden, for: .navigationBar)
                }
                .navigationBarBackButtonHidden()
                .toolbar(.hidden, for: .navigationBar)
        }
        .environmentObject(nav)
        .overlay(alignment: .bottom) {
            // Floating simulation overlay — visible on all screens during a run.
            if sim.isSimulating {
                SimulationOverlay(sim: sim).padding(.bottom, 16)
            }
        }
        .overlay {
            // Fast crash mode skips all navigation and UI by design, so cover the
            // screen with an explicit status splash rather than leaving whatever
            // the last frame happened to be — otherwise a slow crash (or one that
            // doesn't fire) is indistinguishable on-device from a hung app.
            if sim.crashLoopEnabled && sim.fastCrashModeEnabled {
                FastCrashModeSplash(status: sim.fastCrashStatus, awaitingBackground: sim.awaitingBackground)
            }
        }
        .task { await runStartupSequence() }
    }

    @ViewBuilder
    private func destination(for screen: Screen) -> some View {
        switch screen {
        case .welcome:
            WelcomeScreen(sim: sim)
        case .advanced:
            AdvancedScreen(sim: sim, metrics: metrics)
        case .browse:
            BrowseScreen(sim: sim)
        case .search:
            SearchScreen()
        case .featured:
            FeaturedProductsScreen()
        case .categories:
            CategoriesScreen()
        case .categoryBrowse(let category):
            CategoryBrowseScreen(category: category)
        case .productDetail(let source, let productID):
            ProductDetailScreen(source: source, productID: productID, sim: sim)
        case .reviews(let source, let productID):
            ReviewsScreen(source: source, productID: productID)
        case .cart(let productID):
            CartScreen(productID: productID)
        case .wishlist(let productID):
            WishlistScreen(productID: productID)
        case .checkoutGuest(let productID):
            CheckoutGuestScreen(productID: productID)
        case .checkoutSignIn(let productID):
            CheckoutSignInScreen(productID: productID)
        case .paymentCard(let session):
            PaymentScreen(method: .card, checkoutSession: session)
        case .paymentApplePay(let session):
            PaymentScreen(method: .applePay, checkoutSession: session)
        case .paymentPayPal(let session):
            PaymentScreen(method: .payPal, checkoutSession: session)
        case .paymentAndroidPay(let session):
            PaymentScreen(method: .androidPay, checkoutSession: session)
        case .paymentFailed(let paymentMethod, let session):
            PaymentFailedScreen(paymentMethod: paymentMethod, checkoutSession: session)
        case .confirmation(let orderID):
            ConfirmationScreen(orderID: orderID)
        }
    }

    /// Restores persisted fault flags and resumes whatever the previous run was
    /// doing before it crashed, hung, or was force-quit. On Android an
    /// AlarmManager relaunch carries this across the process boundary; on iOS the
    /// relaunch comes from `scripts/watchdog.sh` and the intent is read back here.
    private func runStartupSequence() async {
        nav.logInitialScreen()

        // bitdrift SDK: logAppLaunchTTI() reports time-to-interactive from process
        // start to the first rendered frame. Only the first call per Logger.start()
        // takes effect.
        // POC: event tracking — unsampled p50/p95/p99 TTI histogram across the full
        // user population.
        if let tti = CaptureBridge.timeToInteractive {
            Logger.logAppLaunchTTI(tti)
        }

        sim.crashLoopEnabled = Prefs.crashLoop.bool(Prefs.keyActive)
        sim.fastCrashModeEnabled = Prefs.crashLoop.bool(Prefs.keyFastMode)
        sim.syncAppHangEnabledState()
        sim.syncForceQuitEnabledState()

        // Promote whatever was resolved into the persistent store. Flags supplied
        // as launch arguments land in NSArgumentDomain, which is not persisted —
        // so without this, arming a demo from the command line would survive
        // exactly one launch and the watchdog's next relaunch would come up
        // disarmed. Writing back is a no-op when the values already came from the
        // store. `scripts/check-demo-state.sh --reset` is the way to clear them.
        Prefs.crashLoop.set(Prefs.keyActive, sim.crashLoopEnabled)
        Prefs.crashLoop.set(Prefs.keyFastMode, sim.fastCrashModeEnabled)
        Prefs.crashLoop.set(Prefs.keyOomOnly, Prefs.crashLoop.bool(Prefs.keyOomOnly))
        Prefs.appHang.set(Prefs.keyActive, sim.appHangEnabled)
        Prefs.forceQuit.set(Prefs.keyActive, sim.forceQuitEnabled)
        Prefs.autoInfinite.set(Prefs.keyActive, Prefs.autoInfinite.bool(Prefs.keyActive))

        // A pending background crash lives in memory (`pendingBackgroundCrash`),
        // so it cannot survive a process restart. Clearing the persisted flag here
        // stops a stale `true` from outliving the process that armed it and making
        // the watchdog background the app for a crash that will never fire.
        Prefs.crashLoop.set(Prefs.keyAwaitingBackground, false)
        Prefs.crashLoop.flush()

        // These flags persist across launches and silently change what the app
        // does, so record what was actually armed at startup. Saves guessing at
        // "why did it crash / why didn't it" from the session timeline alone.
        ScreenLogger.logInfo("demo_flags_resolved", [
            "crash_loop": String(sim.crashLoopEnabled),
            "fast_crash": String(sim.fastCrashModeEnabled),
            "oom_only": String(Prefs.crashLoop.bool(Prefs.keyOomOnly)),
            "app_hang": String(sim.appHangEnabled),
            "force_quit": String(sim.forceQuitEnabled),
            "auto_infinite": String(Prefs.autoInfinite.bool(Prefs.keyActive)),
        ])
        DemoStateFile.publish()

        // Fast crash mode is self-sustaining and bypasses the shopping journey
        // entirely — fire the next combo and skip every other resume path below.
        if sim.crashLoopEnabled && sim.fastCrashModeEnabled {
            sim.fireFastCrash()
            return
        }

        let hangRestartPending = Prefs.appHang.bool(Prefs.keyRestartPending)
        let quitRestartPending = Prefs.forceQuit.bool(Prefs.keyRestartPending)
        let hangResumeInfinite = Prefs.appHang.bool(Prefs.keyResumeInfinite)
        let quitResumeInfinite = Prefs.forceQuit.bool(Prefs.keyResumeInfinite)
        let crashResumeInfinite = Prefs.crashLoop.bool(Prefs.keyResumeInfiniteWithCrash)
        let hadResumeRequest = hangRestartPending || quitRestartPending
            || hangResumeInfinite || quitResumeInfinite || crashResumeInfinite

        if crashResumeInfinite {
            Prefs.crashLoop.set(Prefs.keyResumeInfiniteWithCrash, false)
            Prefs.crashLoop.flush()
            sim.restoreVariantFromPrefs()
            ScreenLogger.logInfo("crash_restart_resume", ["variant": sim.activeVariant.label])
            sim.scheduleAutoStartInfinite()
        } else if hangRestartPending || hangResumeInfinite {
            Prefs.appHang.set(Prefs.keyRestartPending, false)
            Prefs.appHang.set(Prefs.keyResumeInfinite, false)
            Prefs.appHang.flush()
            sim.restoreVariantFromPrefs()
            ScreenLogger.logInfo("anr_restart_resume", [
                "mode": hangResumeInfinite ? "infinite" : "single",
                "pending_flag": String(hangRestartPending),
            ])
            hangResumeInfinite ? sim.scheduleAutoStartInfinite() : sim.scheduleAutoStart()
        } else if quitRestartPending || quitResumeInfinite {
            Prefs.forceQuit.set(Prefs.keyRestartPending, false)
            Prefs.forceQuit.set(Prefs.keyResumeInfinite, false)
            Prefs.forceQuit.flush()
            sim.restoreVariantFromPrefs()
            ScreenLogger.logInfo("force_quit_restart_resume", [
                "mode": quitResumeInfinite ? "infinite" : "single",
                "pending_flag": String(quitRestartPending),
            ])
            quitResumeInfinite ? sim.scheduleAutoStartInfinite() : sim.scheduleAutoStart()
        }

        // Relaunch timing can race with SwiftUI readiness. Retry auto-start a few
        // times so infinite sim reliably resumes.
        for _ in 0..<5 {
            sim.tryAutoStart(nav)
            if sim.isSimulating { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        if hadResumeRequest && !sim.isSimulating {
            ScreenLogger.logError("restart_autostart_missed", [
                "anr_restart_pending": String(hangRestartPending),
                "fq_restart_pending": String(quitRestartPending),
                "anr_resume_infinite": String(hangResumeInfinite),
                "fq_resume_infinite": String(quitResumeInfinite),
            ])
        }
    }
}

// MARK: - Startup config

struct StartupConfigScreen: View {
    @ObservedObject var sim: SimulationManager
    let onDone: () -> Void

    @State private var crashEnabled = Prefs.crashLoop.bool(Prefs.keyActive)
    @State private var fastCrashEnabled = Prefs.crashLoop.bool(Prefs.keyFastMode)
    @State private var oomOnlyEnabled = Prefs.crashLoop.bool(Prefs.keyOomOnly)
    @State private var autoInfiniteEnabled = Prefs.autoInfinite.bool(Prefs.keyActive)
    @State private var countdown = 5

    /// OOM mode is journey-based, not fast — it only ever produces crashes by
    /// running the sim loop to Confirmation and back. Rather than let "Fast crash
    /// mode" and "Auto ∞ sim" silently contradict that, lock them to the
    /// combination OOM mode actually needs: fast off, infinite sim on.
    private var oomModeActive: Bool { crashEnabled && oomOnlyEnabled }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Bitdrift Shop Config")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("Auto-starting sim in")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                Text("\(countdown)s")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Palette.green)

                Divider().overlay(Color.white.opacity(0.2))

                toggleRow("Crash mode", isOn: $crashEnabled, tint: Palette.crimson, enabled: true,
                          activeColor: crashEnabled ? Palette.crimson : .white)

                // Skips the shopping journey entirely and fires the next crash
                // combo immediately on every relaunch — only meaningful with
                // Crash mode on.
                toggleRow("Fast crash mode", isOn: $fastCrashEnabled, tint: Palette.violet,
                          enabled: crashEnabled && !oomModeActive,
                          activeColor: !crashEnabled || oomModeActive
                              ? .white.opacity(0.4)
                              : (fastCrashEnabled ? Palette.violet : .white))

                // Restricts the crash loop (fast or normal) to Crashes.oomOnly
                // instead of the full catalog.
                toggleRow("OOM crashes only", isOn: $oomOnlyEnabled, tint: Palette.orange,
                          enabled: crashEnabled,
                          activeColor: !crashEnabled
                              ? .white.opacity(0.4)
                              : (oomOnlyEnabled ? Palette.orange : .white))

                toggleRow("Auto ∞ sim", isOn: autoInfiniteBinding, tint: Palette.purple,
                          enabled: !oomModeActive,
                          activeColor: oomModeActive
                              ? .white.opacity(0.4)
                              : (autoInfiniteEnabled ? Palette.purple : .white))

                Button {
                    Prefs.crashLoop.set(Prefs.keyActive, false)
                    Prefs.crashLoop.set(Prefs.keyFastMode, false)
                    Prefs.crashLoop.set(Prefs.keyOomOnly, false)
                    sim.crashLoopEnabled = false
                    sim.fastCrashModeEnabled = false
                    onDone()
                } label: {
                    Text("Skip -> Normal App")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(32)
            .background(Palette.logoBackdrop, in: RoundedRectangle(cornerRadius: 16))
            .padding(32)
        }
        .onChange(of: oomModeActive) { active in
            guard active else { return }
            if fastCrashEnabled { fastCrashEnabled = false }
            if !autoInfiniteEnabled { setAutoInfinite(true) }
        }
        .task {
            for i in stride(from: 5, through: 1, by: -1) {
                countdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            // Flush, not fire-and-forget: with fast crash mode on, the crash can
            // land within a second or two of this write, and an unflushed write
            // can lose that race and silently revert these flags on the next cold
            // start.
            Prefs.crashLoop.set(Prefs.keyActive, crashEnabled)
            Prefs.crashLoop.set(Prefs.keyFastMode, fastCrashEnabled)
            Prefs.crashLoop.set(Prefs.keyOomOnly, crashEnabled && oomOnlyEnabled)
            Prefs.crashLoop.flush()

            sim.crashLoopEnabled = crashEnabled
            sim.fastCrashModeEnabled = fastCrashEnabled
            DemoStateFile.publish()
            if autoInfiniteEnabled { sim.scheduleAutoStartInfinite() }
            onDone()
        }
    }

    private var autoInfiniteBinding: Binding<Bool> {
        Binding(
            get: { autoInfiniteEnabled || oomModeActive },
            set: { setAutoInfinite($0) }
        )
    }

    private func setAutoInfinite(_ value: Bool) {
        autoInfiniteEnabled = value
        Prefs.autoInfinite.set(Prefs.keyActive, value)
    }

    private func toggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        tint: Color,
        enabled: Bool,
        activeColor: Color
    ) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(activeColor)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
                .disabled(!enabled)
        }
    }
}
