import Capture
import SwiftUI
import UIKit

@main
struct ShoppingDemoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastPhase: ScenePhase?

    // Workshop 3 -- App Launch TTI (basic sdk): process-level start time, so the root view's
    // first `onAppear` (this SDK's closest signal to Android's "first frame drawn") can compute
    // a rough time-to-interactive. No `reportFullyDrawn()` equivalent exists on iOS/SwiftUI.
    private static let appStartTime = CFAbsoluteTimeGetCurrent()

    init() {
        // Workshop 1 -- Initialization (basic sdk): https://docs.bitdrift.io/sdk/quickstart#ios
        //
        // otelExportConfiguration (BIT-9050 local ClickStack demo): only set when both
        // CLICKSTACK_ENDPOINT and CLICKSTACK_INGESTION_API_KEY are configured
        // (.local.xcconfig), so the feature stays off by default rather than pointing at a
        // blank URL. Unlike Android, there is no "published SDK vs. local build" toggle here --
        // this app only ever links the local Capture.xcframework in Frameworks/, so
        // OtelExportConfiguration is always available to reference (see README.md).
        let otelExportConfiguration: OtelExportConfiguration? = {
            guard !AppConfig.clickstackEndpoint.isEmpty, !AppConfig.clickstackIngestionAPIKey.isEmpty,
                  let url = URL(string: AppConfig.clickstackEndpoint)
            else {
                return nil
            }
            return OtelExportConfiguration(endpoint: url, authHeaderValue: AppConfig.clickstackIngestionAPIKey)
        }()

        // Matches Android's `HttpUrl.Builder().scheme("https").host(BuildConfig.BITDRIFT_API_HOST)` --
        // AppConfig only stores the host, so build the full URL Configuration expects.
        let apiURL = URL(string: "https://\(AppConfig.bitdriftAPIHost)") ?? URL(string: "https://api.bitdrift.io")!

        let integrator = Capture.Logger.start(
            withAPIKey: AppConfig.bitdriftSDKKey,
            sessionConfiguration: .init(),
            configuration: Configuration(apiURL: apiURL, otelExportConfiguration: otelExportConfiguration)
        )

        // Unlike Android's per-client OkHttp interceptor (which this demo wires manually, as a
        // deliberate "Workshop 1b" teaching step -- see `automaticOkHttpInstrumentation = false`
        // in the Android build.gradle.kts and `ApiClient.kt`'s explicit `CaptureOkHttpTracingInterceptor`),
        // iOS's URLSession integration is a single process-wide swizzle with no per-client
        // opt-out, so there is no manual/automatic distinction to preserve here -- this is simply
        // what "network instrumentation is on" looks like on this platform.
        integrator?.enableIntegrations([.urlSession()])

        Capture.Logger.shared?.logInfo("app_launched")

        // Workshop 5 -- Global Fields: attached to every log, span, and network request for the
        // lifetime of this process. Not persisted -- re-added on each start.
        Capture.Logger.shared?.addField(withKey: "app_variant", value: "otel-demo")
        Capture.Logger.shared?.addField(withKey: "platform", value: "ios")

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            Capture.Logger.shared?.logWarning("memory_pressure", fields: ["level": "didReceiveMemoryWarning"])
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    let ttiSeconds = CFAbsoluteTimeGetCurrent() - Self.appStartTime
                    Capture.Logger.shared?.logAppLaunchTTI(ttiSeconds)
                }
                .onChange(of: scenePhase) { phase in
                    self.handleScenePhaseChange(phase)
                }
        }
    }

    /// Emits the foreground/background events Android gets from `ActivityLifecycleCallbacks`.
    /// `scenePhase` also reports `.inactive` on transient interruptions (control centre,
    /// incoming call) -- only real foreground/background edges are logged, matching Android's
    /// activity-count-based logic.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        defer { self.lastPhase = phase }
        switch phase {
        case .active where self.lastPhase != .active:
            Capture.Logger.shared?.logInfo("app_open", fields: ["trigger": "scenePhase.active"])
        case .background where self.lastPhase != .background:
            Capture.Logger.shared?.logInfo("app_close", fields: ["trigger": "scenePhase.background"])
        default:
            break
        }
    }
}
