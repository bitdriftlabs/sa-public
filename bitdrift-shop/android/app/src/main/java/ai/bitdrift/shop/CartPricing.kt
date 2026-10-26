package ai.bitdrift.shop

/**
 * Order pricing, as a real shop app would write it. Deliberately has one sharp edge, which is
 * what makes it a realistic crash site: [applyCoupon] assumes the cart is not empty, and a
 * checkout path that reaches it with an empty cart (a race with "remove last item") throws from
 * this class, so the crash report's top app frame is `CartPricing.applyCoupon`.
 */
object CartPricing {
    data class Line(val productId: String, val unitPrice: Double, val quantity: Int) {
        val total: Double get() = unitPrice * quantity
    }

    private val coupons = mapOf("SUMMER20" to 0.20, "WELCOME10" to 0.10, "FREESHIP" to 0.0)

    /**
     * The discount [code] gives on [lines]: a percentage of the most valuable line.
     * No empty-cart guard: `maxBy` throws NoSuchElementException on an empty list.
     */
    fun applyCoupon(lines: List<Line>, code: String): Double {
        val rate = coupons.getValue(code)
        val anchor = lines.maxBy { it.total }
        return anchor.total * rate
    }
}
