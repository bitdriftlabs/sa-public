package com.example.shoppingdemo.shared

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json

/**
 * Shared HTTP client for the ShopDemo backend API using Ktor.
 * Platform-specific engine is provided via expect/actual (see HttpClientFactory.*).
 */
object ApiClient {

    private val baseUrl: String by lazy { platformBaseUrl() }

    internal val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    private val client = createPlatformHttpClient(json)

    // ---- GET helpers ----

    private suspend inline fun <reified T> get(path: String): T {
        val response: HttpResponse = client.get("$baseUrl$path")
        return response.body()
    }

    private suspend inline fun <reified T> post(path: String, body: Any? = null): T {
        val response: HttpResponse = client.post("$baseUrl$path") {
            contentType(ContentType.Application.Json)
            if (body != null) {
                setBody(body)
            } else {
                setBody("{}")
            }
        }
        return response.body()
    }

    private suspend inline fun <reified T> delete(path: String): T {
        val response: HttpResponse = client.delete("$baseUrl$path")
        return response.body()
    }

    // ---- Public API ----

    suspend fun getWelcome(): WelcomeResponse = get("/welcome")

    suspend fun getBrowse(): BrowseResponse = get("/browse")

    suspend fun search(query: String = ""): SearchResponse = get("/search?q=$query")

    suspend fun getFeatured(): FeaturedResponse = get("/featured")

    suspend fun getCategories(): CategoriesResponse = get("/categories")

    suspend fun getCategoryProducts(category: String): CategoryProductsResponse =
        get("/categories/$category")

    suspend fun getProduct(productId: String): ProductDetailResponse =
        get("/product/$productId")

    suspend fun getReviews(productId: String): ReviewsResponse =
        get("/product/$productId/reviews")

    suspend fun addToCart(productId: String, quantity: Int = 1): CartResponse =
        post("/cart", mapOf("product_id" to productId, "quantity" to quantity))

    suspend fun getCart(): CartResponse = get("/cart")

    suspend fun deleteCartItem(productId: String): CartResponse =
        delete("/cart/$productId")

    suspend fun addToWishlist(productId: String): WishlistResponse =
        post("/wishlist", mapOf("product_id" to productId))

    suspend fun checkoutGuest(email: String = ""): CheckoutResponse =
        post("/checkout/guest", mapOf("email" to email))

    suspend fun checkoutSignIn(email: String = ""): CheckoutResponse =
        post("/checkout/signin", mapOf("email" to email))

    suspend fun payCard(checkoutSession: String, cardLast4: String = "4242"): PaymentResponse =
        post("/payment/card", mapOf("checkout_session" to checkoutSession, "card_last4" to cardLast4))

    suspend fun payApplePay(checkoutSession: String): PaymentResponse =
        post("/payment/applepay", mapOf("checkout_session" to checkoutSession))

    suspend fun payPayPal(checkoutSession: String): PaymentResponse =
        post("/payment/paypal", mapOf("checkout_session" to checkoutSession))

    suspend fun getConfirmation(orderId: String): ConfirmationResponse =
        get("/confirmation/$orderId")
}
