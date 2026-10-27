import Capture
import Foundation

enum SessionMode: String {
    /// Default: the sim starts a new session at the start of every journey (what the workflows assume).
    case perJourney = "per_journey"
    /// One session spans several journeys and background/foreground transitions, like a real user's.
    case realistic

    init(id: String?) { self = SessionMode(rawValue: id ?? "") ?? .perJourney }
}

/// Persisted demo settings (UserDefaults suite `demo_settings`, spec/faults.yaml other_persisted).
///
/// `SessionMode` is read once at SDK start, because `SessionConfiguration` cannot change afterwards:
/// toggling it on the Advanced screen takes effect on the next launch. `activeSessionMode` is what
/// this process actually started with.
enum DemoSettings {
    private static let keySessionMode = "session_mode"
    private static let keyLoseOrders = "lose_orders"

    /// Minutes of inactivity after which `realistic` mode rotates to a new session.
    static let realisticInactivityMinutes = 30

    nonisolated(unsafe) static var activeSessionMode: SessionMode = .perJourney

    static var sessionMode: SessionMode {
        get { SessionMode(id: Prefs.demoSettings.string(keySessionMode)) }
        set { Prefs.demoSettings.set(keySessionMode, newValue.rawValue); Prefs.demoSettings.flush() }
    }

    /// Starts a new Capture session only in `per_journey` mode. In `realistic` mode the SDK's inactivity
    /// timeout owns session boundaries, so every place that would rotate a session per journey goes through here.
    static func startNewSessionForJourney() {
        if activeSessionMode == .perJourney { Logger.startNewSession() }
    }

    /// Demo chaos switch: makes order-confirmation lookups fail so the `order_lost` critical log can be shown.
    static var loseOrders: Bool {
        get { Prefs.demoSettings.bool(keyLoseOrders) }
        set { Prefs.demoSettings.set(keyLoseOrders, newValue); Prefs.demoSettings.flush() }
    }
}
