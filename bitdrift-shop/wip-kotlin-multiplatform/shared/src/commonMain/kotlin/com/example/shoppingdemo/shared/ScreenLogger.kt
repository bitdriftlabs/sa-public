package ai.bitdrift.shop.shared

import kotlin.time.TimeSource

object ScreenLogger {

    fun logScreenView(screenName: String) = platformLogScreenView(screenName)
    fun logTrace(message: String, fields: Map<String, String> = emptyMap()) = platformLogTrace(message, fields)
    fun logDebug(message: String, fields: Map<String, String> = emptyMap()) = platformLogDebug(message, fields)
    fun logInfo(message: String, fields: Map<String, String> = emptyMap()) = platformLogInfo(message, fields)
    fun logWarning(message: String, fields: Map<String, String> = emptyMap()) = platformLogWarning(message, fields)
    fun logError(message: String, fields: Map<String, String> = emptyMap()) = platformLogError(message, fields)

    fun addField(key: String, value: String) = platformAddField(key, value)
    fun removeField(key: String) = platformRemoveField(key)
    fun setEntityId(entityId: String) = platformSetEntityId(entityId)
    fun setFeatureFlagExposure(name: String, variant: String) = platformSetFeatureFlagExposure(name, variant)

    // ── Spans (approximation) ─────────────────────────────────────────────────────
    // Paired start/end logs carrying _span_id, _span_type, _duration_ms match the
    // data shape bitdrift's span feature emits, so dashboard span queries work.
    private var spanCounter = 0

    fun startSpan(
        name: String,
        fields: Map<String, String> = emptyMap(),
        parentSpanId: String? = null,
    ): Span {
        spanCounter += 1
        val id = "span_${spanCounter}"
        val mark = TimeSource.Monotonic.markNow()
        logInfo(name, buildMap {
            putAll(fields)
            put("_span_id", id)
            put("_span_type", "start")
            if (parentSpanId != null) put("parent_span_id", parentSpanId)
        })
        return Span(id, mark, name, parentSpanId)
    }

    fun logSimulationStart(runs: Int) = logInfo("simulation_start", mapOf("total_runs" to runs.toString()))
    fun logSimulationEnd(runs: Int) = logInfo("simulation_end", mapOf("total_runs" to runs.toString()))
}

data class Span(
    val id: String,
    private val startMark: TimeSource.Monotonic.ValueTimeMark,
    private val name: String,
    private val parentSpanId: String? = null,
) {
    fun end(result: String = "success", endFields: Map<String, String> = emptyMap()) {
        val durationMs = startMark.elapsedNow().inWholeMilliseconds
        ScreenLogger.logInfo(name, buildMap {
            putAll(endFields)
            put("_span_id", id)
            put("_span_type", "end")
            put("_result", result)
            put("_duration_ms", durationMs.toString())
            if (parentSpanId != null) put("parent_span_id", parentSpanId)
        })
    }
}

internal expect fun platformLogScreenView(screenName: String)
internal expect fun platformLogTrace(message: String, fields: Map<String, String>)
internal expect fun platformLogDebug(message: String, fields: Map<String, String>)
internal expect fun platformLogInfo(message: String, fields: Map<String, String>)
internal expect fun platformLogWarning(message: String, fields: Map<String, String>)
internal expect fun platformLogError(message: String, fields: Map<String, String>)
internal expect fun platformAddField(key: String, value: String)
internal expect fun platformRemoveField(key: String)
internal expect fun platformSetEntityId(entityId: String)
internal expect fun platformSetFeatureFlagExposure(name: String, variant: String)
