import Foundation

// Replays tools/journey/golden.json (written by the Python reference engine from
// spec/journey.yaml): for every seeded case the Swift engine must make exactly the same
// adapter calls, in the same order, as tools/journey/engine.py.
// Built and run by scripts/test-journey-engine.sh; Foundation only, no app code.

final class Handle {
    let name: String
    init(_ name: String) { self.name = name }
}

@MainActor
final class TraceAdapter: JourneyAdapter {
    var lines: [String] = []
    private let fixture: [String: Any]

    init(fixture: [String: Any]) { self.fixture = fixture }

    private func f(_ m: [String: String]) -> String {
        "{" + m.keys.sorted().map { "\($0)=\(m[$0]!)" }.joined(separator: ", ") + "}"
    }

    func isCancelled() -> Bool { false }
    func startNewSession() { lines.append("new_session") }
    func applyExposures(persona: String) { lines.append("exposures \(persona)") }
    func setEntity(_ entity: String) { lines.append("entity \(entity)") }
    func delay(ms: Int) async { lines.append("wait \(ms)") }
    func navigate(screen: String, args: [String: String]) async { lines.append("nav \(screen) \(f(args))") }
    func callApi(endpoint: String, args: [String: String]) async -> [String: Any]? {
        lines.append("api \(endpoint) \(f(args))")
        if let fail = fixture["fail"] as? [String], fail.contains(endpoint) { return nil }
        return (fixture[endpoint] as? [String: Any]) ?? [:]
    }
    func log(level: String, event: String, fields: [String: String]) {
        lines.append("log \(level) \(event) \(f(fields))")
    }
    func startSpan(name: String, parent: AnyObject?, fields: [String: String]) -> AnyObject? {
        lines.append("span_start \(name) \((parent as? Handle)?.name ?? "-") \(f(fields))")
        return Handle(name)
    }
    func endSpan(handle: AnyObject, result: String, fields: [String: String]) {
        lines.append("span_end \((handle as! Handle).name) \(result) \(f(fields))")
    }
    func addField(key: String, value: String) { lines.append("field \(key)=\(value)") }
    func injectFault(id: String) { lines.append("fault \(id)") }
    func fireCrash() { lines.append("crash") }
}

@MainActor
func runTests() async -> Int {
    var failures = 0

    var rng = JourneyRng(seed: 42)
    let a = rng.next(), b = rng.next()
    if a != 0.6011037519201636 || b != 0.44829055899754167 {
        print("FAIL rng: mulberry32(42) = \(a), \(b)")
        failures += 1
    }
    let big = JourneyRng.journeySeed(simSeed: 2147483647, run: 4)
    if big != UInt32(truncatingIfNeeded: (2147483647 * 1000003 + 4) & 0xFFFFFFFF) {
        print("FAIL journeySeed wrap: \(big)")
        failures += 1
    }

    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tools/journey/golden.json"
    guard let data = FileManager.default.contents(atPath: path),
          let golden = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = golden["cases"] as? [[String: Any]] else {
        print("FAIL cannot read golden file \(path)")
        return failures + 1
    }
    let fixture = golden["fixture"] as? [String: Any] ?? [:]

    for c in cases {
        let name = c["name"] as! String
        let adapter = TraceAdapter(fixture: fixture)
        let engine = JourneyEngine(bundleJson: SpecJourney.json, adapter: adapter)
        let toggles = Set((c["toggles"] as! [String]))
        for run in 1...(c["runs"] as! NSNumber).intValue {
            let outcome = await engine.run(
                persona: c["persona"] as! String, run: run,
                simSeed: (c["sim_seed"] as! NSNumber).int64Value,
                toggles: toggles, infinite: (c["infinite"] as! NSNumber).boolValue
            )
            adapter.lines.append("outcome \(outcome)")
        }
        let want = c["trace"] as! [String]
        let got = adapter.lines
        let diff = (0..<max(want.count, got.count)).first {
            $0 >= want.count || $0 >= got.count || want[$0] != got[$0]
        }
        if let i = diff {
            print("FAIL \(name): first difference at line \(i)")
            print("  want: \(i < want.count ? want[i] : "<end>")")
            print("  got:  \(i < got.count ? got[i] : "<end>")")
            failures += 1
        } else {
            print("PASS \(name) (\(want.count) lines)")
        }
    }
    return failures
}

let failures = await runTests()
print(failures == 0 ? "journey engine: all cases pass" : "journey engine: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
