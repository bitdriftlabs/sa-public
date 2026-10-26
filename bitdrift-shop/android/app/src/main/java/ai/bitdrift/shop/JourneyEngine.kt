package ai.bitdrift.shop

import org.json.JSONArray
import org.json.JSONObject

/**
 * The platform half of the shared journey: everything the interpreter needs from the
 * app. [SimulationManager] implements it against the SDK, the nav graph and [ApiClient];
 * the unit tests implement it as a trace recorder (see tools/journey/golden.json).
 */
interface JourneyAdapter {
    fun isCancelled(): Boolean
    fun startNewSession()
    fun applyExposures(persona: String)
    fun setEntity(entity: String)
    suspend fun delay(ms: Long)
    suspend fun navigate(screen: String, args: Map<String, String>)
    /** The endpoint's JSON response, or null if the call failed. */
    suspend fun callApi(endpoint: String, args: Map<String, String>): JSONObject?
    fun log(level: String, event: String, fields: Map<String, String>)
    /** Returns a handle passed back to [endSpan] (and as a child's `parent`), or null. */
    fun startSpan(name: String, parent: Any?, fields: Map<String, String>): Any?
    fun endSpan(handle: Any, result: String, fields: Map<String, String>)
    fun addField(key: String, value: String)
    /** Persist the restart intent and perform the fault (may never return). */
    fun injectFault(id: String)
    /** Fire the next crash-loop crash (pick, log about_to_crash, schedule restart, dispatch). */
    fun fireCrash()
}

/** mulberry32, bit-identical to tools/journey/engine.py and the other apps' engines. */
class JourneyRng(seed: Int) {
    private var s = seed

    fun next(): Double {
        s += 0x6D2B79F5
        var t = s
        t = (t xor (t ushr 15)) * (t or 1)
        t = (t + (t xor (t ushr 7)) * (t or 61)) xor t
        return ((t xor (t ushr 14)).toLong() and 0xFFFFFFFFL).toDouble() / 4294967296.0
    }

    companion object {
        /** journey_seed = (sim_seed * 1000003 + run) mod 2^32, 0 <= sim_seed < 2^31. */
        fun journeySeed(simSeed: Long, run: Int): Int = ((simSeed * 1000003L + run) and 0xFFFFFFFFL).toInt()
    }
}

/**
 * Interprets spec/journey.yaml (compiled into [ai.bitdrift.shop.generated.SpecJourney]).
 * A line-for-line port of tools/journey/engine.py: change the journey there and in the
 * YAML, never here. One engine per simulator, because the fault counters persist across
 * journeys.
 */
class JourneyEngine(bundleJson: String, private val adapter: JourneyAdapter) {
    private val bundle = JSONObject(bundleJson)
    private val eligible = mutableMapOf<String, Int>()

    private var persona = ""
    private var toggles: Set<String> = emptySet()
    private var infinite = false
    private var rng = JourneyRng(0)
    private val vars = mutableMapOf<String, Any>()
    private val spans = mutableMapOf<String, Any>()
    private var crashFired = false

    private class Stop(val outcome: String) : Exception(null, null, false, false)

    /** Runs one journey; returns its outcome (completed, cart_abandoned, fault, crash, cancelled, ...). */
    suspend fun run(persona: String, run: Int, simSeed: Long, toggles: Set<String>, infinite: Boolean): String {
        this.persona = persona
        this.toggles = toggles
        this.infinite = infinite
        rng = JourneyRng(JourneyRng.journeySeed(simSeed, run))
        vars.clear()
        val pv = bundle.getJSONObject("personas").getJSONObject(persona).getJSONObject("vars")
        for (k in pv.keys()) vars[k] = pv.getString(k)
        vars["run"] = run.toString()
        vars["sim_seed"] = simSeed.toString()
        vars["persona"] = persona
        spans.clear()
        crashFired = false
        return try {
            block(bundle.getJSONArray("journey"))
            "completed"
        } catch (s: Stop) {
            s.outcome
        }
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    private fun t(s: String): String = TEMPLATE.replace(s) { m ->
        when (val v = vars[m.groupValues[1]]) {
            is List<*> -> v.size.toString()
            null -> ""
            else -> v.toString()
        }
    }

    private fun tm(o: JSONObject): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (k in o.keys()) out[k] = t(o.getString(k))
        return out
    }

