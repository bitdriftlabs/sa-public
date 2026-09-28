import SwiftUI

/// Wraps `NavigationPath` with the same three navigation primitives the Android app used from
/// `NavController`: `navigate(to:)` (push), `popBackStack()` (pop one), and `popToWelcome()`
/// (`popUpTo(Welcome) { inclusive = true }` — reset to the root).
@MainActor
final class Router: ObservableObject {
    @Published var path = NavigationPath()

    func navigate(to screen: Screen) {
        self.path.append(screen)
    }

    func popBackStack() {
        guard !self.path.isEmpty else { return }
        self.path.removeLast()
    }

    func popToWelcome() {
        self.path = NavigationPath()
    }
}
