package ai.bitdrift.shop

/**
 * Navigation Path - sealed class representing all screens in the app.
 *
 * Step 1: Welcome, Advanced
 * Step 2: Browse, Search
 * Step 3: Featured, Categories
 * Step 4: ProductDetail, Reviews
 * Step 5: Cart, Wishlist
 * Step 6: CheckoutGuest, CheckoutSignIn
 * Step 6: PaymentCard, PaymentApplePay, PaymentPayPal, PaymentAndroidPay
 * Step 7: Confirmation
 */
sealed class Screen(val route: String) {
    // Step 1
    data object Welcome : Screen("welcome")
    data object Advanced : Screen("advanced")

    // Step 2 branches
    data object Browse : Screen("browse")
    data object Search : Screen("search")

    // Step 3 branches
    data object FeaturedProducts : Screen("featured")
    data object Categories : Screen("categories")
    data class CategoryBrowse(val category: String) : Screen("categoryBrowse/$category")

    // Step 4 branches (source = featured|categories, productId passed from browse list)
    data class ProductDetail(val source: String, val productId: String = "") : Screen("productDetail/$source/$productId")
    data class Reviews(val source: String, val productId: String = "") : Screen("reviews/$source/$productId")

    // Step 5 branches (carry productId for cart/wishlist API call)
    data class Cart(val productId: String = "") : Screen("cart/$productId")
    data class Wishlist(val productId: String = "") : Screen("wishlist/$productId")

    // Step 6 branches (carry productId for checkout context)
    data class CheckoutGuest(val productId: String = "") : Screen("checkoutGuest/$productId")
    data class CheckoutSignIn(val productId: String = "") : Screen("checkoutSignIn/$productId")

    // Step 7 branches (carry checkoutSession for payment)
    data class PaymentCard(val checkoutSession: String = "") : Screen("paymentCard/$checkoutSession")
    data class PaymentApplePay(val checkoutSession: String = "") : Screen("paymentApplePay/$checkoutSession")
    data class PaymentPayPal(val checkoutSession: String = "") : Screen("paymentPayPal/$checkoutSession")
    data class PaymentAndroidPay(val checkoutSession: String = "") : Screen("paymentAndroidPay/$checkoutSession")

    // Payment failure (carry paymentMethod + checkoutSession for retry context)
    data class PaymentFailed(val paymentMethod: String = "", val checkoutSession: String = "") : Screen("paymentFailed/$paymentMethod/$checkoutSession")

    // Final step (carry orderId for confirmation)
    data class Confirmation(val orderId: String = "") : Screen("confirmation/$orderId")

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
        const val PAYMENT_FAILED_ROUTE = "paymentFailed/{paymentMethod}/{checkoutSession}"
        const val CONFIRMATION_ROUTE = "confirmation/{orderId}"
    }
}
