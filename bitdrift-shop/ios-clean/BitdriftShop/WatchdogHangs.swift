import Foundation
import UIKit

/// Reproduces iOS watchdog terminations — `0x8BADF00D`, reported as **App Hang**.
///
/// These are the largest single class of iOS crashes seen in the field,
/// and nothing in the Swift-trap / POSIX-signal catalog can produce them: they
/// are not exceptions at all. The OS gives an app a wall-clock budget to finish a
/// lifecycle transition, and kills it via RunningBoard when it overruns:
///
///     <RBSTerminateContext| domain:10 code:0x8BADF00D
///        explanation:scene-create watchdog transgression: ...
///        exhausted real (wall clock) time allowance of 10.00 seconds
///        WatchdogEvent: scene-create  WatchdogVisibility: Background ...>
///
/// Each variant blocks the main thread during a different transition, which is
/// what sets `WatchdogEvent` and makes them distinct issue groups:
///
/// | Variant        | WatchdogEvent  | Budget | Blocks during        |
/// |----------------|----------------|--------|----------------------|
/// | `.sceneCreate` | `scene-create` | ~10s   | launch → first scene |
/// | `.sceneUpdate` | `scene-update` | ~10s   | foreground resume    |
/// | `.processExit` | `process-exit` | 5s     | termination (SIGTERM)|
///
/// Budgets vary in practice because the number reported is the *remaining*
/// allowance, not a fixed constant.
///
/// None of these can be self-inflicted the way a trap can: the app cannot launch,
/// resume, or terminate itself on demand. So a variant is *armed* here and fires
/// on the next matching transition, which `scripts/watchdog.sh` drives (relaunch,
/// background-then-foreground, or SIGTERM).
enum WatchdogHang: String, CaseIterable {
    case sceneCreate = "scene_create"
    case sceneUpdate = "scene_update"
    case processExit = "process_exit"

    /// How long to block. Only needs to exceed the OS budget — the process is
    /// killed partway through, so this is an upper bound, not a wait.
    var blockDuration: TimeInterval {
        switch self {
        case .sceneCreate, .sceneUpdate: return 30
        case .processExit: return 15
        }
    }
}

enum WatchdogHangs {

    /// Arms `hang` to fire on the next matching lifecycle transition.
    static func arm(_ hang: WatchdogHang) {
        Prefs.crashLoop.set(Prefs.keyPendingWatchdog, hang.rawValue)
        Prefs.crashLoop.flush()
        DemoStateFile.publish()
        ScreenLogger.logWarning("watchdog_hang_armed", [
            "watchdog_event": hang.rawValue,
            "hint": "fires on the next matching lifecycle transition",
        ])
    }

    static var armed: WatchdogHang? {
        guard let raw = Prefs.crashLoop.string(Prefs.keyPendingWatchdog) else { return nil }
        return WatchdogHang(rawValue: raw)
    }

    /// Blocks the main thread if `hang` is the armed variant, producing the
    /// termination. Call from the transition each variant targets.
    static func blockIfArmed(for hang: WatchdogHang) {
        guard armed == hang else { return }

        // Disarm *before* blocking, not after. The OS kills us mid-sleep, so any
        // code after the block never runs — leaving the flag set would re-arm on
        // every subsequent launch and wedge the app in a permanent hang loop with
        // no way in to switch it off.
        disarm()

        ScreenLogger.logWarning("about_to_hang: watchdog_\(hang.rawValue)", [
            "watchdog_event": hang.rawValue,
            "block_seconds": String(Int(hang.blockDuration)),
        ])

        Thread.sleep(forTimeInterval: hang.blockDuration)
    }

    static func disarm() {
        Prefs.crashLoop.remove(Prefs.keyPendingWatchdog)
        Prefs.crashLoop.flush()
        DemoStateFile.publish()
    }

    /// Installs a SIGTERM handler that blocks when `.processExit` is armed.
    ///
    /// `devicectl device process terminate` sends SIGTERM by default, which is a
    /// *graceful* request: the app then has 5 seconds to exit before RunningBoard
    /// escalates to `0x8BADF00D` with `WatchdogEvent: process-exit`. Blocking the
    /// main thread here is what overruns that budget.
    ///
    /// A DispatchSource rather than `signal(2)`: the handler runs on the main
    /// queue as ordinary Swift, instead of in async-signal-safe context where
    /// almost nothing — including the logger — is legal to call.
    static func installTerminationHandler() {
        // SIGTERM must be ignored at the POSIX level or the default disposition
        // kills the process outright and the DispatchSource never runs.
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            guard armed == .processExit else {
                // Not our demo — honour the termination request as normal.
                exit(0)
            }
            blockIfArmed(for: .processExit)
        }
        source.resume()
        terminationSource = source
    }

    /// Held for the process lifetime; a cancelled DispatchSource stops firing.
    private static var terminationSource: DispatchSourceSignal?
}
