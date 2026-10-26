package ai.bitdrift.shop

import java.util.concurrent.ConcurrentHashMap
import org.json.JSONArray
import org.json.JSONObject

/**
 * Remembers each product's category from the catalog responses the app has already seen
 * (browse, search, featured, category, product), because the backend's cart lines only carry a
 * product id. Used to put a category on every line of `cart_json`.
 */
object ProductCatalog {
    private val categories = ConcurrentHashMap<String, String>()

    /** Learns from any response shaped like a product list (`products[]`) or a single product. */
    fun learn(response: JSONObject?) {
        response ?: return
        val list = response.optJSONArray("products") ?: response.optJSONArray("featured_products")
        if (list != null) for (i in 0 until list.length()) learnOne(list.optJSONObject(i))
        else learnOne(response)
    }

    private fun learnOne(p: JSONObject?) {
        val id = p?.optString("id").orEmpty()
        val category = p?.optString("category").orEmpty()
        if (id.isNotEmpty() && category.isNotEmpty()) categories[id] = category
    }

    fun categoryOf(productId: String): String = categories[productId] ?: "unknown"
}

/**
 * `cart_json`: the cart as one JSON string field, {"items":[{"id","category","price","quantity"}],"total"}.
 * A workflow metric uses JSON paths on it to chart revenue by category (`items[].category`,
 * `items[].price`) without a separate field per line.
 */
object CartJson {
    fun from(cart: JSONObject?): String {
        val items = JSONArray()
        val lines = cart?.optJSONArray("items")
        if (lines != null) for (i in 0 until lines.length()) {
            val l = lines.optJSONObject(i) ?: continue
            val id = l.optString("product_id")
            items.put(
                JSONObject()
                    .put("id", id)
                    .put("category", ProductCatalog.categoryOf(id))
                    .put("price", l.optDouble("unit_price", 0.0))
                    .put("quantity", l.optInt("quantity", 1))
            )
        }
        return JSONObject().put("items", items).put("total", cart?.optDouble("total", 0.0) ?: 0.0).toString()
    }

    fun lines(cart: JSONObject?): List<CartPricing.Line> {
        val out = mutableListOf<CartPricing.Line>()
        val lines = cart?.optJSONArray("items") ?: return out
        for (i in 0 until lines.length()) {
            val l = lines.optJSONObject(i) ?: continue
            out += CartPricing.Line(l.optString("product_id"), l.optDouble("unit_price", 0.0), l.optInt("quantity", 1))
        }
        return out
    }
}
