import SwiftUI
import Shared
import Combine

/// Bridges the shared SimulationEngine to SwiftUI via ObservableObject.
class SimulationState: ObservableObject {
    @Published var isSimulating = false
    @Published var currentRun = 0
    @Published var totalRuns = 0
    @Published var navigationRoute: String? = nil

    private let engine = SimulationEngine()
    private var timer: Timer?

    var isInfiniteMode: Bool { engine.isInfiniteMode }

    func simulate(runs: Int32) {
        let navigator = IOSNavigator(state: self)
        engine.simulate(
            runs: runs,
            navigator: navigator,
            scope: KotlinCoroutineScopeKt.createMainScope()
        )
        startPolling()
    }

    func infiniteSimulate() {
        let navigator = IOSNavigator(state: self)
        engine.infiniteSimulate(
            navigator: navigator,
            scope: KotlinCoroutineScopeKt.createMainScope()
        )
        startPolling()
    }

    func cancel() {
        engine.cancel()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isSimulating = self.engine.isSimulating.value as? Bool ?? false
                self.currentRun = (self.engine.currentRun.value as? NSNumber)?.intValue ?? 0
                self.totalRuns = (self.engine.totalRuns.value as? NSNumber)?.intValue ?? 0
                if !self.isSimulating {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }
}

/// Navigator implementation for iOS that publishes route changes.
class IOSNavigator: Shared.Navigator {
    private weak var state: SimulationState?

    init(state: SimulationState) {
        self.state = state
    }

    func navigate(route: String) {
        DispatchQueue.main.async { [weak self] in
            self?.state?.navigationRoute = route
        }
    }

    func navigateAndClear(route: String) {
        DispatchQueue.main.async { [weak self] in
            self?.state?.navigationRoute = "welcome_clear"
        }
    }
}
