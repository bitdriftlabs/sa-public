import Foundation

/// Five waveform metrics (sine/square/sawtooth/triangle/dc) plus a per-tick
/// counter, logged once a second in a single `metric_values` event. Useful for
/// validating bitdrift's dashboard aggregation against CloudWatch or another
/// metrics backend side by side — see `android/metric-demo.md` for the workflow
/// and CloudWatch export that read this data. The event and field names match
/// the Android app exactly, so both feed the same charts.
///
/// Also carries the "grouping of metrics" demo: `metric_work_latency_ms`
/// simulates a release history across five versions, each with a visibly
/// different latency distribution. The tick loop auto-rotates to a random
/// version every `versionRotationSeconds` so a grouped chart fills out with all
/// five series on its own.
enum SimAppVersion: String, CaseIterable {
    case baseline = "4.0.0"
    case regressed = "4.1.0"
    case fixed = "4.2.0"
    case minorRegression = "4.3.0"
    case optimized = "4.4.0"

    var label: String { rawValue }

    var meanLatencyMs: Double {
        switch self {
        case .baseline: return 120
        case .regressed: return 340
        case .fixed: return 140
        case .minorRegression: return 220
        case .optimized: return 90
        }
    }

    var jitterMs: Double {
        switch self {
        case .baseline: return 20
        case .regressed: return 40
        case .fixed: return 20
        case .minorRegression: return 30
        case .optimized: return 15
        }
    }
}

@MainActor
final class MetricsDemoManager: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var simVersion: SimAppVersion = .baseline

    private var tickTask: Task<Void, Never>?
    private var elapsedSeconds = 0

    /// Shuffled bag rather than an independent random pick each rotation —
    /// guarantees every version gets roughly even representation instead of a
    /// short demo run over-sampling one and never drawing another.
    private var versionBag: [SimAppVersion] = []

    private func nextRandomVersion() -> SimAppVersion {
        if versionBag.isEmpty { versionBag = SimAppVersion.allCases.shuffled() }
        return versionBag.removeFirst()
    }

    /// Starts or stops the once-a-second `metric_values` tick.
    func toggle() {
        isRunning ? stop() : start()
    }

    private func start() {
        isRunning = true

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                self.elapsedSeconds += 1
                if self.elapsedSeconds % Self.versionRotationSeconds == 0 {
                    self.simVersion = self.nextRandomVersion()
                }
                self.logTick(Double(self.elapsedSeconds))
            }
        }
    }

    private func stop() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
    }

    private func logTick(_ t: Double) {
        // Periods are 5 minutes (300s) so each ~1-minute bitdrift aggregation
        // window captures ~1/5th of a cycle — 3 full cycles visible in a
        // 15-minute view.
        let period = 300.0
        let half = period / 2

        let sine = 5 + 5 * sin(2 * .pi * t / period)
        let square = t.truncatingRemainder(dividingBy: period) < half ? 0.0 : 5.0
        let sawtooth = t.truncatingRemainder(dividingBy: half) / half * 5
        let phase = t.truncatingRemainder(dividingBy: period)
        let triangle = phase < half ? phase / half * 10 : (period - phase) / half * 10
        let dc = 5.0
        // Counter: always 1 per tick — a sum aggregation should yield exactly
        // (events_per_window) in both bitdrift and CloudWatch, making any drop or
        // double-count immediately visible.
        let counter = 1.0

        // work_latency_ms: the metric the grouping demo is built around. Its
        // mean/jitter depend on the currently simulated version (auto-rotated
        // across all five), so grouping this by `sim_app_version` in a workflow
        // chart produces five distinct distributions instead of one.
        let version = simVersion
        let jitter = Double.random(in: -1...1) * version.jitterMs
        let latency = max(version.meanLatencyMs + jitter, 1)

        ScreenLogger.logInfo("metric_values", [
            "metric_sine": String(format: "%.4f", sine),
            "metric_square": String(format: "%.4f", square),
            "metric_sawtooth": String(format: "%.4f", sawtooth),
            "metric_triangle": String(format: "%.4f", triangle),
            "metric_dc": String(format: "%.4f", dc),
            "metric_counter": String(format: "%.4f", counter),
            "metric_work_latency_ms": String(format: "%.2f", latency),
        ])
    }

    deinit {
        tickTask?.cancel()
    }

    /// How often to roll the session boundary while the tick loop is running.
    private static let sessionRotationSeconds = 60

    /// How often to auto-rotate to a random simulated version while running.
    private static let versionRotationSeconds = 30
}
