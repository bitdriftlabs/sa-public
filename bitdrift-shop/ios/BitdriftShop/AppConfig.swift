import Foundation

/// Build-time configuration, read from `Info.plist` keys that are populated from
/// `local.xcconfig` / `.local.xcconfig`. This is the iOS counterpart of the
/// Android app's generated `BuildConfig`.
///
/// Every value falls back to an environment variable of the same name first, so
/// CI and `xcodebuild`-driven runs can override without editing a file.
enum AppConfig {

    /// bitdrift SDK key. Empty means the SDK still starts but never uploads —
    /// the Welcome screen's Device Code button surfaces that as `needs_sdk_key`.
    static let sdkKey = value(for: "BITDRIFT_SDK_KEY") ?? ""

    /// bitdrift API host, e.g. `api.bitdrift.io`.
    static let apiHost = value(for: "BITDRIFT_API_HOST") ?? "api.bitdrift.io"

    static var apiURL: URL {
        URL(string: "https://\(apiHost)") ?? URL(string: "https://api.bitdrift.io")!
    }

    /// Base URL of the bitdrift-shop FastAPI backend.
    ///
    /// The iOS Simulator shares the host's network stack, so `localhost` reaches
    /// the backend directly — unlike the Android emulator, which needs the
    /// `10.0.2.2` alias. Override for a physical device (set it to the Mac's LAN
    /// address) via `BITDRIFT_BACKEND_URL` in `.local.xcconfig`.
    static let backendURL = value(for: "BITDRIFT_BACKEND_URL") ?? "http://localhost:5173"

    static var apiBaseURL: String { backendURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/api" }

    /// Optional demo toggles, mirroring the Android BuildConfig flags.
    static let showCardinality = flag("SHOW_CARDINALITY")
    static let showSimAB = flag("SHOW_SIM_AB")

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
