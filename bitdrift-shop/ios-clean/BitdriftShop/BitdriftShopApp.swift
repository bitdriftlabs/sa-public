import SwiftUI
import UIKit

@main
struct BitdriftShopApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLifecycleObserver.shared.register()

        // SIGTERM has to be trapped before anything can send one.
        WatchdogHangs.installTerminationHandler()

        // Blocks here if a scene-create hang is armed. Deliberately after
        // app startup, so the breadcrumb explaining the hang is actually
        // captured — and still inside the launch window the OS is timing, which
        // is what makes the report come back as `WatchdogEvent: scene-create`
        // rather than a plain unresponsive app.
        WatchdogHangs.blockIfArmed(for: .sceneCreate)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { phase in
                    AppLifecycleObserver.shared.handle(phase)
                }
        }
    }
}

/// Emits the foreground/background and memory-pressure events the Android app
/// gets from `ActivityLifecycleCallbacks` and `ComponentCallbacks2`.
///
/// Foreground/background comes from SwiftUI's `scenePhase`. Memory warnings have
/// no SwiftUI equivalent, so that one still comes from the UIKit notification —
/// an API call, not an Objective-C class of our own.
final class AppLifecycleObserver {

    static let shared = AppLifecycleObserver()

    private var registered = false
    private var lastPhase: ScenePhase?

    func register() {
        guard !registered else { return }
        registered = true

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            ScreenLogger.logWarning("memory_pressure", ["level": "didReceiveMemoryWarning"])
        }
    }

    func handle(_ phase: ScenePhase) {
        // scenePhase also reports `.inactive` on transient interruptions (control
        // centre, incoming call). Only log real foreground/background edges, so
        // app_open/app_close stay comparable with the Android app's counts.
        defer { lastPhase = phase }
        switch phase {
        case .active where lastPhase == .background:
            // Returning to the foreground is the scene-update transition, so
            // block here if that hang is armed. Only on a real background ->
            // active edge; `.inactive -> .active` (control centre, notification
            // banner) is not a scene update and would fire at the wrong moment.
            ScreenLogger.logInfo("app_open", ["trigger": "scenePhase.active"])
            WatchdogHangs.blockIfArmed(for: .sceneUpdate)
        case .active where lastPhase != .active:
            ScreenLogger.logInfo("app_open", ["trigger": "scenePhase.active"])
        case .background where lastPhase != .background:
            ScreenLogger.logInfo("app_close", ["trigger": "scenePhase.background"])
        default:
            break
        }
    }
}
