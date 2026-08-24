package ai.bitdrift.shop

import org.json.JSONObject

object OrderSummaryHelper {

    private var _totalFormatted: String? = null

    val totalFormatted: String
        get() = _totalFormatted ?: "$0.00"

    fun formatOrderSummary(apiData: JSONObject?, orderId: String): String {
        val data = apiData ?: return "Order $orderId\nTotal: $totalFormatted\nThank you for your purchase!"
        val txn = data.optString("transaction_id", "")
        val total = data.optDouble("total", 0.0)
        _totalFormatted = "$${String.format("%.2f", total)}"
        val shipping = data.optJSONObject("shipping")
        val delivery = shipping?.optString("estimated_delivery", "") ?: ""
        val tracking = shipping?.optString("tracking_number", "") ?: ""
        return "Order ${data.optString("order_id", orderId)}\nTotal: $totalFormatted\nDelivery: $delivery\nTracking: $tracking\nTxn: ${txn.take(24)}…"
    }

    fun reset() {
        _totalFormatted = null
    }
}
