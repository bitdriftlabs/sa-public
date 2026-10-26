package ai.bitdrift.shop

import ai.bitdrift.shop.generated.SpecJourney
import java.io.File
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Replays tools/journey/golden.json (written by the Python reference engine from
 * spec/journey.yaml): for every seeded case the Kotlin engine must make exactly the same
 * adapter calls, in the same order, as tools/journey/engine.py.
 */
class JourneyEngineTest {
    private val golden = JSONObject(File("../../tools/journey/golden.json").readText())

    private class TraceAdapter(private val fixture: JSONObject) : JourneyAdapter {
        val lines = mutableListOf<String>()
        private fun f(m: Map<String, String>) = m.keys.sorted().joinToString(", ", "{", "}") { "$it=${m[it]}" }

        override fun isCancelled() = false
        override fun startNewSession() { lines += "new_session" }
        override fun applyExposures(persona: String) { lines += "exposures $persona" }
        override fun setEntity(entity: String) { lines += "entity $entity" }
        override suspend fun delay(ms: Long) { lines += "wait $ms" }
        override suspend fun navigate(screen: String, args: Map<String, String>) { lines += "nav $screen ${f(args)}" }
        override suspend fun callApi(endpoint: String, args: Map<String, String>): JSONObject? {
            lines += "api $endpoint ${f(args)}"
            val fail = fixture.optJSONArray("fail")
            if (fail != null && (0 until fail.length()).any { fail.getString(it) == endpoint }) return null
            return fixture.optJSONObject(endpoint) ?: JSONObject()
        }
        override fun log(level: String, event: String, fields: Map<String, String>) { lines += "log $level $event ${f(fields)}" }
        override fun startSpan(name: String, parent: Any?, fields: Map<String, String>): Any {
            lines += "span_start $name ${parent ?: "-"} ${f(fields)}"
            return name
        }
        override fun endSpan(handle: Any, result: String, fields: Map<String, String>) { lines += "span_end $handle $result ${f(fields)}" }
        override fun addField(key: String, value: String) { lines += "field $key=$value" }
        override fun injectFault(id: String) { lines += "fault $id" }
        override fun fireCrash() { lines += "crash" }
    }

    @Test fun rngMatchesReference() {
        // mulberry32(42) reference values (also asserted by the other apps' tests).
        val rng = JourneyRng(42)
        assertEquals(0.6011037519201636, rng.next(), 0.0)
        assertEquals(0.44829055899754167, rng.next(), 0.0)
        assertEquals(JourneyRng.journeySeed(2147483647L, 4), ((2147483647L * 1000003L + 4) and 0xFFFFFFFFL).toInt())
    }

    @Test fun replaysGoldenTraces() = runBlocking {
        val cases = golden.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val adapter = TraceAdapter(golden.getJSONObject("fixture"))
            val engine = JourneyEngine(SpecJourney.JSON, adapter)
            val toggles = c.getJSONArray("toggles").let { a -> (0 until a.length()).map { a.getString(it) }.toSet() }
            for (run in 1..c.getInt("runs")) {
                val outcome = engine.run(c.getString("persona"), run, c.getLong("sim_seed"), toggles, c.getBoolean("infinite"))
                adapter.lines += "outcome $outcome"
            }
            val want = c.getJSONArray("trace").let { a -> (0 until a.length()).map { a.getString(it) } }
            val got = adapter.lines
            val firstDiff = want.indices.firstOrNull { it >= got.size || want[it] != got[it] }
            assertEquals(
                "case ${c.getString("name")}: first difference at line ${firstDiff}: want '${firstDiff?.let { want[it] }}', " +
                    "got '${firstDiff?.let { got.getOrNull(it) }}'",
                want.size to null, got.size to firstDiff,
            )
        }
    }
}
