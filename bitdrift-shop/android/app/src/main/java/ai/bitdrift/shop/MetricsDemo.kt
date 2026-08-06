package ai.bitdrift.shop

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.bitdrift.capture.Capture.Logger
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random

/**
 * Ported from misc-demos/metricdemo: five waveform metrics (sine/square/sawtooth/triangle/dc)
 * plus a per-tick counter, logged once a second in a single `metric_values` event. Useful for
 * validating bitdrift's dashboard aggregation against CloudWatch or another metrics backend
 * side by side -- see metric-demo.md for the workflow and CloudWatch export that read this data.
 *
 * Also carries the "grouping of metrics" demo: `metric_work_latency_ms` simulates a release
 * history across five versions, each with a visibly different latency distribution. The tick loop
 * auto-rotates to a random version every [VERSION_ROTATION_SECONDS] seconds (via `Logger.addField()`
 * -- exactly like `app_variant`/`ff_*` elsewhere in this app) so a grouped chart fills out with all
 * five series on its own, no manual control needed. In a real app this dimension is just the SDK's
 * built-in `app_version` field -- no custom field needed; it's faked here only so a multi-version
 * grouped chart can be demoed from one build in one session.
 *
 * Session handling: a workflow only evaluates sessions that started *after* it went live --
 * an already-open session never retroactively shows up in a newly created/redeployed workflow's
 * charts, even while it's actively emitting matching events (confirmed live: 1000+ metric_values
 * events sitting in a session's raw timeline with an empty workflow chart to show for it). Rather
 * than requiring a manual kill-and-relaunch after every workflow change, [start] and the tick loop
 * call `Logger.startNewSession()` immediately and then every [SESSION_ROTATION_SECONDS] seconds
 * while running, so there's always a recent session boundary for whatever workflow is currently
 * deployed to pick up. This rotates the *app-wide* session, not just metrics telemetry -- avoid
 * running Metrics at the same time as a shopping-journey demo you need to read as one continuous
 * session (SimulationManager already rotates sessions per journey anyway, so this is consistent
 * with how session boundaries already work elsewhere in this app).
 */
enum class SimAppVersion(val label: String, val meanLatencyMs: Float, val jitterMs: Float) {
    BASELINE("4.0.0", 120f, 20f),
    REGRESSED("4.1.0", 340f, 40f),
    FIXED("4.2.0", 140f, 20f),
    MINOR_REGRESSION("4.3.0", 220f, 30f),
    OPTIMIZED("4.4.0", 90f, 15f),
}

class MetricsDemoManager : ViewModel() {

    var isRunning by mutableStateOf(false)
        private set

    var simVersion by mutableStateOf(SimAppVersion.BASELINE)
        private set

    private var tickJob: Job? = null
    private var elapsedSeconds = 0f

    // Shuffled bag rather than a plain random pick each rotation -- guarantees every version
    // gets roughly even representation over time instead of a short demo run happening to
    // over-sample one version and never drawing another.
    private var versionBag: MutableList<SimAppVersion> = mutableListOf()

    private fun nextRandomVersion(): SimAppVersion {
        if (versionBag.isEmpty()) {
            versionBag = SimAppVersion.entries.shuffled().toMutableList()
        }
        return versionBag.removeAt(0)
    }

    /** Starts or stops the once-a-second metric_values tick. Bound to the "Metrics" button. */
    fun toggle() {
        if (isRunning) stop() else start()
    }

    private fun start() {
        isRunning = true
        Logger.addField("sim_app_version", simVersion.label)
        // Fresh session boundary right away -- see the class doc for why. Whatever workflow is
        // deployed at this moment will see everything from here on, without a relaunch.
        Logger.startNewSession()
        tickJob = viewModelScope.launch {
            while (true) {
                delay(1000L)
                elapsedSeconds += 1f
                if (elapsedSeconds.toInt() % SESSION_ROTATION_SECONDS == 0) {
                    Logger.startNewSession()
                }
                if (elapsedSeconds.toInt() % VERSION_ROTATION_SECONDS == 0) {
                    simVersion = nextRandomVersion()
                    Logger.addField("sim_app_version", simVersion.label)
                }
                logTick(elapsedSeconds)
            }
        }
    }

    private fun stop() {
        isRunning = false
        tickJob?.cancel()
        tickJob = null
    }

    private fun logTick(t: Float) {
        // Periods are 5 minutes (300s) so each ~1-minute bitdrift aggregation window
        // captures ~1/5th of a cycle -- 3 full cycles visible in a 15-minute view.
        val period = 300f
        val half = period / 2f

        val sine = 5f + 5f * sin(2.0 * PI * t / period).toFloat()
        val square = if ((t % period) < half) 0f else 5f
        val sawtooth = (t % half) / half * 5f
        val phase = t % period
        val triangle = if (phase < half) phase / half * 10f else (period - phase) / half * 10f
        val dc = 5f
        // Counter: always 1 per tick -- a sum aggregation should yield exactly
        // (events_per_window) in both bitdrift and CloudWatch, making any drop or
        // double-count immediately visible.
        val counter = 1f

        // work_latency_ms: the metric the grouping demo is built around. Its mean/jitter
        // depend on the currently simulated version (auto-rotated across all five -- see
        // VERSION_ROTATION_SECONDS), so grouping this by sim_app_version in a workflow chart
        // produces five distinct distributions instead of one.
        val version = simVersion
        val jitter = (Random.nextFloat() * 2f - 1f) * version.jitterMs
        val latency = (version.meanLatencyMs + jitter).coerceAtLeast(1f)

        Logger.logInfo(
            mapOf(
                "metric_sine" to "%.4f".format(sine),
                "metric_square" to "%.4f".format(square),
                "metric_sawtooth" to "%.4f".format(sawtooth),
                "metric_triangle" to "%.4f".format(triangle),
                "metric_dc" to "%.4f".format(dc),
                "metric_counter" to "%.4f".format(counter),
                "metric_work_latency_ms" to "%.2f".format(latency),
            )
        ) { "metric_values" }
    }

    override fun onCleared() {
        super.onCleared()
        tickJob?.cancel()
    }

    companion object {
        /** How often to roll the session boundary while the tick loop is running. */
        private const val SESSION_ROTATION_SECONDS = 60

        /** How often to auto-rotate to a random simulated version while the tick loop is running. */
        private const val VERSION_ROTATION_SECONDS = 30
    }
}
