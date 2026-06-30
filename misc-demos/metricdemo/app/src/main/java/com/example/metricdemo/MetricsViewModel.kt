package com.example.metricdemo

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.bitdrift.capture.Capture.Logger as BitdriftLogger
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

data class MetricData(
    val name: String,
    val fieldKey: String,
    val currentValue: Float,
    val history: List<Float>
)

class MetricsViewModel : ViewModel() {

    private val historySize = 300

    private val _metrics = MutableStateFlow(initialMetrics())
    val metrics: StateFlow<List<MetricData>> = _metrics

    private var elapsedSeconds = 0f

    init {
        viewModelScope.launch {
            while (true) {
                delay(1000L)
                elapsedSeconds += 1f
                val newValues = computeValues(elapsedSeconds)

                // Log all metric values to bitdrift in a single event
                val fields = newValues.associate { it.fieldKey to "%.4f".format(it.currentValue) }
                BitdriftLogger.logInfo(fields) { "metric_values" }

                _metrics.value = _metrics.value.mapIndexed { index, metric ->
                    val newVal = newValues[index].currentValue
                    metric.copy(
                        currentValue = newVal,
                        history = (metric.history + newVal).takeLast(historySize)
                    )
                }
            }
        }
    }

    private fun computeValues(t: Float): List<MetricData> {
        // Periods are 5 minutes (300s) so each ~1-minute bitdrift aggregation window
        // captures ~1/5th of a cycle — 3 full cycles visible in a 15-minute view.
        val period   = 300f
        val half     = period / 2f

        val sine     = 5f + 5f * sin(2.0 * PI * t / period).toFloat()
        val square   = if ((t % period) < half) 0f else 5f
        val sawtooth = (t % half) / half * 5f
        val phase    = t % period
        val triangle = if (phase < half) phase / half * 10f else (period - phase) / half * 10f
        val dc       = 5f
        // Counter: always 1 per tick. Sum aggregation should yield exactly
        // (events_per_window) in both bitdrift and CloudWatch, making any
        // drop or double-count immediately visible.
        val counter  = 1f

        val rawValues = listOf(sine, square, sawtooth, triangle, dc, counter)
        return _metrics.value.mapIndexed { index, metric ->
            metric.copy(currentValue = rawValues[index])
        }
    }

    private fun initialMetrics(): List<MetricData> = listOf(
        MetricData("sine",     "metric_sine",     5f, emptyList()),
        MetricData("square",   "metric_square",   0f, emptyList()),
        MetricData("sawtooth", "metric_sawtooth", 0f, emptyList()),
        MetricData("triangle", "metric_triangle", 0f, emptyList()),
        MetricData("dc",       "metric_dc",       5f, emptyList()),
        MetricData("counter",  "metric_counter",  0f, emptyList()),
    )
}
