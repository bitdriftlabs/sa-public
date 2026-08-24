import Foundation

/// Build-time configuration, read from `Info.plist` keys that are populated from
/// `local.xcconfig` / `.local.xcconfig`. This is the iOS counterpart of the
/// Android app's generated `BuildConfig`.
///
/// Every value falls back to an environment variable of the same name first, so
/// CI and `xcodebuild`-driven runs can override without editing a file.
enum AppConfig {

    /// Optional override for the demo shop's backend, e.g. when the Mac's LAN IP
    /// changes or several devices share one backend. Nil unless set, in which
    /// case `ApiClient` falls back to its compiled-in per-environment defaults.
    static let shopBackendURL = value(for: "SHOP_BACKEND_URL")

    /// Optional demo toggles, mirroring the Android BuildConfig flags.
    static let showCardinality = flag("SHOW_CARDINALITY")
    static let showSimAB = flag("SHOW_SIM_AB")

    /// Whether the crash sweep includes background-half crashes.
    ///
    /// Those need an external actor to take the foreground before they can fire,
    /// which is unreliable — and a crash that never fires stalls the sweep. Off
    /// by default so every crash lands in the foreground.
    static let backgroundCrashesEnabled = flag("ENABLE_BACKGROUND_CRASHES")

    /// Whether the memory-exhaustion variants are in the default sweep.
    ///
    /// They block the caller for ~35s each and need a 45s restart delay, so six
    /// of them dominate a sweep and leave the app looking hung. Off by default;
    /// the "OOMs" mode on the Advanced screen still reaches them explicitly.
    static let oomCrashesEnabled = flag("ENABLE_OOM_CRASHES")

    /// Replaces the randomized shopping journey with a fixed 7-step path
    /// (Welcome → Browse → ProductDetail → Cart → CheckoutGuest → PaymentCard
    /// → Confirmation), and — when
    /// the crash loop is also on — an unconditional crash right after step 5
    /// (CheckoutGuest), every journey, no random branching, no probabilistic
    /// crash-point selection.
    ///
    /// Step 5 is deliberate, not just "the checkout step": it is exactly where
    /// the checkout funnel is deepest.
    ///
    /// Built for a concrete before/after comparison: with the crash loop off, every journey
    /// completes all 7 steps ("before" — proves the path itself is sound). With
    /// it on, every journey stops at exactly step 5 ("after" — no ambiguity
    /// about which step). See `SimulationManager.runSimplifiedJourney`.
    static let simplifiedJourneyEnabled = flag("SIMPLIFIED_JOURNEY_ENABLED")

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Private

    private static func value(for key: String) -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment[key],
            Bundle.main.infoDictionary?[key] as? String,
        ]
        // xcconfig substitution leaves the literal `$(NAME)` behind when a
        // setting is undefined; treat that (and blank) as "not configured".
        return candidates
            .compactMap { $0 }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
    }

    private static func flag(_ key: String) -> Bool {
        let raw = (value(for: key) ?? "NO").lowercased()
        return raw == "yes" || raw == "true" || raw == "1"
    }
}
