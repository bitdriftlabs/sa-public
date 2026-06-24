import SwiftUI
import Shared
import Capture

@main
struct ShoppingDemoKMPApp: App {
    // Capture wall-clock time at process start for TTI measurement.
    private static let appStartTime = Date()

    init() {
        // Read API key from Info.plist, which is populated from .local.xcconfig via
        // the BITDRIFT_SDK_KEY build setting. Falls back to the BITDRIFT_SDK_KEY
        // environment variable for CI / automated builds.
        let apiKey = Bundle.main.infoDictionary?["BITDRIFT_SDK_KEY"] as? String
            ?? ProcessInfo.processInfo.environment["BITDRIFT_SDK_KEY"] ?? ""

        // Read API host from Info.plist (populated from .local.xcconfig via
        // BITDRIFT_API_HOST). Falls back to env var, then the default host.
        let apiHostRaw = Bundle.main.infoDictionary?["BITDRIFT_API_HOST"] as? String
        let apiHostEnv = ProcessInfo.processInfo.environment["BITDRIFT_API_HOST"]
        let apiURLString = apiHostRaw.flatMap { $0.isEmpty ? nil : $0 }
            ?? apiHostEnv
            ?? "api.bitdrift.io"
        let apiURL = URL(string: "https://\(apiURLString)")
            ?? URL(string: "https://api.bitdrift.io")!

        // Start the Capture SDK and enable URLSession auto-instrumentation so every
        // network request/response is logged in the bitdrift dashboard automatically.
        Logger
            .start(withAPIKey: apiKey, sessionStrategy: .fixed(),
                   configuration: .init(apiURL: apiURL))?
            .enableIntegrations([.urlSession()])

        // Attach a stable field to every log, span, and network event.
        Logger.addField(withKey: "app_variant", value: "kmp-demo")

        ScreenLogger.logInfo("app_launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Measure time from process start to first rendered frame.
                    let tti = Date().timeIntervalSince(Self.appStartTime)
                    Logger.logAppLaunchTTI(tti)
                }
        }
    }
}
