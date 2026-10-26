package ai.bitdrift.shop

import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.Span as SdkSpan
import io.bitdrift.capture.events.span.SpanResult
import java.util.UUID
import kotlin.time.Duration

/**
 * A started span. Wraps the SDK span so its start and end are also written to the
 * [Recorder] when record mode is on. Exposes the same `id` / `end` the app uses.
 */
class Span internal constructor(
    private val sdk: SdkSpan?,
    val name: String,
    val localId: UUID,
    internal val parent: UUID? = null,
    internal val startFields: Map<String, String>? = null,
) {
    val id: UUID get() = sdk?.id ?: localId

    fun end(result: SpanResult, fields: Map<String, String>? = null, endTimeMs: Long? = null) {
        sdk?.end(result, fields, endTimeMs)
        RecordingLogger.openSpans.remove(localId)
        Recorder.write(
            "span_end",
            "id" to localId.toString(),
            "name" to name,
            "result" to result.toString().lowercase(),
            fields = fields,
        )
    }
}

/**
 * Drop-in for the SDK's `Logger` that the app code calls: forwards everything to the
 * SDK unchanged and, in record mode, writes app-emitted logs, spans and screen views
 * to the [Recorder]. Only the members the app uses are exposed.
 */
@OptIn(ExperimentalBitdriftApi::class)
object RecordingLogger {
    /** Spans started but not yet ended, so record mode can carry them into a recording that begins mid-run. */
    internal val openSpans = java.util.concurrent.ConcurrentHashMap<UUID, Span>()

    /** Called by [Recorder.start]: write a (carried) start for every span already open. */
    internal fun carryOpenSpans() {
        for (span in openSpans.values) {
            Recorder.write(
                "span_start",
                "id" to span.localId.toString(),
                "name" to span.name,
                "parent" to span.parent?.toString(),
                "carried" to true,
                fields = span.startFields,
            )
        }
    }

    val sdkVersion: String get() = Logger.sdkVersion

    fun addField(key: String, value: String) = Logger.addField(key, value)
    fun removeField(key: String) = Logger.removeField(key)
    fun setEntityId(entityId: String) = Logger.setEntityId(entityId)
    fun startNewSession() = Logger.startNewSession()
    fun setFeatureFlagExposure(name: String, variant: String) = Logger.setFeatureFlagExposure(name, variant)
    fun logAppLaunchTTI(duration: Duration) = Logger.logAppLaunchTTI(duration)
    fun createTemporaryDeviceCode(completion: (io.bitdrift.capture.CaptureResult<String>) -> Unit) =
        Logger.createTemporaryDeviceCode(completion)

    fun logScreenView(screenName: String) {
        Recorder.write("screen", "name" to screenName)
        Logger.logScreenView(screenName)
    }

    fun logInfo(fields: Map<String, String>? = null, throwable: Throwable? = null, message: () -> String) {
        val m = message()
        record("info", m, fields)
        Logger.logInfo(fields, throwable) { m }
    }

    fun logWarning(fields: Map<String, String>? = null, throwable: Throwable? = null, message: () -> String) {
        val m = message()
        record("warning", m, fields)
        Logger.logWarning(fields, throwable) { m }
    }

    fun logError(fields: Map<String, String>? = null, throwable: Throwable? = null, message: () -> String) {
        val m = message()
        record("error", m, fields)
        Logger.logError(fields, throwable) { m }
    }

    fun startSpan(
        name: String,
        level: LogLevel,
        fields: Map<String, String>? = null,
        startTimeMs: Long? = null,
        parentSpanId: UUID? = null,
    ): Span? {
        val sdk = Logger.startSpan(name, level, fields, startTimeMs, parentSpanId)
        // The SDK returns null before Capture has started; record mode still wants the span.
        val span = Span(sdk, name, sdk?.id ?: UUID.randomUUID(), parentSpanId, fields)
        openSpans[span.localId] = span
        Recorder.write(
            "span_start",
            "id" to span.localId.toString(),
            "name" to name,
            "parent" to parentSpanId?.toString(),
            fields = fields,
        )
        return span
    }

    private fun record(level: String, message: String, fields: Map<String, String>?) {
        Recorder.write("log", "level" to level, "message" to message, fields = fields)
    }
}
