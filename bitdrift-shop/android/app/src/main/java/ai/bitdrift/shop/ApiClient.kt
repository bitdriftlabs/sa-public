package ai.bitdrift.shop

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import io.bitdrift.capture.network.okhttp.CaptureOkHttpEventListenerFactory
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

    // bitdrift SDK: CaptureOkHttpEventListenerFactory() attaches to every OkHttp call and
    // automatically logs requests and responses in the bitdrift session timeline.
    // POC: network monitoring — unsampled latency, error rates, and throughput per endpoint
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .eventListenerFactory(CaptureOkHttpEventListenerFactory())
        .build()

    // ---- GET helpers ----

    private fun get(path: String, pathTemplate: String? = null): JSONObject {
        val request = Request.Builder().url("$BASE_URL$path").apply {
            if (pathTemplate != null) addHeader("x-capture-path-template", pathTemplate)
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

    private fun delete(path: String, pathTemplate: String? = null): JSONObject {
        val request = Request.Builder().url("$BASE_URL$path").delete().apply {
            if (pathTemplate != null) addHeader("x-capture-path-template", pathTemplate)
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
        get("/categories/$category", "/api/categories/<category>")
    }

    suspend fun getProduct(productId: String): JSONObject = withContext(Dispatchers.IO) {
        get("/product/$productId", "/api/product/<id>")
    }

    suspend fun getReviews(productId: String): JSONObject = withContext(Dispatchers.IO) {
        get("/product/$productId/reviews", "/api/product/<id>/reviews")
    }

    suspend fun addToCart(productId: String, quantity: Int = 1): JSONObject = withContext(Dispatchers.IO) {
        post("/cart", JSONObject().put("product_id", productId).put("quantity", quantity))
    }

    suspend fun getCart(): JSONObject = withContext(Dispatchers.IO) {
        get("/cart")
    }

    suspend fun deleteCartItem(productId: String): JSONObject = withContext(Dispatchers.IO) {
        delete("/cart/$productId", "/api/cart/<id>")
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
        get("/confirmation/$orderId", "/api/confirmation/<id>")
    }

    /** Fetches the latest capture-sdk release tag from GitHub (strips leading "v"). Returns null on any error. */
    suspend fun fetchLatestSdkVersion(): String? = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("https://api.github.com/repos/bitdriftlabs/capture-sdk/releases/latest")
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                JSONObject(response.body?.string() ?: return@withContext null)
                    .optString("tag_name", "").removePrefix("v").ifEmpty { null }
            }
        } catch (_: Exception) { null }
    }

    /** Returns the raw JSON string of the product array from /browse (for recommendation scoring). */
    suspend fun getFullCatalogJson(): String = withContext(Dispatchers.IO) {
        val result = get("/browse")
        val arr = result.optJSONArray("products")
        arr?.toString() ?: "[]"
    }

    // ── Cardinality demo ──────────────────────────────────────────────────
    // Generates a fresh random hex `session` on every call so each request
    // produces a unique URL, creating infinite cardinality in the Bitdrift
    // HTTP traffic dashboard. Demonstrates the need for Path Templates.
    suspend fun inventoryLookup(item: String): JSONObject = withContext(Dispatchers.IO) {
        val hex = "0123456789abcdef"
        val session = buildString { repeat(16) { append(hex.random()) } }
        // Without a path template every request lands as a unique URL in the Bitdrift
        // dashboard (e.g. /api/inventory/lookup/headphones/a3f92b1e4d7c0e85). The block
        // below is the FIX: passing the x-capture-path-template header tells the SDK to
        // record all requests under the single canonical path, collapsing the cardinality
        // explosion into one dashboard entry. To apply: uncomment the block and delete the
        // get() call beneath it.
        // Docs: https://docs.bitdrift.io/sdk/features/http-traffic-logs#http-request-fields
        //
        // val request = Request.Builder()
        //     .url("$BASE_URL/inventory/lookup/${item}/${session}")
        //     .header("x-capture-path-template", "/api/inventory/lookup/<item>/<session>")
        //     .build()
        // return@withContext client.newCall(request).execute()
        //     .use { r -> JSONObject(r.body?.string() ?: "{}") }
        get("/inventory/lookup/${item}/${session}")
    }
}
