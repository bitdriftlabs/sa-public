import Foundation

/// Minimal dynamic JSON reader over `JSONSerialization` output.
///
/// The backend returns large, loosely-typed payloads that the app only ever
/// reads a handful of fields from (see `shopping_server.py` — a single product
/// card carries trending data, promotions, seller info, …). Decoding those into
/// `Codable` structs would mean maintaining ~20 models to use ~40 fields, and
/// any backend addition would be a compile error rather than an ignored key.
/// This mirrors the Android app's use of `org.json.JSONObject`, so both apps
/// read the same payloads the same way.
///
/// Every accessor is total: missing keys, wrong types, and nulls all collapse
/// to `nil` / an empty collection rather than throwing.
struct JSON {
    let raw: Any?

    init(_ raw: Any?) {
        // JSONSerialization represents JSON null as NSNull; normalise it away so
        // callers never have to test for it.
        self.raw = raw is NSNull ? nil : raw
    }

    static let empty = JSON(nil)

    static func parse(_ data: Data) -> JSON {
        JSON(try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    static func parse(string: String) -> JSON {
        guard let data = string.data(using: .utf8) else { return .empty }
        return parse(data)
    }

    // MARK: - Traversal

    subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> JSON {
        guard let arr = raw as? [Any], index >= 0, index < arr.count else { return .empty }
        return JSON(arr[index])
    }

    /// Array elements, or an empty array when this is not an array.
    var array: [JSON] {
        (raw as? [Any])?.map(JSON.init) ?? []
    }

    var exists: Bool { raw != nil }

    // MARK: - Leaf values

    var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    var double: Double? { (raw as? NSNumber)?.doubleValue ?? Double(raw as? String ?? "") }

    var int: Int? { (raw as? NSNumber)?.intValue ?? Int(raw as? String ?? "") }

    var bool: Bool? { (raw as? NSNumber)?.boolValue }

    // MARK: - Defaulted accessors (mirror org.json's optXxx)

    func str(_ key: String, _ fallback: String = "") -> String { self[key].string ?? fallback }

    func num(_ key: String, _ fallback: Double = 0) -> Double { self[key].double ?? fallback }

    func int(_ key: String, _ fallback: Int = 0) -> Int { self[key].int ?? fallback }

    /// Re-serialises this value back to a JSON string. Used by
    /// `RecommendationEngine`, which scores products by comparing whole
    /// serialised product profiles.
    var serialized: String {
        guard let raw,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }
}

/// `$12.34` — matches the Android app's `String.format("%.2f", …)` output so
/// both apps render identical subtitles.
func money(_ value: Double) -> String {
    String(format: "$%.2f", value)
}
