package ai.bitdrift.shop

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Singleton HTTP client for the bitdrift-shop backend API.
 * The emulator reaches host localhost via 10.0.2.2.
 */
object ApiClient {

    private const val PORT = 5173
    private const val BASE_URL = "http://10.0.2.2:$PORT/api"
    private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    // ---- GET helpers ----

    private fun get(path: String): JSONObject {
        val request = Request.Builder().url("$BASE_URL$path").apply {
        }.build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string() ?: "{}"
            return JSONObject(body)
        }
    }

    private fun post(path: String, json: JSONObject = JSONObject()): JSONObject {
        val body = json.toString().toRequestBody(JSON_MEDIA)
        val request = Request.Builder().url("$BASE_URL$path").post(body).build()
        client.newCall(request).execute().use { response ->
            val respBody = response.body?.string() ?: "{}"
            return JSONObject(respBody)
        }
    }

    private fun delete(path: String): JSONObject {
        val request = Request.Builder().url("$BASE_URL$path").delete().apply {
        }.build()
        client.newCall(request).execute().use { response ->
            val respBody = response.body?.string() ?: "{}"
            return JSONObject(respBody)
        }
    }

    // ---- Public API (all suspend, run on IO dispatcher) ----

    suspend fun getWelcome(): JSONObject = withContext(Dispatchers.IO) { get("/welcome") }

    suspend fun getBrowse(): JSONObject = withContext(Dispatchers.IO) { get("/browse") }

    suspend fun search(query: String = ""): JSONObject = withContext(Dispatchers.IO) { get("/search?q=$query") }

    suspend fun getFeatured(): JSONObject = withContext(Dispatchers.IO) { get("/featured") }

    suspend fun getCategories(): JSONObject = withContext(Dispatchers.IO) { get("/categories") }

    suspend fun getCategoryProducts(category: String): JSONObject = withContext(Dispatchers.IO) {
        get("/categories/$category")
    }

    suspend fun getProduct(productId: String): JSONObject = withContext(Dispatchers.IO) {
        get("/product/$productId")
    }

    suspend fun getReviews(productId: String): JSONObject = withContext(Dispatchers.IO) {
        get("/product/$productId/reviews")
    }

    suspend fun addToCart(productId: String, quantity: Int = 1): JSONObject = withContext(Dispatchers.IO) {
        post("/cart", JSONObject().put("product_id", productId).put("quantity", quantity))
    }

    suspend fun getCart(): JSONObject = withContext(Dispatchers.IO) {
        get("/cart")
    }

    suspend fun deleteCartItem(productId: String): JSONObject = withContext(Dispatchers.IO) {
        delete("/cart/$productId")
    }

    suspend fun addToWishlist(productId: String): JSONObject = withContext(Dispatchers.IO) {
        post("/wishlist", JSONObject().put("product_id", productId))
    }

    suspend fun checkoutGuest(email: String = ""): JSONObject = withContext(Dispatchers.IO) {
        post("/checkout/guest", JSONObject().put("email", email))
    }

    suspend fun checkoutSignIn(email: String = ""): JSONObject = withContext(Dispatchers.IO) {
        post("/checkout/signin", JSONObject().put("email", email))
    }

    suspend fun payCard(checkoutSession: String, cardLast4: String = "4242"): JSONObject = withContext(Dispatchers.IO) {
        post("/payment/card", JSONObject().put("checkout_session", checkoutSession).put("card_last4", cardLast4))
    }

    suspend fun payApplePay(checkoutSession: String): JSONObject = withContext(Dispatchers.IO) {
        post("/payment/applepay", JSONObject().put("checkout_session", checkoutSession))
    }

    suspend fun payPayPal(checkoutSession: String): JSONObject = withContext(Dispatchers.IO) {
        post("/payment/paypal", JSONObject().put("checkout_session", checkoutSession))
    }

    suspend fun payAndroidPay(checkoutSession: String): JSONObject = withContext(Dispatchers.IO) {
        post("/payment/androidpay", JSONObject().put("checkout_session", checkoutSession))
    }

    suspend fun getConfirmation(orderId: String): JSONObject = withContext(Dispatchers.IO) {
        get("/confirmation/$orderId")
    }

    /** Returns the raw JSON string of the product array from /browse (for recommendation scoring). */
    suspend fun getFullCatalogJson(): String = withContext(Dispatchers.IO) {
        val result = get("/browse")
        val arr = result.optJSONArray("products")
        arr?.toString() ?: "[]"
    }

    suspend fun inventoryLookup(item: String): JSONObject = withContext(Dispatchers.IO) {
        val session = buildString {
            repeat(16) { append("0123456789abcdef".random()) }
        }
        get("/inventory/lookup/$item/$session")
    }

}
