import Capture
import Foundation

/// Record mode for the test harness: appends every app-emitted log, span and screen view to a
/// JSONL file in the app's Documents/record directory, so `tools/conformance` can validate the
/// stream against spec/telemetry.yaml with no bitdrift account involved. Off unless a launch
/// argument names a record file (see `Autorun`). Line shapes (same as the Android recorder):
///   {"kind":"log","level":"info","message":"...","fields":{...}}
///   {"kind":"span_start","id":"...","name":"...","parent":"..."|null,"fields":{...}}
///   {"kind":"span_end","id":"...","result":"success","fields":{...}}
///   {"kind":"screen","name":"..."}
enum Recorder {
    private static let lock = NSLock()
    private static var handle: FileHandle?

    static var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return handle != nil
    }

    /// Opens (truncating) `Documents/record/<fileName>` and carries over spans already open.
    @discardableResult
    static func start(fileName: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("record", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        lock.lock()
        handle = try? FileHandle(forWritingTo: url)
        lock.unlock()
        RecordedSpan.carryOpenSpans()
        return url
    }

    static func write(_ kind: String, _ pairs: [String: Any] = [:], fields: [String: String]? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return }
        var obj: [String: Any] = ["t": Int(Date().timeIntervalSince1970 * 1000), "kind": kind]
        for (k, v) in pairs { obj[k] = v }
        if let fields { obj["fields"] = fields }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }

    static func flatten(_ fields: Fields?) -> [String: String]? {
        guard let fields, !fields.isEmpty else { return nil }
        return fields.mapValues { String(describing: $0) }
    }
}

/// A started span. Wraps the SDK span so its start and end are also written to the `Recorder`.
/// Exposes the same `id` / `end` the app uses.
final class RecordedSpan {
    private static let lock = NSLock()
    private static var open: [UUID: RecordedSpan] = [:]

    private let sdk: Span?
    let name: String
    private let localID: UUID
    private let parent: UUID?
    private let startFields: [String: String]?

    var id: UUID { sdk?.id ?? localID }

    private init(sdk: Span?, name: String, parent: UUID?, startFields: [String: String]?) {
        self.sdk = sdk
        self.name = name
        self.localID = sdk?.id ?? UUID()
        self.parent = parent
        self.startFields = startFields
    }

    /// Same labels as `Logger.startSpan`.
    static func start(
        name: String,
        level: LogLevel,
        fields: Fields? = nil,
        startTimeInterval: TimeInterval? = nil,
        parentSpanID: UUID? = nil
    ) -> RecordedSpan? {
        let sdk = Logger.startSpan(
            name: name, level: level, fields: fields,
            startTimeInterval: startTimeInterval, parentSpanID: parentSpanID
        )
        let flat = Recorder.flatten(fields)
        let span = RecordedSpan(sdk: sdk, name: name, parent: parentSpanID, startFields: flat)
        lock.lock(); open[span.localID] = span; lock.unlock()
        Recorder.write("span_start", [
            "id": span.localID.uuidString, "name": name,
            "parent": parentSpanID?.uuidString ?? NSNull(),
        ], fields: flat)
        return span
    }

    func end(_ result: SpanResult, fields: Fields? = nil, endTimeInterval: TimeInterval? = nil) {
        sdk?.end(result, fields: fields, endTimeInterval: endTimeInterval)
        Self.lock.lock(); Self.open[localID] = nil; Self.lock.unlock()
        Recorder.write("span_end", [
            "id": localID.uuidString, "name": name, "result": String(describing: result).lowercased(),
        ], fields: Recorder.flatten(fields))
    }

    /// Called by `Recorder.start`: a (carried) start for every span already open.
    static func carryOpenSpans() {
        lock.lock(); let spans = Array(open.values); lock.unlock()
        for s in spans {
            Recorder.write("span_start", [
                "id": s.localID.uuidString, "name": s.name,
                "parent": s.parent?.uuidString ?? NSNull(), "carried": true,
            ], fields: s.startFields)
        }
    }
}

/// Launch arguments for the automated test harness (`xcrun simctl launch ... -sim_runs 5 ...`):
///   -sim_runs N  -sim_seed S  -persona control|variant_a|variant_b  -record_file name.jsonl
///   [-crash <name>]  with the crash loop on, fire this catalog crash (e.g. app_coupon_empty_cart)
/// `sim_runs` > 0 turns on autorun: skip the config countdown, run N journeys, log
/// `sim_autorun_complete`. `sim_seed` seeds the journey engine (masked to 0..<2^31, see `simSeed`).
enum Autorun {
    static let defaults = UserDefaults.standard
    static let runs = defaults.integer(forKey: "sim_runs")
    static let seed = defaults.integer(forKey: "sim_seed")
    /// `seed` masked to the engine's 0..<2^31 range; this is the value reported as `sim_seed`.
    static let simSeed = Int64(seed) & 0x7FFF_FFFF
    static let persona = defaults.string(forKey: "persona") ?? "control"
    static let recordFile = defaults.string(forKey: "record_file")
    /// `-crash <catalog name>`: fire exactly this crash at the journey's crash point (instead of the sweep).
    static let crash = defaults.string(forKey: "crash")
    static var started = false

    static var active: Bool { runs > 0 }

    static var variant: SimVariant {
        switch persona {
        case "variant_a": return .variantA
        case "variant_b": return .variantB
        default: return .control
        }
    }
}
