package ai.bitdrift.shop

import org.json.JSONObject

/**
 * Parses the promo banner the backend sends to the Welcome screen. Another realistic crash
 * site: the render path trusts the payload, so a banner whose `discount_percent` arrives as
 * "20%" instead of 20 makes [parse] throw an IllegalStateException (wrapping the JSONException) with
 * nothing catching it. Wrapped because JSONException is checked: left bare, a main-thread crash would
 * be rewrapped by the platform as RuntimeException(InvocationTargetException) and group under
 * `RuntimeInit` instead of this class.
 */
object PromoBannerParser {
    data class Banner(val title: String, val discountPercent: Int, val endsAtMs: Long)

    fun parse(payload: String): Banner {
        try {
            val json = JSONObject(payload)
            return Banner(
                title = json.getString("title"),
                discountPercent = json.getInt("discount_percent"),
                endsAtMs = json.getLong("ends_at_ms"),
            )
        } catch (e: org.json.JSONException) {
            throw IllegalStateException("Malformed promo banner payload", e)
        }
    }

    /** A payload as a misbehaving promo service might send it. */
    const val MALFORMED_PAYLOAD = """{"title":"Summer Sale","discount_percent":"20%","ends_at_ms":1793000000000}"""
}
