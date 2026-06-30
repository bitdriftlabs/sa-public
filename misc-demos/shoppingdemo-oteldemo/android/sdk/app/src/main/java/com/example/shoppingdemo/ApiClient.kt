package com.example.shoppingdemo

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import io.bitdrift.capture.network.okhttp.CaptureOkHttpEventListenerFactory
import io.bitdrift.capture.network.okhttp.CaptureOkHttpTracingInterceptor
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.UUID

/**
 * Compatibility adapter that keeps the app's existing JSON contract while
 * sourcing data from the OpenTelemetry Demo frontend proxy.
 */
object ApiClient {

    private const val HOST = BuildConfig.OTEL_DEMO_HOST
    private const val PORT = BuildConfig.OTEL_DEMO_PORT
    private const val BASE_URL = "http://$HOST:$PORT/api"
    private const val IMAGE_BASE_URL = "http://$HOST:$PORT/images/products"
    private const val DEFAULT_CURRENCY = "USD"
    private const val TAX_RATE = 0.08
    private const val PREFS_NAME = "otel_demo_adapter"
    private const val USER_ID_KEY = "user_id"
    private const val WISHLIST_KEY = "wishlist_ids"
    private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .addInterceptor(CaptureOkHttpTracingInterceptor())
        .eventListenerFactory(CaptureOkHttpEventListenerFactory())
        .build()

    private val prefs
        get() = ShoppingDemoApp.appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun currentUserId(): String {
        prefs.getString(USER_ID_KEY, null)?.let { return it }
        val userId = "android-${UUID.randomUUID()}"
        prefs.edit().putString(USER_ID_KEY, userId).apply()
        return userId
    }

    private fun checkoutKey(sessionId: String) = "checkout_$sessionId"

    private fun confirmationKey(orderId: String) = "confirmation_$orderId"

    private fun buildUrl(path: String, queryParams: Map<String, Any?> = emptyMap()): String {
        val builder = "$BASE_URL$path".toHttpUrl().newBuilder()
        queryParams.forEach { (key, value) ->
            when (value) {
                null -> Unit
                is Iterable<*> -> value.forEach { item ->
                    if (item != null) {
                        builder.addQueryParameter(key, item.toString())
                    }
                }
                else -> builder.addQueryParameter(key, value.toString())
            }
        }
        return builder.build().toString()
    }

