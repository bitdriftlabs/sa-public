import Foundation

/// The platform half of the shared journey: everything the interpreter needs from the
/// app. `SimulationManager` implements it against the SDK, the navigator and `ApiClient`;
/// the host-run test (JourneyEngineTests) implements it as a trace recorder (see
/// tools/journey/golden.json).
@MainActor
protocol JourneyAdapter: AnyObject {
    func isCancelled() -> Bool
    func startNewSession()
    func applyExposures(persona: String)
    func setEntity(_ entity: String)
    func delay(ms: Int) async
    func navigate(screen: String, args: [String: String]) async
    /// The endpoint's JSON response, or nil if the call failed.
    func callApi(endpoint: String, args: [String: String]) async -> [String: Any]?
    func log(level: String, event: String, fields: [String: String])
    /// Returns a handle passed back to `endSpan` (and as a child's `parent`), or nil.
    func startSpan(name: String, parent: AnyObject?, fields: [String: String]) -> AnyObject?
    func endSpan(handle: AnyObject, result: String, fields: [String: String])
    func addField(key: String, value: String)
    /// Persist the restart intent and perform the fault (may never return).
    func injectFault(id: String)
    /// Fire the next crash-loop crash (pick, log about_to_crash, persist resume intent, dispatch).
    func fireCrash()
}

/// mulberry32, bit-identical to tools/journey/engine.py and the other apps' engines.
struct JourneyRng {
    private var s: UInt32

    init(seed: UInt32) { s = seed }

    mutating func next() -> Double {
        s = s &+ 0x6D2B79F5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }

    /// journey_seed = (sim_seed * 1000003 + run) mod 2^32, 0 <= sim_seed < 2^31.
    static func journeySeed(simSeed: Int64, run: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: simSeed &* 1000003 &+ Int64(run))
    }
}

/// Interprets spec/journey.yaml (compiled into `SpecJourney.json`). A line-for-line port
/// of tools/journey/engine.py: change the journey there and in the YAML, never here. One
/// engine per simulator, because the fault counters persist across journeys.
@MainActor
final class JourneyEngine {
    private typealias Op = [String: Any]

    private let bundle: [String: Any]
    private unowned let adapter: JourneyAdapter
    private var eligible: [String: Int] = [:]

    private var persona = ""
    private var toggles: Set<String> = []
    private var infinite = false
    private var rng = JourneyRng(seed: 0)
    private var vars: [String: Any] = [:]
    private var spans: [String: AnyObject] = [:]
    private var crashFired = false

    private struct Stop: Error { let outcome: String }

    init(bundleJson: String, adapter: JourneyAdapter) {
        // The bundle is generated at build time; failing to parse it is a build bug.
        bundle = (try! JSONSerialization.jsonObject(with: Data(bundleJson.utf8))) as! [String: Any]
        self.adapter = adapter
    }

    /// Runs one journey; returns its outcome (completed, cart_abandoned, fault, crash, cancelled, ...).
    func run(persona: String, run: Int, simSeed: Int64, toggles: Set<String>, infinite: Bool) async -> String {
        self.persona = persona
        self.toggles = toggles
        self.infinite = infinite
        rng = JourneyRng(seed: JourneyRng.journeySeed(simSeed: simSeed, run: run))
        vars.removeAll()
        let pv = (((bundle["personas"] as! [String: Any])[persona] as! [String: Any])["vars"]) as! [String: String]
        for (k, v) in pv { vars[k] = v }
        vars["run"] = String(run)
        vars["sim_seed"] = String(simSeed)
        vars["persona"] = persona
        spans.removeAll()
        crashFired = false
        do {
            try await block(bundle["journey"] as! [Any])
            return "completed"
        } catch let stop as Stop {
            return stop.outcome
        } catch {
            return "error"
        }
    }

    // MARK: - helpers

