package ai.bitdrift.shop.shared

/**
 * Navigation screen definitions mirroring the 16-screen shopping flow.
 */
sealed class AppScreen(val route: String) {
    data object Welcome : AppScreen("welcome")
    data object Browse : AppScreen("browse")
    data object Search : AppScreen("search")
    data object FeaturedProducts : AppScreen("featured")
    data object Categories : AppScreen("categories")
    data class CategoryBrowse(val category: String) : AppScreen("categoryBrowse/$category")
    data class ProductDetail(val source: String, val productId: String = "") : AppScreen("productDetail/$source/$productId")
    data class Reviews(val source: String, val productId: String = "") : AppScreen("reviews/$source/$productId")
    data class Cart(val productId: String = "") : AppScreen("cart/$productId")
    data class Wishlist(val productId: String = "") : AppScreen("wishlist/$productId")
    data class CheckoutGuest(val productId: String = "") : AppScreen("checkoutGuest/$productId")
    data class CheckoutSignIn(val productId: String = "") : AppScreen("checkoutSignIn/$productId")
    data class PaymentCard(val checkoutSession: String = "") : AppScreen("paymentCard/$checkoutSession")
    data class PaymentApplePay(val checkoutSession: String = "") : AppScreen("paymentApplePay/$checkoutSession")
    data class PaymentPayPal(val checkoutSession: String = "") : AppScreen("paymentPayPal/$checkoutSession")
    data class PaymentAndroidPay(val checkoutSession: String = "") : AppScreen("paymentAndroidPay/$checkoutSession")
    data class PaymentFailed(val paymentMethod: String = "") : AppScreen("paymentFailed/$paymentMethod")
    data class Confirmation(val orderId: String = "") : AppScreen("confirmation/$orderId")
    data object Advanced : AppScreen("advanced")

    companion object {
        const val PRODUCT_DETAIL_ROUTE = "productDetail/{source}/{productId}"
        const val CATEGORY_BROWSE_ROUTE = "categoryBrowse/{category}"
        const val REVIEWS_ROUTE = "reviews/{source}/{productId}"
        const val CART_ROUTE = "cart/{productId}"
        const val WISHLIST_ROUTE = "wishlist/{productId}"
        const val CHECKOUT_GUEST_ROUTE = "checkoutGuest/{productId}"
        const val CHECKOUT_SIGNIN_ROUTE = "checkoutSignIn/{productId}"
        const val PAYMENT_CARD_ROUTE = "paymentCard/{checkoutSession}"
        const val PAYMENT_APPLEPAY_ROUTE = "paymentApplePay/{checkoutSession}"
        const val PAYMENT_PAYPAL_ROUTE = "paymentPayPal/{checkoutSession}"
        const val PAYMENT_ANDROIDPAY_ROUTE = "paymentAndroidPay/{checkoutSession}"
        const val PAYMENT_FAILED_ROUTE = "paymentFailed/{paymentMethod}"
        const val CONFIRMATION_ROUTE = "confirmation/{orderId}"
    }
}