    @Suppress("UNCHECKED_CAST")
    private fun lst(name: String): MutableList<String> {
        val v = vars[name]
        if (v is MutableList<*>) return v as MutableList<String>
        val fresh = mutableListOf<String>()
        vars[name] = fresh
        return fresh
    }

    private fun str(name: String): String = (vars[name] as? String) ?: ""

    private fun strings(a: JSONArray): List<String> = (0 until a.length()).map { a.getString(it) }

    private fun p(chance: JSONObject): Double {
        var table = chance.getJSONObject("default")
        if (chance.has("by")) {
            val cases = chance.getJSONObject("cases")
            val key = str(chance.getString("by"))
            if (cases.has(key)) table = cases.getJSONObject(key)
        }
        return table.getDouble(persona)
    }

    /** Draws for `chance` first (always), then checks every other condition. */
    private fun condOk(op: JSONObject): Boolean {
        var ok = true
        if (op.has("chance")) ok = rng.next() < p(op.getJSONObject("chance"))
        if (op.has("toggle") && op.getString("toggle") !in toggles) ok = false
        if (op.has("not_toggle") && op.getString("not_toggle") in toggles) ok = false
        if (op.has("eq")) {
            val eq = op.getJSONArray("eq")
            if (str(eq.getString(0)) != eq.getString(1)) ok = false
        }
        if (op.has("min_len")) {
            val ml = op.getJSONArray("min_len")
            if (lst(ml.getString(0)).size < ml.getInt(1)) ok = false
        }
        return ok
    }

    // ── interpreter ──────────────────────────────────────────────────────────

    private suspend fun block(ops: JSONArray) {
        for (i in 0 until ops.length()) {
            if (adapter.isCancelled()) throw Stop("cancelled")
            step(ops.getJSONObject(i))
        }
    }

