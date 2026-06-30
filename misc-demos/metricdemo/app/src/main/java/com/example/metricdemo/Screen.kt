package com.example.metricdemo

/**
 * Navigation Path - sealed class representing all screens in the app.
 *
 * Step 1: Welcome
 * Step 2: Browse, Search
 * Step 3: Featured, Categories
 * Step 4: ProductDetail, Reviews
 * Step 5: Cart, Wishlist
 * Step 6: CheckoutGuest, CheckoutSignIn
 * Step 6: PaymentCard, PaymentApplePay, PaymentPayPal
 * Step 7: Confirmation
 */
sealed class Screen(val route: String) {
    // Step 1
    data object Welcome : Screen("welcome")

    // Step 2 branches
    data object Browse : Screen("browse")
    data object Search : Screen("search")

    // Step 3 branches
    data object FeaturedProducts : Screen("featured")
    data object Categories : Screen("categories")

    // Step 4 branches
    data class ProductDetail(val source: String) : Screen("productDetail/$source")
    data class Reviews(val source: String) : Screen("reviews/$source")

    // Step 5 branches
    data object Cart : Screen("cart")
    data object Wishlist : Screen("wishlist")

    // Step 6 branches
    data object CheckoutGuest : Screen("checkoutGuest")
    data object CheckoutSignIn : Screen("checkoutSignIn")

    // Step 7 branches (all converge to confirmation)
    data object PaymentCard : Screen("paymentCard")
    data object PaymentApplePay : Screen("paymentApplePay")
    data object PaymentPayPal : Screen("paymentPayPal")

    // Final step
    data object Confirmation : Screen("confirmation")

    companion object {
        const val PRODUCT_DETAIL_ROUTE = "productDetail/{source}"
        const val REVIEWS_ROUTE = "reviews/{source}"
    }
}
