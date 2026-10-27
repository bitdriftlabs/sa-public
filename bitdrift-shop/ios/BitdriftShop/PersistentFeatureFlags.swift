import Capture
import Foundation

/// Exactly three install-persistent feature flags (hard cap -- do not add a fourth), the same
/// three as the Android app. Each flag is assigned once, on first launch, then read back from
/// UserDefaults on every later launch, so a device keeps the same values across restarts,
/// crashes and new sessions (unlike the per-run `SimVariant` flags).
///
/// bitdrift SDK: `apply()` records every flag as both a feature flag exposure (usable as a
/// workflow/chart dimension) and an `ff_*` global field (visible on every log in the session).
enum PersistentFeatureFlags {
    private struct Flag { let key: String; let values: [String] }

    private static let flags = [
        Flag(key: "express_checkout", values: ["enabled", "disabled"]),
        Flag(key: "product_card_layout", values: ["grid", "list"]),
        Flag(key: "free_shipping_banner", values: ["control", "treatment"]),
    ]

    private static let store = Prefs(suite: "persistent_flags")

    static var flagKeys: [String] { flags.map(\.key) }

    /// Call once from `CaptureBridge.start()` after `Logger.start()`.
    static func apply() {
        for flag in flags {
            let value = store.string(flag.key).flatMap { flag.values.contains($0) ? $0 : nil }
                ?? flag.values.randomElement()!
            store.set(flag.key, value)
            record(flag.key, value)
        }
        store.flush()
    }

    /// Flips one flag to its other value (the `flip_flag` command), persisting it and re-recording
    /// the exposure and `ff_*` field so the change is visible in the running session.
    /// Returns (from, to), or nil when `key` is not one of the three flags.
    static func flip(_ key: String) -> (from: String, to: String)? {
        guard let flag = flags.first(where: { $0.key == key }) else { return nil }
        let from = store.string(flag.key).flatMap { flag.values.contains($0) ? $0 : nil } ?? flag.values[0]
        let to = flag.values.first { $0 != from }!
        store.set(flag.key, to)
        store.flush()
        record(flag.key, to)
        return (from, to)
    }

    private static func record(_ key: String, _ value: String) {
        Logger.setFeatureFlagExposure(withName: key, variant: value)
        Logger.addField(withKey: "ff_\(key)", value: value)
    }
}
