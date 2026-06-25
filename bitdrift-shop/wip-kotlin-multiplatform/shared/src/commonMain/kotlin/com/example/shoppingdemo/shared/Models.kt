package ai.bitdrift.shop.shared

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProductCard(
    val id: String = "",
    val name: String = "",
    val price: Double = 0.0,
    @SerialName("image_url") val imageUrl: String = "",
    val category: String = "",
    val brand: String = ""
)

@Serializable
data class CartItem(
    @SerialName("product_id") val productId: String = "",
    val name: String = "",
    val quantity: Int = 0,
    @SerialName("unit_price") val unitPrice: Double = 0.0,
    @SerialName("line_total") val lineTotal: Double = 0.0
)

@Serializable
data class Category(
    val name: String = "",
    @SerialName("product_count") val productCount: Int = 0,
    val icon: String = ""
)

@Serializable
data class Review(
    val rating: Int = 0,
    val title: String = "",
    val body: String = "",
    val author: String = ""
)

@Serializable
data class WelcomeResponse(
    @SerialName("store_name") val storeName: String = "",
    val tagline: String = "",
    val promotions: List<Promotion> = emptyList()
)

@Serializable
data class Promotion(
    val title: String = "",
    val subtitle: String = ""
)

@Serializable
data class BrowseResponse(
    val products: List<ProductCard> = emptyList(),
    @SerialName("total_products") val totalProducts: Int = 0
)

@Serializable
data class SearchResponse(
    val query: String = "",
    val products: List<ProductCard> = emptyList(),
    @SerialName("result_count") val resultCount: Int = 0
)

@Serializable
data class FeaturedResponse(
    @SerialName("featured_products") val featuredProducts: List<ProductCard> = emptyList(),
    val banner: Banner? = null
)

@Serializable
data class Banner(
    val text: String = ""
)

@Serializable
data class CategoriesResponse(
    val categories: List<Category> = emptyList()
)

@Serializable
data class CategoryProductsResponse(
    val category: String = "",
    val products: List<ProductCard> = emptyList()
)

@Serializable
data class ProductDetailResponse(
    val id: String = "",
    val name: String = "",
    val price: Double = 0.0,
    val brand: String = "",
    val description: String = "",
    val images: List<String> = emptyList(),
    @SerialName("stock_count") val stockCount: Int = 0,
    val category: String = ""
)

@Serializable
data class ReviewsResponse(
    @SerialName("product_id") val productId: String = "",
    @SerialName("average_rating") val averageRating: Double = 0.0,
    @SerialName("total_reviews") val totalReviews: Int = 0,
    val reviews: List<Review> = emptyList()
)

@Serializable
data class CartResponse(
    val items: List<CartItem> = emptyList(),
    val total: Double = 0.0,
    val tax: Double = 0.0,
    @SerialName("item_count") val itemCount: Int = 0
)

@Serializable
data class WishlistResponse(
    @SerialName("item_count") val itemCount: Int = 0,
    val items: List<WishlistItem> = emptyList()
)

@Serializable
data class WishlistItem(
    val name: String = "",
    @SerialName("product_id") val productId: String = ""
)

@Serializable
data class CheckoutResponse(
    @SerialName("checkout_session") val checkoutSession: String = "",
    val email: String = "",
    @SerialName("shipping_address") val shippingAddress: ShippingAddress? = null,
    @SerialName("order_preview") val orderPreview: OrderPreview? = null,
    val user: CheckoutUser? = null
)

@Serializable
data class ShippingAddress(
    val city: String = "",
    val state: String = "",
    val zip: String = ""
)

@Serializable
data class OrderPreview(
    val total: Double = 0.0
)

@Serializable
data class CheckoutUser(
    val name: String = "",
    val email: String = "",
    @SerialName("loyalty_points") val loyaltyPoints: Int = 0
)

@Serializable
data class PaymentResponse(
    @SerialName("order_id") val orderId: String = "",
    @SerialName("transaction_id") val transactionId: String = "",
    @SerialName("payment_method") val paymentMethod: String = "",
    @SerialName("amount_charged") val amountCharged: Double = 0.0,
    @SerialName("paypal_reference") val paypalReference: String = ""
)

@Serializable
data class ConfirmationResponse(
    @SerialName("order_id") val orderId: String = "",
    @SerialName("transaction_id") val transactionId: String = "",
    val total: Double = 0.0,
    val shipping: ShippingInfo? = null
)

@Serializable
data class ShippingInfo(
    @SerialName("estimated_delivery") val estimatedDelivery: String = "",
    @SerialName("tracking_number") val trackingNumber: String = ""
)
