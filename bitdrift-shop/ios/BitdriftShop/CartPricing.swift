import Foundation

/// Order pricing, as a real shop app would write it. Deliberately has one sharp edge, which is
/// what makes it a realistic crash site: `applyCoupon` assumes the cart is not empty, and a
/// checkout path that reaches it with an empty cart (a race with "remove last item") traps
/// inside this type, so the crash report's top app frame is `CartPricing.applyCoupon`.
enum CartPricing {
    struct Line {
        let productId: String
        let unitPrice: Double
        let quantity: Int

        var total: Double { unitPrice * Double(quantity) }
    }

    private static let coupons: [String: Double] = ["SUMMER20": 0.20, "WELCOME10": 0.10, "FREESHIP": 0.0]

    /// The discount `code` gives on `lines`: a percentage of the most valuable line. No
    /// empty-cart guard: the force unwrap of `max(by:)` traps on an empty list.
    @inline(never)
    static func applyCoupon(_ lines: [Line], code: String) -> Double {
        let rate = coupons[code] ?? 0
        let anchor = lines.max(by: { $0.total < $1.total })!
        return anchor.total * rate
    }

    /// The same computation with the guard the crashing path is missing, for the handled path.
    static func applyCouponChecked(_ lines: [Line], code: String) throws -> Double {
        guard !lines.isEmpty else { throw CartError.emptyCart }
        return applyCoupon(lines, code: code)
    }

    enum CartError: Error { case emptyCart }
}