    private suspend fun step(op: JSONObject) {
        when (op.getString("op")) {
            "new_session" -> adapter.startNewSession()
            "exposures" -> adapter.applyExposures(persona)
            "entity" -> {
                val ents = bundle.getJSONArray("entities")
                val e = ents.getString((vars["run"].toString().toInt() - 1) % ents.length())
                vars["entity"] = e
                adapter.setEntity(e)
            }
            "wait" -> adapter.delay(op.getLong("ms"))
            "nav" -> {
                adapter.navigate(op.getString("screen"), tm(op.getJSONObject("args")))
                adapter.delay(bundle.getLong("step_delay_ms"))
            }
            "api" -> {
                val res = adapter.callApi(op.getString("endpoint"), tm(op.getJSONObject("args")))
                val save = op.getJSONArray("save")
                for (i in 0 until save.length()) {
                    val s = save.getJSONObject(i)
                    val v = res?.opt(s.getString("key"))
                    if (s.has("item")) {
                        val item = s.getString("item")
                        val items = mutableListOf<String>()
                        if (v is JSONArray) for (j in 0 until v.length()) {
                            val o = v.optJSONObject(j)
                            if (o != null && o.has(item)) items.add(o.get(item).toString())
                        }
                        vars[s.getString("var")] = items.ifEmpty { strings(s.getJSONArray("default")).toMutableList() }
                    } else {
                        vars[s.getString("var")] =
                            if (v == null || v == JSONObject.NULL || v.toString().isEmpty()) t(s.getString("default")) else v.toString()
                    }
                }
            }
            "log" -> adapter.log(op.getString("level"), op.getString("event"), tm(op.getJSONObject("fields")))
            "span_start" -> startSpan(op)
            "span_end" -> spans.remove(op.getString("span"))?.let {
                adapter.endSpan(it, op.getString("result"), tm(op.getJSONObject("fields")))
            }
            "span" -> {
                // Scoped span: success when the block finishes or the journey stops inside
                // it (fault / crash / outcome); canceled when the run is cancelled.
                startSpan(op)
                var result = "canceled"
                try {
                    block(op.getJSONArray("do"))
                    result = "success"
                } catch (s: Stop) {
                    result = if (s.outcome == "cancelled") "canceled" else "success"
                    throw s
                } finally {
                    spans.remove(op.getString("span"))?.let { adapter.endSpan(it, result, emptyMap()) }
                }
            }
            "set" -> {
                val values = op.getJSONObject("values")
                for (k in values.keys()) vars[k] = t(values.getString(k))
            }
            "pick" -> {
                var items = if (op.has("values")) strings(op.getJSONArray("values")) else lst(op.getString("from")).toList()
                if (op.has("exclude")) {
                    val ex = t(op.getString("exclude"))
                    items = items.filter { it != ex }
                }
                val r = rng.next()
                vars[op.getString("into")] = if (items.isEmpty()) "" else items[(r * items.size).toInt()]
            }
            "rand_int" -> {
                val lo = op.getInt("min")
                val hi = op.getInt("max")
                vars[op.getString("into")] = (lo + (rng.next() * (hi - lo + 1)).toInt()).toString()
            }
            "choose" -> {
                val weights = op.getJSONObject("weights").getJSONArray(persona)
                var total = 0.0
                for (i in 0 until weights.length()) total += weights.getJSONArray(i).getDouble(1)
                val x = rng.next() * total
                var pick = weights.getJSONArray(weights.length() - 1).getString(0)
                var acc = 0.0
                for (i in 0 until weights.length()) {
                    acc += weights.getJSONArray(i).getDouble(1)
                    if (x < acc) {
                        pick = weights.getJSONArray(i).getString(0)
                        break
                    }
                }
                if (!op.isNull("into")) vars[op.getString("into")] = pick
                op.getJSONObject("branches").optJSONArray(pick)?.let { block(it) }
            }
            "if" -> block(op.getJSONArray(if (condOk(op)) "then" else "else"))
            "switch" -> block(op.getJSONObject("cases").optJSONArray(str(op.getString("var"))) ?: op.getJSONArray("default"))
            "repeat" -> {
                val range = op.getJSONObject("ranges").getJSONArray(persona)
                val lo = range.getInt(0)
                val hi = range.getInt(1)
                val n = lo + (rng.next() * (hi - lo + 1)).toInt()
                repeat(n) { block(op.getJSONArray("do")) }
            }
            "for_each" -> for (item in lst(op.getString("list")).toList()) {
                vars[op.getString("as")] = item
                block(op.getJSONArray("do"))
            }
            "list_add" -> lst(op.getString("list")).add(t(op.getString("value")))
            "list_remove_random" -> {
                val items = lst(op.getString("list"))
                val r = rng.next()
                vars[op.getString("into")] = if (items.isEmpty()) "" else items.removeAt((r * items.size).toInt())
            }
            "list_clear" -> lst(op.getString("list")).clear()
            "last" -> {
                val items = lst(op.getString("list"))
                vars[op.getString("into")] = items.lastOrNull() ?: t(op.getString("default"))
            }
            "fault" -> fault(op)
            "crash_point" -> {
                val point = op.getString("point")
                if ("crash_loop" in toggles && !crashFired && (point == str("crash_point") || point == "confirmation")) {
                    crashFired = true
                    adapter.addField("crash_journey_point", point)
                    adapter.fireCrash()
                    throw Stop("crash")
                }
            }
            "stop" -> throw Stop(op.getString("outcome"))
            else -> error("unknown journey op ${op.getString("op")}")
        }
    }

    private fun startSpan(op: JSONObject) {
        val parent = if (op.isNull("parent")) null else spans[op.getString("parent")]
        val h = adapter.startSpan(op.getString("span"), parent, tm(op.getJSONObject("fields")))
        if (h != null) spans[op.getString("span")] = h
    }

    private fun fault(op: JSONObject) {
        val id = op.getString("fault")
        if (id !in toggles) return
        val n = (eligible[id] ?: 0) + 1
        eligible[id] = n
        val randomHit = rng.next() < op.getDouble("probability")
        val forced = infinite && n >= op.getInt("force_after")
        if (!randomHit && !forced) return
        eligible[id] = 0
        vars["trigger_mode"] = if (randomHit) "random" else "forced_infinite"
        adapter.log(op.getString("level"), op.getString("event"), tm(op.getJSONObject("fields")))
        adapter.injectFault(id)
        throw Stop("fault")
    }

    companion object {
        private val TEMPLATE = Regex("""\{([A-Za-z0-9_.]+)\}""")
    }
}
