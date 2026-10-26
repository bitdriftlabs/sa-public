package ai.bitdrift.shop

import android.content.Context
import java.io.File
import java.io.FileWriter
import org.json.JSONObject

/**
 * Record mode for the test harness: appends every app-emitted log, span and screen
 * view to a JSONL file in the app's private storage, so `tools/conformance` can
 * validate the stream against spec/telemetry.yaml with no bitdrift account involved.
 *
 * Off unless a launch argument names a record file (see [AutorunConfig]). Line shapes:
 *   {"kind":"log","level":"info","message":"...","fields":{...}}
 *   {"kind":"span_start","id":"...","name":"...","parent":"..."|null,"fields":{...}}
 *   {"kind":"span_end","id":"...","result":"success","fields":{...}}
 *   {"kind":"screen","name":"..."}
 */
object Recorder {
    private var writer: FileWriter? = null

    val isActive: Boolean get() = writer != null

    fun start(context: Context, fileName: String): File = start(File(context.filesDir, "record"), fileName)

    @Synchronized
    fun start(dir: File, fileName: String): File {
        dir.mkdirs()
        val file = File(dir, fileName)
        writer?.close()
        writer = FileWriter(file, false)
        RecordingLogger.carryOpenSpans()
        return file
    }

    @Synchronized
    fun write(kind: String, vararg pairs: Pair<String, Any?>, fields: Map<String, String>? = null) {
        val w = writer ?: return
        val obj = JSONObject()
        obj.put("t", System.currentTimeMillis())
        obj.put("kind", kind)
        for ((k, v) in pairs) obj.put(k, v ?: JSONObject.NULL)
        if (fields != null) obj.put("fields", JSONObject(fields as Map<*, *>))
        w.write(obj.toString())
        w.write("\n")
        w.flush()
    }

    @Synchronized
    fun stop() {
        writer?.close()
        writer = null
    }
}

/**
 * Launch arguments for the automated test harness, passed as intent extras:
 *   --ei sim_runs N --el sim_seed S --es persona control|variant_a|variant_b --es record_file name.jsonl
 * `sim_runs` > 0 turns on autorun: skip the config countdown, run N journeys, log
 * `sim_autorun_complete`. Until Phase 4 the simulator is not seeded; `sim_seed` is
 * accepted and reported only.
 */
object AutorunConfig {
    var runs: Int = 0
    var seed: Long = 0
    var persona: String = "control"
    var recordFile: String? = null
    var started = false

    val active: Boolean get() = runs > 0

    fun parse(intent: android.content.Intent?) {
        val e = intent?.extras ?: return
        if (!e.containsKey("sim_runs")) return
        runs = e.getInt("sim_runs", 0)
        seed = e.getLong("sim_seed", 0L)
        persona = e.getString("persona") ?: "control"
        recordFile = e.getString("record_file")
        started = false
    }

    fun variant(): SimVariant = when (persona) {
        "variant_a" -> SimVariant.VARIANT_A
        "variant_b" -> SimVariant.VARIANT_B
        else -> SimVariant.CONTROL
    }
}
