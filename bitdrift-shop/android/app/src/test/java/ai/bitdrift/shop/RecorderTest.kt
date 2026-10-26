package ai.bitdrift.shop

import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.SpanResult
import java.io.File
import java.nio.file.Files
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecorderTest {
    private val dir: File = Files.createTempDirectory("bdshop-record").toFile()

    @After fun cleanup() {
        Recorder.stop()
        dir.deleteRecursively()
    }

    private fun lines(f: File) = f.readLines().filter { it.isNotBlank() }.map { JSONObject(it) }

    @Test fun recordsLogsSpansAndScreens() {
        val file = Recorder.start(dir, "t.jsonl")
        val journey = RecordingLogger.startSpan("journey", LogLevel.INFO, mapOf("variant" to "Control"))!!
        val child = RecordingLogger.startSpan("product_discovery", LogLevel.INFO, null, null, journey.id)!!
        RecordingLogger.logInfo(mapOf("run" to "1")) { "journey_started" }
        RecordingLogger.logScreenView("Welcome")
        child.end(SpanResult.SUCCESS)
        journey.end(SpanResult.FAILURE, mapOf("reason" to "payment_failed"))

        val rows = lines(file)
        assertEquals(listOf("span_start", "span_start", "log", "screen", "span_end", "span_end"), rows.map { it.getString("kind") })
        assertEquals("journey_started", rows[2].getString("message"))
        assertEquals("1", rows[2].getJSONObject("fields").getString("run"))
        assertEquals(journey.id.toString(), rows[1].getString("parent"))
        assertEquals("failure", rows[5].getString("result"))
        assertEquals("payment_failed", rows[5].getJSONObject("fields").getString("reason"))
    }

    @Test fun carriesSpansThatWereOpenBeforeRecordingStarted() {
        val early = RecordingLogger.startSpan("foreground_session", LogLevel.INFO)!!
        val file = Recorder.start(dir, "carried.jsonl")
        early.end(SpanResult.SUCCESS)
        val rows = lines(file)
        assertEquals("span_start", rows[0].getString("kind"))
        assertTrue(rows[0].getBoolean("carried"))
        assertEquals("span_end", rows[1].getString("kind"))
    }

    @Test fun writesNothingWhenNotRecording() {
        Recorder.stop()
        RecordingLogger.logInfo { "journey_started" }
        assertFalse(Recorder.isActive)
    }

    @Test fun autorunPersonaMapsToVariant() {
        AutorunConfig.persona = "variant_a"
        assertEquals(SimVariant.VARIANT_A, AutorunConfig.variant())
        AutorunConfig.persona = "variant_b"
        assertEquals(SimVariant.VARIANT_B, AutorunConfig.variant())
        AutorunConfig.persona = "anything-else"
        assertEquals(SimVariant.CONTROL, AutorunConfig.variant())
    }
}
