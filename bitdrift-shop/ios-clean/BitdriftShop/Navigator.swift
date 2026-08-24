import Foundation

/// Drives the `NavigationStack` path and is the single place screen views are
/// logged from.
///
/// Centralising the `logScreenView` call here — rather than in each screen's
/// `onAppear` — is deliberate: it fires identically for user taps and for
/// simulator-driven navigation (`SimulationManager.nav`), and it does not depend
/// on SwiftUI's view lifecycle timing. This mirrors the Android app's
/// `NavController.OnDestinationChangedListener`.
@MainActor
final class Navigator: ObservableObject {

    /// Welcome is the stack root and never appears in `path`.
    @Published var path: [Screen] = []

    /// The screen currently on top, Welcome when the stack is empty.
    var current: Screen { path.last ?? .welcome }

    /// Logs the initial Welcome view. Called once the app is on screen, since
    /// the root is never pushed through `navigate`.
    func logInitialScreen() {
        ScreenLogger.logScreenView(Screen.welcome.screenName)
    }

    func navigate(to screen: Screen) {
        path.append(screen)
        ScreenLogger.logScreenView(screen.screenName)
    }

    func popBackStack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        ScreenLogger.logScreenView(current.screenName)
    }

    /// Clears the stack back to Welcome — the equivalent of Android's
    /// `navigate(Welcome) { popUpTo(Welcome) { inclusive = true } }`.
    func popToWelcome() {
        path.removeAll()
        ScreenLogger.logScreenView(Screen.welcome.screenName)
    }
}
