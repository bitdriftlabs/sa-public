import Foundation

/// Namespaced `UserDefaults` wrapper standing in for Android's
/// `SharedPreferences`. Each `Prefs` instance prefixes its keys with a suite
/// name so the crash-loop, hang, force-quit and user-session stores stay as
/// separate as they are on Android.
///
/// `flush()` is the counterpart of Android's `commit()`: the crash demos write
/// state moments before deliberately killing the process, and an unflushed
/// write can lose that race and silently revert a toggle on the next cold start.
struct Prefs {
    let suite: String

    private let defaults = UserDefaults.standard

    private func k(_ key: String) -> String { "\(suite).\(key)" }

    /// Presence check first so an unset key can fall back to something other than
    /// `false`, then `UserDefaults`' own accessor to read it.
    ///
    /// Reading via `bool(forKey:)` rather than casting `object(forKey:) as? Bool`
    /// matters: the cast only accepts a real boolean, so a value supplied as a
    /// launch argument (`-crash_loop.active 1`, which lands in NSArgumentDomain as
    /// a string) or written by `defaults write … -int 1` would be silently ignored
    /// and read back as `false`. That makes arming a demo from the command line —
    /// see `scripts/` and the README — work as written.
    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        guard defaults.object(forKey: k(key)) != nil else { return fallback }
        return defaults.bool(forKey: k(key))
    }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        guard defaults.object(forKey: k(key)) != nil else { return fallback }
        return defaults.integer(forKey: k(key))
    }

    func string(_ key: String) -> String? {
        defaults.string(forKey: k(key))
    }

    func set(_ key: String, _ value: Bool) { defaults.set(value, forKey: k(key)) }
    func set(_ key: String, _ value: Int) { defaults.set(value, forKey: k(key)) }
    func set(_ key: String, _ value: String) { defaults.set(value, forKey: k(key)) }
    func remove(_ key: String) { defaults.removeObject(forKey: k(key)) }

    /// Force the pending writes to disk before a deliberate crash.
    func flush() { defaults.synchronize() }

    // MARK: - Stores

    /// Crash-loop state. Mirrors Android's `crash_loop` SharedPreferences file.
    static let crashLoop = Prefs(suite: "crash_loop")
    /// App-hang (Android ANR) state.
    static let appHang = Prefs(suite: "app_hang")
    /// Force-quit state.
    static let forceQuit = Prefs(suite: "force_quit")
    /// "Auto ∞ sim" startup toggle.
    static let autoInfinite = Prefs(suite: "auto_infinite")
    /// Signed-in user, read back by `UserIDFieldProvider` on every log.
    static let userSession = Prefs(suite: "user_session")

    // MARK: - Keys (shared across stores, as on Android)

    static let keyActive = "active"
    static let keyFastMode = "fast_mode"
    static let keyOomOnly = "oom_only"
    static let keyNextComboIndex = "next_combo_index"
    static let keyRestartPending = "restart_pending"
    static let keyResumeInfinite = "resume_infinite"
    static let keyResumeInfiniteWithCrash = "resume_infinite_with_crash"
    static let keyRestartVariant = "restart_variant"
    static let keyUserID = "user_id"
    /// Set while a background-half crash is armed; polled by `scripts/watchdog.sh`.
    static let keyAwaitingBackground = "awaiting_background"

    /// Clears every demo-fault flag. Backs `scripts/check-demo-state.sh --reset`
    /// and the Welcome screen's "Stop crash loop" button.
    static func resetFaultFlags() {
        for store in [crashLoop, appHang, forceQuit, autoInfinite] {
            for key in [keyActive, keyFastMode, keyOomOnly, keyRestartPending,
                        keyResumeInfinite, keyResumeInfiniteWithCrash] {
                store.remove(key)
            }
            store.remove(keyRestartVariant)
        }
        crashLoop.flush()
    }
}