    private static let template = try! NSRegularExpression(pattern: #"\{([A-Za-z0-9_.]+)\}"#)

    private func t(_ s: String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in Self.template.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let name = ns.substring(with: m.range(at: 1))
            switch vars[name] {
            case let list as [String]: out += String(list.count)
            case let v as String: out += v
            default: break
            }
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private func tm(_ o: Any?) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in (o as? [String: Any]) ?? [:] { out[k] = t(str(v)) }
        return out
    }

    private func lst(_ name: String) -> [String] {
        if let v = vars[name] as? [String] { return v }
        vars[name] = [String]()
        return []
    }

    private func str(_ v: Any?) -> String { (v as? String) ?? "" }

    private func v(_ name: String) -> String { str(vars[name]) }

    private func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

    private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    private func strings(_ a: Any?) -> [String] { (a as? [Any])?.map { str($0) } ?? [] }

    /// org.json-style toString of a scalar response value.
    private func scalarString(_ x: Any) -> String {
        switch x {
        case let s as String: return s
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        default:
            let data = try? JSONSerialization.data(withJSONObject: x, options: [.fragmentsAllowed])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    private func p(_ chance: Op) -> Double {
        var table = chance["default"] as! [String: Any]
        if let by = chance["by"] as? String {
            let cases = chance["cases"] as! [String: Any]
            if let hit = cases[v(by)] as? [String: Any] { table = hit }
        }
        return num(table[persona])
    }

    /// Draws for `chance` first (always), then checks every other condition.
    private func condOk(_ op: Op) -> Bool {
        var ok = true
        if let chance = op["chance"] as? Op { ok = rng.next() < p(chance) }
        if let tg = op["toggle"] as? String, !toggles.contains(tg) { ok = false }
        if let tg = op["not_toggle"] as? String, toggles.contains(tg) { ok = false }
        if let eq = op["eq"] as? [Any], v(str(eq[0])) != str(eq[1]) { ok = false }
        if let ml = op["min_len"] as? [Any], lst(str(ml[0])).count < int(ml[1]) { ok = false }
        return ok
    }

    // MARK: - interpreter

    private func block(_ ops: [Any]) async throws {
        for op in ops {
            if adapter.isCancelled() { throw Stop(outcome: "cancelled") }
            try await step(op as! Op)
        }
    }

    private func step(_ op: Op) async throws {
        switch op["op"] as! String {
        case "new_session": adapter.startNewSession()
        case "exposures": adapter.applyExposures(persona: persona)
        case "entity":
            let ents = bundle["entities"] as! [String]
            let e = ents[(Int(v("run"))! - 1) % ents.count]
            vars["entity"] = e
            adapter.setEntity(e)
        case "wait": await adapter.delay(ms: int(op["ms"]))
        case "nav":
            await adapter.navigate(screen: str(op["screen"]), args: tm(op["args"]))
            await adapter.delay(ms: int(bundle["step_delay_ms"]))
        case "api":
            let res = await adapter.callApi(endpoint: str(op["endpoint"]), args: tm(op["args"]))
            for s in (op["save"] as! [Any]).map({ $0 as! Op }) {
                let value = res?[str(s["key"])]
                if let item = s["item"] as? String {
                    var items: [String] = []
                    for o in (value as? [Any]) ?? [] {
                        if let o = o as? Op, let x = o[item] { items.append(scalarString(x)) }
                    }
                    vars[str(s["var"])] = items.isEmpty ? strings(s["default"]) : items
                } else {
                    let text = value == nil || value is NSNull ? "" : scalarString(value!)
                    vars[str(s["var"])] = text.isEmpty ? t(str(s["default"])) : text
                }
            }
        case "log": adapter.log(level: str(op["level"]), event: str(op["event"]), fields: tm(op["fields"]))
        case "span_start": startSpan(op)
        case "span_end":
            if let h = spans.removeValue(forKey: str(op["span"])) {
                adapter.endSpan(handle: h, result: str(op["result"]), fields: tm(op["fields"]))
            }
        case "span":
            // Scoped span: success when the block finishes or the journey stops inside
            // it (fault / crash / outcome); canceled when the run is cancelled.
            startSpan(op)
            var result = "canceled"
            var failure: Error?
            do {
                try await block(op["do"] as! [Any])
                result = "success"
            } catch let stop as Stop {
                result = stop.outcome == "cancelled" ? "canceled" : "success"
                failure = stop
            }
            if let h = spans.removeValue(forKey: str(op["span"])) {
                adapter.endSpan(handle: h, result: result, fields: [:])
            }
            if let failure { throw failure }
        case "set":
            for (k, val) in (op["values"] as! [String: Any]) { vars[k] = t(str(val)) }
        case "pick":
            var items = op["values"] != nil ? strings(op["values"]) : lst(str(op["from"]))
            if let exclude = op["exclude"] as? String {
                let ex = t(exclude)
                items = items.filter { $0 != ex }
            }
            let r = rng.next()
            vars[str(op["into"])] = items.isEmpty ? "" : items[Int(r * Double(items.count))]
        case "rand_int":
            let lo = int(op["min"]), hi = int(op["max"])
            vars[str(op["into"])] = String(lo + Int(rng.next() * Double(hi - lo + 1)))
        case "choose":
            let weights = ((op["weights"] as! [String: Any])[persona] as! [Any]).map { $0 as! [Any] }
            var total = 0.0
            for w in weights { total += num(w[1]) }
            let x = rng.next() * total
            var pick = str(weights[weights.count - 1][0])
            var acc = 0.0
            for w in weights {
                acc += num(w[1])
                if x < acc {
                    pick = str(w[0])
                    break
                }
            }
            if let into = op["into"] as? String { vars[into] = pick }
            if let branch = (op["branches"] as! [String: Any])[pick] as? [Any] { try await block(branch) }
        case "if": try await block((condOk(op) ? op["then"] : op["else"]) as? [Any] ?? [])
        case "switch":
            let cases = op["cases"] as! [String: Any]
            try await block((cases[v(str(op["var"]))] as? [Any]) ?? (op["default"] as! [Any]))
        case "repeat":
            let range = (op["ranges"] as! [String: Any])[persona] as! [Any]
            let lo = int(range[0]), hi = int(range[1])
            let n = lo + Int(rng.next() * Double(hi - lo + 1))
            for _ in 0..<n { try await block(op["do"] as! [Any]) }
        case "for_each":
            for item in lst(str(op["list"])) {
                vars[str(op["as"])] = item
                try await block(op["do"] as! [Any])
            }
        case "list_add": vars[str(op["list"])] = lst(str(op["list"])) + [t(str(op["value"]))]
        case "list_remove_random":
            var items = lst(str(op["list"]))
            let r = rng.next()
            vars[str(op["into"])] = items.isEmpty ? "" : items.remove(at: Int(r * Double(items.count)))
            vars[str(op["list"])] = items
        case "list_clear": vars[str(op["list"])] = [String]()
        case "last": vars[str(op["into"])] = lst(str(op["list"])).last ?? t(str(op["default"]))
        case "fault": try fault(op)
        case "crash_point":
            let point = str(op["point"])
            if toggles.contains("crash_loop"), !crashFired, point == v("crash_point") || point == "confirmation" {
                crashFired = true
                adapter.addField(key: "crash_journey_point", value: point)
                adapter.fireCrash()
                throw Stop(outcome: "crash")
            }
        case "stop": throw Stop(outcome: str(op["outcome"]))
        default: fatalError("unknown journey op \(op["op"] ?? "?")")
        }
    }

    private func startSpan(_ op: Op) {
        let name = str(op["span"])
        let parent = (op["parent"] as? String).flatMap { spans[$0] }
        if let h = adapter.startSpan(name: name, parent: parent, fields: tm(op["fields"])) { spans[name] = h }
    }

    private func fault(_ op: Op) throws {
        let id = str(op["fault"])
        guard toggles.contains(id) else { return }
        let n = (eligible[id] ?? 0) + 1
        eligible[id] = n
        let randomHit = rng.next() < num(op["probability"])
        let forced = infinite && n >= int(op["force_after"])
        guard randomHit || forced else { return }
        eligible[id] = 0
        vars["trigger_mode"] = randomHit ? "random" : "forced_infinite"
        adapter.log(level: str(op["level"]), event: str(op["event"]), fields: tm(op["fields"]))
        adapter.injectFault(id: id)
        throw Stop(outcome: "fault")
    }
}
