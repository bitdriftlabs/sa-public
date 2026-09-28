import Foundation

/// Build-time configuration, read from `Info.plist` keys populated from `local.xcconfig` /
/// `.local.xcconfig`. The iOS counterpart of Android's generated `BuildConfig` — see
/// `bitdrift-shop/ios-clean/BitdriftShop/AppConfig.swift` for the precedent this follows.
enum AppConfig {
    static let bitdriftSDKKey = value(for: "BITDRIFT_SDK_KEY") ?? ""
    static let bitdriftAPIHost = value(for: "BITDRIFT_API_HOST") ?? "api.bitdrift.io"

    /// iOS Simulator shares the Mac's network directly, so `localhost` just works — unlike
    /// Android's emulator, which needs the `10.0.2.2` NAT alias. Only a physical device needs
    /// this overridden to the Mac's LAN IP (`ipconfig getifaddr en0`).
    static let otelDemoHost = value(for: "OTEL_DEMO_HOST") ?? "localhost"
    static let otelDemoPort = value(for: "OTEL_DEMO_PORT") ?? "8081"

    /// OTel span export (BIT-9050 local ClickStack demo). Blank endpoint means the feature stays
    /// off (see `OtelExportConfiguration` wiring in `ShoppingDemoApp.swift`).
    static let clickstackEndpoint = value(for: "CLICKSTACK_ENDPOINT") ?? ""
    static let clickstackIngestionAPIKey = value(for: "CLICKSTACK_INGESTION_API_KEY") ?? ""

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Whether the linked `Capture.xcframework` in `Frameworks/` declares the Rust-backed
    /// `capture_build_otel_span_payload` bridge function -- i.e. whether it was built from the
    /// capture-sdk branch that moved OTel span building into shared-core. There is no "published
    /// SDK" toggle on iOS yet (unlike Android's Maven Central fallback) since this demo only ever
    /// links the local xcframework -- see README.md.
    ///
    /// Unlike Android's `Class.forName(...).declaredMethods` reflection check, Swift has no
    /// runtime reflection into a C symbol table -- `dlsym` against the current process image is
    /// the closest real equivalent, and actually checks the linked binary rather than assuming.
    static var aarHasRustSpanBuilder: Bool {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "capture_build_otel_span_payload") != nil
    }

    // MARK: - Private

    private static func value(for key: String) -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment[key],
            Bundle.main.infoDictionary?[key] as? String,
        ]
        // xcconfig substitution leaves the literal `$(NAME)` behind when a setting is undefined;
        // treat that (and blank) as "not configured".
        return candidates
            .compactMap { $0 }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
    }
}