    private fun execute(request: Request, allowHttpError: Boolean = false): String {
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful && !allowHttpError) {
                throw IllegalStateException("HTTP ${response.code}: $body")
            }
            return body
        }
    }

    private fun getObject(path: String, queryParams: Map<String, Any?> = emptyMap()): JSONObject {
        val request = Request.Builder().url(buildUrl(path, queryParams)).build()
        val body = execute(request)
        return JSONObject(if (body.isBlank()) "{}" else body)
    }

    private fun getArray(path: String, queryParams: Map<String, Any?> = emptyMap()): JSONArray {
        val request = Request.Builder().url(buildUrl(path, queryParams)).build()
        val body = execute(request)
        return JSONArray(if (body.isBlank()) "[]" else body)
    }

    private fun postObject(
        path: String,
        bodyJson: JSONObject = JSONObject(),
        queryParams: Map<String, Any?> = emptyMap()
    ): JSONObject {
        val body = bodyJson.toString().toRequestBody(JSON_MEDIA)
        val request = Request.Builder()
            .url(buildUrl(path, queryParams))
            .post(body)
            .build()
        val responseBody = execute(request)
        return JSONObject(if (responseBody.isBlank()) "{}" else responseBody)
    }

    private fun deleteObject(
        path: String,
        bodyJson: JSONObject? = null,
        queryParams: Map<String, Any?> = emptyMap()
    ): JSONObject {
        val requestBuilder = Request.Builder().url(buildUrl(path, queryParams))
        val request = if (bodyJson == null) {
            requestBuilder.delete().build()
        } else {
            requestBuilder.delete(bodyJson.toString().toRequestBody(JSON_MEDIA)).build()
        }
        val responseBody = execute(request)
        return JSONObject(if (responseBody.isBlank()) "{}" else responseBody)
    }

    private fun requestInventoryLookup(path: String): JSONObject {
        val request = Request.Builder().url("$BASE_URL$path").build()
        val body = execute(request, allowHttpError = true)
        return JSONObject()
            .put("path", path)
            .put("status", if (body.isBlank()) "empty" else "ok")
    }

    private fun readStoredJson(key: String): JSONObject? =
        prefs.getString(key, null)?.let(::JSONObject)

    private fun writeStoredJson(key: String, value: JSONObject) {
        prefs.edit().putString(key, value.toString()).apply()
    }

    private fun imageUrl(picture: String): String = "$IMAGE_BASE_URL/$picture"

    private fun formatCategory(raw: String): String = raw
        .split(Regex("[_\\s-]+"))
        .filter { it.isNotBlank() }
        .joinToString(" ") { token ->
            token.lowercase(Locale.US).replaceFirstChar { ch ->
                if (ch.isLowerCase()) ch.titlecase(Locale.US) else ch.toString()
            }
        }
        .ifBlank { "Products" }

    private fun moneyToDouble(money: JSONObject?): Double {
        if (money == null) return 0.0
        val units = money.optLong("units", 0L).toDouble()
        val nanos = money.optLong("nanos", 0L) / 1_000_000_000.0
        return units + nanos
    }

    private fun cents(value: Double): Double = kotlin.math.round(value * 100.0) / 100.0

    private fun productToLegacy(product: JSONObject): JSONObject {
        val picture = product.optString("picture", "")
        val categories = product.optJSONArray("categories") ?: JSONArray()
        val primaryCategory = formatCategory(categories.optString(0, "Products"))
        val price = cents(moneyToDouble(product.optJSONObject("priceUsd")))
        val description = product.optString("description", product.optString("name", ""))

        return JSONObject()
            .put("id", product.optString("id", ""))
            .put("name", product.optString("name", "Unnamed Product"))
            .put("description", description)
            .put("brand", "OpenTelemetry Demo")
            .put("category", primaryCategory)
            .put("price", price)
            .put("image_url", imageUrl(picture))
            .put("images", JSONArray().put(imageUrl(picture)))
            .put("picture", picture)
    }

    private fun listOtelProducts(): JSONArray = getArray(
        "/products",
        queryParams = mapOf("currencyCode" to DEFAULT_CURRENCY)
    )

    private fun getOtelProduct(productId: String): JSONObject = getObject(
        "/products/$productId",
        queryParams = mapOf("currencyCode" to DEFAULT_CURRENCY)
    )

    private fun listLegacyProducts(): JSONArray {
        val source = listOtelProducts()
        val mapped = JSONArray()
        for (index in 0 until source.length()) {
            mapped.put(productToLegacy(source.getJSONObject(index)))
        }
        return mapped
    }

    private fun currentWishlistIds(): MutableSet<String> =
        prefs.getStringSet(WISHLIST_KEY, emptySet())?.toMutableSet() ?: mutableSetOf()

    private fun memberProfile(): JSONObject = JSONObject()
        .put("id", currentUserId())
        .put("name", "Taylor Shopper")
        .put("email", "taylor.shopper@example.com")
        .put("loyalty_points", 240)

    private fun guestEmail(): String = "guest.${currentUserId().takeLast(8)}@example.com"

    private fun shippingAddress(): JSONObject = JSONObject()
        .put("street", "123 Telescope Way")
        .put("city", "Mountain View")
        .put("state", "CA")
        .put("country", "US")
        .put("zip", "94043")

    private fun shippingAddressForOtel(): JSONObject = JSONObject()
        .put("streetAddress", "123 Telescope Way")
        .put("city", "Mountain View")
        .put("state", "CA")
        .put("country", "US")
        .put("zipCode", "94043")

    private fun creditCardForOtel(): JSONObject = JSONObject()
        .put("creditCardNumber", "4242424242424242")
        .put("creditCardCvv", 123)
        .put("creditCardExpirationYear", 2030)
        .put("creditCardExpirationMonth", 12)

    private fun cartFromOtel(): JSONObject {
        val cart = getObject(
            "/cart",
            queryParams = mapOf(
                "sessionId" to currentUserId(),
                "currencyCode" to DEFAULT_CURRENCY
            )
        )

        val items = cart.optJSONArray("items") ?: JSONArray()
        val mappedItems = JSONArray()
        var subtotal = 0.0

        for (index in 0 until items.length()) {
            val item = items.getJSONObject(index)
            val product = item.optJSONObject("product") ?: continue
            val productId = item.optString("productId", "")
            val quantity = item.optInt("quantity", 0)
            val unitPrice = cents(moneyToDouble(product.optJSONObject("priceUsd")))
            val lineTotal = cents(unitPrice * quantity)
            subtotal += lineTotal

            mappedItems.put(
                JSONObject()
                    .put("product_id", productId)
                    .put("name", product.optString("name", ""))
                    .put("quantity", quantity)
                    .put("unit_price", unitPrice)
                    .put("line_total", lineTotal)
                    .put("image_url", imageUrl(product.optString("picture", "")))
            )
        }

        val tax = cents(subtotal * TAX_RATE)
        val total = cents(subtotal + tax)

        return JSONObject()
            .put("user_id", cart.optString("userId", currentUserId()))
            .put("subtotal", cents(subtotal))
            .put("tax", tax)
            .put("total", total)
            .put("items", mappedItems)
    }

    private fun orderPreviewFromCart(cart: JSONObject): JSONObject = JSONObject()
        .put("subtotal", cart.optDouble("subtotal", 0.0))
        .put("tax", cart.optDouble("tax", 0.0))
        .put("total", cart.optDouble("total", 0.0))
        .put("item_count", cart.optJSONArray("items")?.length() ?: 0)

    private fun createCheckout(mode: String): JSONObject {
        val cart = cartFromOtel()
        val sessionId = UUID.randomUUID().toString()
        val email = if (mode == "signin") memberProfile().optString("email") else guestEmail()
        val snapshot = JSONObject()
            .put("checkout_session", sessionId)
            .put("user_id", currentUserId())
            .put("email", email)
            .put("mode", mode)
            .put("shipping_address", shippingAddress())
            .put("order_preview", orderPreviewFromCart(cart))

        if (mode == "signin") {
            snapshot.put("user", memberProfile())
        }

        writeStoredJson(checkoutKey(sessionId), snapshot)
        return snapshot
    }

    private fun totalFromCheckout(order: JSONObject): Double {
        val items = order.optJSONArray("items") ?: JSONArray()
        var itemsTotal = 0.0
        for (index in 0 until items.length()) {
            val item = items.getJSONObject(index)
            itemsTotal += moneyToDouble(item.optJSONObject("cost"))
        }
        return cents(itemsTotal + moneyToDouble(order.optJSONObject("shippingCost")))
    }

    private fun flattenOrderItems(items: JSONArray): JSONArray {
        val flattened = JSONArray()
        for (index in 0 until items.length()) {
            val entry = items.getJSONObject(index)
            val item = entry.optJSONObject("item") ?: continue
            val product = item.optJSONObject("product") ?: continue
            val quantity = item.optInt("quantity", 0)
            val unitPrice = cents(moneyToDouble(entry.optJSONObject("cost")) / quantity.coerceAtLeast(1))
            flattened.put(
                JSONObject()
                    .put("product_id", item.optString("productId", ""))
                    .put("name", product.optString("name", ""))
                    .put("quantity", quantity)
                    .put("unit_price", unitPrice)
                    .put("line_total", cents(moneyToDouble(entry.optJSONObject("cost"))))
                    .put("image_url", imageUrl(product.optString("picture", "")))
            )
        }
        return flattened
    }

    private fun buildConfirmation(
        order: JSONObject,
        paymentMethod: String,
        transactionId: String,
        email: String
    ): JSONObject {
        val trackingId = order.optString("shippingTrackingId", "")
        val delivery = LocalDate.now().plusDays(5).format(DateTimeFormatter.ISO_DATE)
        return JSONObject()
            .put("order_id", order.optString("orderId", ""))
            .put("transaction_id", transactionId)
            .put("payment_method", paymentMethod)
            .put("email", email)
            .put("total", totalFromCheckout(order))
            .put("items", flattenOrderItems(order.optJSONArray("items") ?: JSONArray()))
            .put("shipping_address", shippingAddress())
            .put(
                "shipping",
                JSONObject()
                    .put("estimated_delivery", delivery)
                    .put("tracking_number", trackingId)
            )
    }

    private fun pay(checkoutSession: String, paymentMethod: String, extraFields: JSONObject = JSONObject()): JSONObject {
        val snapshot = readStoredJson(checkoutKey(checkoutSession))
            ?: throw IllegalStateException("Unknown checkout session: $checkoutSession")

        val order = postObject(
            "/checkout",
            bodyJson = JSONObject()
                .put("userId", snapshot.optString("user_id"))
                .put("userCurrency", DEFAULT_CURRENCY)
                .put("address", shippingAddressForOtel())
                .put("email", snapshot.optString("email"))
                .put("creditCard", creditCardForOtel()),
            queryParams = mapOf("currencyCode" to DEFAULT_CURRENCY)
        )

        val orderId = order.optString("orderId", "")
        val transactionId = "txn-${UUID.randomUUID()}"
        val confirmation = buildConfirmation(order, paymentMethod, transactionId, snapshot.optString("email"))
        writeStoredJson(confirmationKey(orderId), confirmation)

        val payment = JSONObject()
            .put("order_id", orderId)
            .put("transaction_id", transactionId)
            .put("payment_method", paymentMethod)
            .put("amount_charged", totalFromCheckout(order))

        extraFields.keys().forEach { key ->
            payment.put(key, extraFields.get(key))
        }
        return payment
    }

    suspend fun getWelcome(): JSONObject = withContext(Dispatchers.IO) {
        JSONObject()
            .put("store_name", "Telescope Store")
            .put("tagline", "Explore the OpenTelemetry Demo catalog with your existing Bitdrift instrumentation")
            .put(
                "promotions",
                JSONArray().put(
                    JSONObject()
                        .put("title", "Now backed by the OpenTelemetry Demo services")
                )
            )
    }

    suspend fun getBrowse(): JSONObject = withContext(Dispatchers.IO) {
        JSONObject().put("products", listLegacyProducts())
    }

    suspend fun search(query: String): JSONObject = withContext(Dispatchers.IO) {
        val lowered = query.trim().lowercase(Locale.US)
        val products = listLegacyProducts()
        val filtered = JSONArray()
        for (index in 0 until products.length()) {
            val product = products.getJSONObject(index)
            val haystack = listOf(
                product.optString("name", ""),
                product.optString("description", ""),
                product.optString("category", "")
            ).joinToString(" ").lowercase(Locale.US)
            if (lowered.isBlank() || haystack.contains(lowered)) {
                filtered.put(product)
            }
        }
        JSONObject()
            .put("query", query)
            .put("products", filtered)
    }

    suspend fun getFeatured(): JSONObject = withContext(Dispatchers.IO) {
        val products = listLegacyProducts()
        val featured = JSONArray()
        for (index in 0 until minOf(4, products.length())) {
            featured.put(products.getJSONObject(index))
        }
        JSONObject()
            .put("banner", JSONObject().put("text", "Featured picks from the Telescope Store"))
            .put("featured_products", featured)
    }

    suspend fun getCategories(): JSONObject = withContext(Dispatchers.IO) {
        val products = listLegacyProducts()
        val seen = linkedSetOf<String>()
        val categories = JSONArray()
        for (index in 0 until products.length()) {
            val name = products.getJSONObject(index).optString("category", "Products")
            if (seen.add(name)) {
                categories.put(JSONObject().put("name", name))
            }
        }
        JSONObject().put("categories", categories)
    }

    suspend fun getCategoryProducts(category: String): JSONObject = withContext(Dispatchers.IO) {
        val products = listLegacyProducts()
        val filtered = JSONArray()
        for (index in 0 until products.length()) {
            val product = products.getJSONObject(index)
            if (product.optString("category", "").equals(category, ignoreCase = true)) {
                filtered.put(product)
            }
        }
        JSONObject()
            .put("category", category)
            .put("products", filtered)
    }

    suspend fun getProduct(productId: String): JSONObject = withContext(Dispatchers.IO) {
        productToLegacy(getOtelProduct(productId))
    }

    suspend fun getReviews(productId: String): JSONObject = withContext(Dispatchers.IO) {
        val reviews = getArray("/product-reviews/$productId")
        val mapped = JSONArray()
        for (index in 0 until reviews.length()) {
            val review = reviews.getJSONObject(index)
            val author = review.optString("username", "Anonymous")
            mapped.put(
                JSONObject()
                    .put("title", "Review by $author")
                    .put("author", author)
                    .put("rating", review.optString("score", "0").toIntOrNull() ?: 0)
                    .put("content", review.optString("description", ""))
            )
        }
        JSONObject().put("reviews", mapped)
    }

    suspend fun addToCart(productId: String, quantity: Int = 1): JSONObject = withContext(Dispatchers.IO) {
        postObject(
            "/cart",
            bodyJson = JSONObject()
                .put("userId", currentUserId())
                .put(
                    "item",
                    JSONObject()
                        .put("productId", productId)
                        .put("quantity", quantity)
                ),
            queryParams = mapOf("currencyCode" to DEFAULT_CURRENCY)
        )
        cartFromOtel()
    }

    suspend fun getCart(): JSONObject = withContext(Dispatchers.IO) {
        cartFromOtel()
    }

    suspend fun deleteCartItem(productId: String): JSONObject = withContext(Dispatchers.IO) {
        val cart = getObject("/cart", queryParams = mapOf("sessionId" to currentUserId(), "currencyCode" to DEFAULT_CURRENCY))
        val items = cart.optJSONArray("items") ?: JSONArray()
        deleteObject("/cart", bodyJson = JSONObject().put("userId", currentUserId()))
        for (index in 0 until items.length()) {
            val item = items.getJSONObject(index)
            if (item.optString("productId", "") != productId) {
                postObject(
                    "/cart",
                    bodyJson = JSONObject()
                        .put("userId", currentUserId())
                        .put(
                            "item",
                            JSONObject()
                                .put("productId", item.optString("productId", ""))
                                .put("quantity", item.optInt("quantity", 1))
                        ),
                    queryParams = mapOf("currencyCode" to DEFAULT_CURRENCY)
                )
            }
        }
        cartFromOtel()
    }

    suspend fun addToWishlist(productId: String): JSONObject = withContext(Dispatchers.IO) {
        val wishlistIds = currentWishlistIds()
        wishlistIds.add(productId)
        prefs.edit().putStringSet(WISHLIST_KEY, wishlistIds).apply()

        val items = JSONArray()
        wishlistIds.forEach { itemId ->
            items.put(productToLegacy(getOtelProduct(itemId)))
        }

        JSONObject()
            .put("item_count", items.length())
            .put("items", items)
    }

    suspend fun checkoutGuest(email: String = ""): JSONObject = withContext(Dispatchers.IO) {
        createCheckout(mode = "guest").apply {
            if (email.isNotBlank()) {
                put("email", email)
                writeStoredJson(checkoutKey(optString("checkout_session")), this)
            }
        }
    }

    suspend fun checkoutSignIn(email: String = ""): JSONObject = withContext(Dispatchers.IO) {
        createCheckout(mode = "signin").apply {
            if (email.isNotBlank()) {
                val user = optJSONObject("user") ?: JSONObject()
                user.put("email", email)
                put("email", email)
                put("user", user)
                writeStoredJson(checkoutKey(optString("checkout_session")), this)
            }
        }
    }

    suspend fun payCard(checkoutSession: String, cardLast4: String = "4242"): JSONObject = withContext(Dispatchers.IO) {
        pay(
            checkoutSession = checkoutSession,
            paymentMethod = "Card",
            extraFields = JSONObject().put("card_last4", cardLast4)
        )
    }

    suspend fun payApplePay(checkoutSession: String): JSONObject = withContext(Dispatchers.IO) {
        pay(checkoutSession = checkoutSession, paymentMethod = "Apple Pay")
    }

    suspend fun payPayPal(checkoutSession: String): JSONObject = withContext(Dispatchers.IO) {
        pay(
            checkoutSession = checkoutSession,
            paymentMethod = "PayPal",
            extraFields = JSONObject().put("paypal_reference", "PP-${UUID.randomUUID().toString().take(10).uppercase(Locale.US)}")
        )
    }

    suspend fun payAndroidPay(checkoutSession: String): JSONObject = withContext(Dispatchers.IO) {
        pay(checkoutSession = checkoutSession, paymentMethod = "Android Pay")
    }

    suspend fun getConfirmation(orderId: String): JSONObject = withContext(Dispatchers.IO) {
        readStoredJson(confirmationKey(orderId)) ?: JSONObject().put("order_id", orderId)
    }

    suspend fun getFullCatalogJson(): String = withContext(Dispatchers.IO) {
        val result = getBrowse()
        val arr = result.optJSONArray("products")
        arr?.toString() ?: "[]"
    }

    suspend fun inventoryLookup(item: String): JSONObject = withContext(Dispatchers.IO) {
        val hex = "0123456789abcdef"
        val session = buildString { repeat(16) { append(hex.random()) } }
        requestInventoryLookup("/inventory/lookup/${item}/${session}")
    }
}
