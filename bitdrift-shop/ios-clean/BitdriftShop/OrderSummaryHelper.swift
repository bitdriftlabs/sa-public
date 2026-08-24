import Foundation

/// Formats the Confirmation screen's order summary, caching the last formatted
/// total. Used only while the crash loop is active — the cached total is what
/// distinguishes the `order_summary` v2 code path from v1 (see
/// `SimulationManager.setVariant`).
enum OrderSummaryHelper {

    private static var cachedTotal: String?

    static var totalFormatted: String { cachedTotal ?? "$0.00" }

    static func formatOrderSummary(_ data: JSON?, orderID: String) -> String {
        guard let data, data.exists else {
            return "Order \(orderID)\nTotal: \(totalFormatted)\nThank you for your purchase!"
        }
        let txn = data.str("transaction_id")
        cachedTotal = money(data.num("total"))
        let shipping = data["shipping"]
        let delivery = shipping.str("estimated_delivery")
        let tracking = shipping.str("tracking_number")
        return """
        Order \(data.str("order_id", orderID))
        Total: \(totalFormatted)
        Delivery: \(delivery)
        Tracking: \(tracking)
        Txn: \(String(txn.prefix(24)))…
        """
    }

    static func reset() {
        cachedTotal = nil
    }
}
