import Foundation

/// A lightweight, mutable JSON object wrapper mirroring Android's `org.json.JSONObject` API
/// (`optString`/`optInt`/`optDouble`/`optJSONArray`/`put`, etc.), so `ApiClient.swift` can be a
/// close, mechanical port of `ApiClient.kt` rather than a rewrite onto `Codable`. Backed by a
/// plain `[String: Any]` so it round-trips through `JSONSerialization` directly.
final class JSONObject {
    private(set) var storage: [String: Any]

    init(_ storage: [String: Any] = [:]) {
        self.storage = storage
    }

    convenience init(data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        self.init(object as? [String: Any] ?? [:])
    }

    convenience init(string: String) {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            self.init([:])
            return
        }
        self.init(dict)
    }

    @discardableResult
    func put(_ key: String, _ value: Any?) -> JSONObject {
        if let value {
            self.storage[key] = value
        }
        return self
    }

    @discardableResult
    func put(_ key: String, _ value: JSONObject) -> JSONObject {
        self.storage[key] = value.storage
        return self
    }

    @discardableResult
    func put(_ key: String, _ value: [JSONObject]) -> JSONObject {
        self.storage[key] = value.map(\.storage)
        return self
    }

    /// Mirrors `org.json.JSONObject.optString`, which stringifies any value type (not just
    /// actual strings) via `String.valueOf` -- e.g. a numeric `score` field still round-trips
    /// through `optString(...).toIntOrNull()` on Android. Without this, a JSON number here would
    /// silently fall back to `fallback` instead.
    func optString(_ key: String, _ fallback: String = "") -> String {
        switch self.storage[key] {
        case let value as String: value
        case let value as Bool: value ? "true" : "false"
        case let value as NSNumber: value.stringValue
        case let value as Int: String(value)
        case let value as Double: String(value)
        default: fallback
        }
    }

    func optInt(_ key: String, _ fallback: Int = 0) -> Int {
        if let value = self.storage[key] as? Int { return value }
        if let value = self.storage[key] as? Double { return Int(value) }
        if let value = self.storage[key] as? NSNumber { return value.intValue }
        return fallback
    }

    func optLong(_ key: String, _ fallback: Int64 = 0) -> Int64 {
        if let value = self.storage[key] as? NSNumber { return value.int64Value }
        return fallback
    }

    func optDouble(_ key: String, _ fallback: Double = 0.0) -> Double {
        if let value = self.storage[key] as? Double { return value }
        if let value = self.storage[key] as? Int { return Double(value) }
        if let value = self.storage[key] as? NSNumber { return value.doubleValue }
        return fallback
    }

    func optJSONObject(_ key: String) -> JSONObject? {
        guard let dict = self.storage[key] as? [String: Any] else { return nil }
        return JSONObject(dict)
    }

    func optJSONArray(_ key: String) -> [JSONObject]? {
        guard let array = self.storage[key] as? [[String: Any]] else { return nil }
        return array.map(JSONObject.init)
    }

    /// Convenience for arrays of scalars (used for the rare non-object array, e.g. `images`).
    func optStringArray(_ key: String) -> [String]? {
        self.storage[key] as? [String]
    }

    var keys: [String] { Array(self.storage.keys) }

    func toData() -> Data {
        (try? JSONSerialization.data(withJSONObject: self.storage)) ?? Data("{}".utf8)
    }
}
