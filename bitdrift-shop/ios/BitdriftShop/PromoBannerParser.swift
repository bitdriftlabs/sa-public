import Foundation

/// Parses the promo banner the backend sends to the Welcome screen. Another realistic crash
/// site: the render path trusts the payload, so a banner whose `discount_percent` arrives as
/// "20%" instead of 20 fails to decode, and `parse` force-tries the result.
enum PromoBannerParser {
    struct Banner: Decodable {
        let title: String
        let discountPercent: Int
        let endsAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case title
            case discountPercent = "discount_percent"
            case endsAtMs = "ends_at_ms"
        }
    }

    /// A payload as a misbehaving promo service might send it.
    static let malformedPayload = #"{"title":"Summer Sale","discount_percent":"20%","ends_at_ms":1793000000000}"#

    /// The careful form, used by the first (handled) attempt.
    static func tryParse(_ payload: String) throws -> Banner {
        try JSONDecoder().decode(Banner.self, from: Data(payload.utf8))
    }

    /// The render path: trusts the payload. A decode failure here is a `try!` trap.
    @inline(never)
    static func parse(_ payload: String) -> Banner {
        try! tryParse(payload)
    }
}
