import Foundation

/// Mirrors the demo's fault-injection state to a plain JSON file inside the app
/// container, for `scripts/watchdog.sh` and `scripts/check-demo-state.sh` to read.
///
/// Why not just have the scripts read the app's `UserDefaults` plist? Because on
/// the Simulator that file is owned by `cfprefsd`, which caches the domain in
/// memory and flushes on its own schedule — a host-side read can return values
/// the app abandoned minutes ago, and a host-side write is silently overwritten
/// the next time the daemon flushes. The watchdog decides *when to relaunch* and
/// *when to background the app* from this state, so reading something stale
/// breaks the crash loop outright.
///
/// Written with `FileManager`/`Data`, atomically, so what lands on disk is always
/// exactly what the app last published. Read-only as far as the scripts are
/// concerned — arming still happens in the app UI or via launch arguments.
enum DemoStateFile {

    /// `<container>/Library/Application Support/bitdrift-demo-state.json`
    static var url: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("bitdrift-demo-state.json")
    }

    /// Snapshots the current flags to disk. Cheap enough to call on every toggle.
    static func publish(awaitingBackground: Bool? = nil) {
        guard let url else { return }

        let state: [String: Any] = [
            "crash_loop": Prefs.crashLoop.bool(Prefs.keyActive),
            "fast_crash": Prefs.crashLoop.bool(Prefs.keyFastMode),
            "oom_only": Prefs.crashLoop.bool(Prefs.keyOomOnly),
            "resume_infinite_with_crash": Prefs.crashLoop.bool(Prefs.keyResumeInfiniteWithCrash),
            "app_hang": Prefs.appHang.bool(Prefs.keyActive),
            "app_hang_restart_pending": Prefs.appHang.bool(Prefs.keyRestartPending),
            "force_quit": Prefs.forceQuit.bool(Prefs.keyActive),
            "force_quit_restart_pending": Prefs.forceQuit.bool(Prefs.keyRestartPending),
            "auto_infinite": Prefs.autoInfinite.bool(Prefs.keyActive),
            "recommendations_v2": Prefs.recommendations.bool(Prefs.keyActive),
            "next_combo_index": Prefs.crashLoop.int(Prefs.keyNextComboIndex),
            "restart_delay_ms": Prefs.crashLoop.int("restart_delay_ms", 2000),
            "awaiting_background": awaitingBackground
                ?? Prefs.crashLoop.bool(Prefs.keyAwaitingBackground),
            // Which lifecycle transition the watchdog script must drive to fire an
            // armed watchdog hang: "" (none), scene_create, scene_update, or
            // process_exit. The app cannot launch, resume or terminate itself.
            "pending_watchdog": Prefs.crashLoop.string(Prefs.keyPendingWatchdog) ?? "",
        ]

        // Demo-only bookkeeping — exists purely for scripts/watchdog.sh and
        // check-demo-state.sh to read.
        guard let data = try? JSONSerialization.data(
            withJSONObject: state, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
