package ai.bitdrift.shop

import ai.bitdrift.shop.generated.*

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
    data object Welcome : Screen(SpecScreen.WELCOME.route)
    data object Advanced : Screen(SpecScreen.ADVANCED.route)

    // Step 2 branches
    data object Browse : Screen(SpecScreen.BROWSE.route)
    data object Search : Screen(SpecScreen.SEARCH.route)

    // Step 3 branches
    data object FeaturedProducts : Screen(SpecScreen.FEATURED.route)
    data object Categories : Screen(SpecScreen.CATEGORIES.route)
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
        val PRODUCT_DETAIL_ROUTE = SpecScreen.PRODUCT_DETAIL.route
        val CATEGORY_BROWSE_ROUTE = SpecScreen.CATEGORY_BROWSE.route
        val REVIEWS_ROUTE = SpecScreen.REVIEWS.route
        val CART_ROUTE = SpecScreen.CART.route
        val WISHLIST_ROUTE = SpecScreen.WISHLIST.route
        val CHECKOUT_GUEST_ROUTE = SpecScreen.CHECKOUT_GUEST.route
        val CHECKOUT_SIGNIN_ROUTE = SpecScreen.CHECKOUT_SIGNIN.route
        val PAYMENT_CARD_ROUTE = SpecScreen.PAYMENT_CARD.route
        val PAYMENT_APPLEPAY_ROUTE = SpecScreen.PAYMENT_APPLE_PAY.route
        val PAYMENT_PAYPAL_ROUTE = SpecScreen.PAYMENT_PAYPAL.route
        val PAYMENT_ANDROIDPAY_ROUTE = SpecScreen.PAYMENT_ANDROID_PAY.route
        val PAYMENT_FAILED_ROUTE = SpecScreen.PAYMENT_FAILED.route
        val CONFIRMATION_ROUTE = SpecScreen.CONFIRMATION.route
    }
}
