import Foundation

/// Build-time configuration, read from `Info.plist` keys that are populated from
/// `local.xcconfig` / `.local.xcconfig`. This is the iOS counterpart of the
/// Android app's generated `BuildConfig`.
///
/// Every value falls back to an environment variable of the same name first, so
/// CI and `xcodebuild`-driven runs can override without editing a file.
enum AppConfig {

    /// bitdrift API key — what the platform calls this credential, and the name
    /// the SDK itself uses (`Logger.start(withAPIKey:)`). The same key authorizes
    /// the build-time dSYM upload in `scripts/upload-symbols.sh`.
    ///
    /// Empty means the SDK still starts but never uploads — the Welcome screen's
    /// Device Code button surfaces that as `needs_api_key`.
    static let apiKey = value(for: "BITDRIFT_API_KEY") ?? ""

    /// bitdrift API host, e.g. `api.bitdrift.io`.
    static let apiHost = value(for: "BITDRIFT_API_HOST") ?? "api.bitdrift.io"

    static var apiURL: URL {
        URL(string: "https://\(apiHost)") ?? URL(string: "https://api.bitdrift.io")!
    }

    /// Optional override for the demo shop's backend, e.g. when the Mac's LAN IP
    /// changes or several devices share one backend. Nil unless set, in which
    /// case `ApiClient` falls back to its compiled-in per-environment defaults.
    ///
    /// Nothing to do with the bitdrift platform — that is `BITDRIFT_API_HOST`.
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

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// The Capture SDK version this build actually linked against, reported by
    /// the SDK itself rather than hardcoded — so the Welcome screen can never
    /// claim a version the binary doesn't match.
    static var captureSDKVersion: String { CaptureBridge.sdkVersion }

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
