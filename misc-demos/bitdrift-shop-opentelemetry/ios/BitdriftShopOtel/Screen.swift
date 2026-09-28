import Foundation

/// Navigation destinations — mirrors Android's `Screen.kt` sealed class one-for-one, minus the
/// route-string plumbing (SwiftUI's `NavigationStack` pushes typed values directly).
///
/// Step 1: Welcome
/// Step 2: Browse, Search
/// Step 3: Featured, Categories
/// Step 3b: CategoryBrowse
/// Step 4: ProductDetail, Reviews
/// Step 5: Cart, Wishlist
/// Step 6: CheckoutGuest, CheckoutSignIn, PaymentCard, PaymentApplePay, PaymentPayPal, PaymentAndroidPay
/// Step 6 (failure): PaymentFailed
/// Step 7: Confirmation
enum Screen: Hashable {
    case browse
    case search
    case featuredProducts
    case categories
    case categoryBrowse(category: String)
    case productDetail(source: String, productId: String?)
    case reviews(source: String, productId: String?)
    case cart(productId: String?)
    case wishlist(productId: String?)
    case checkoutGuest(productId: String?)
    case checkoutSignIn(productId: String?)
    case paymentCard(checkoutSession: String?)
    case paymentApplePay(checkoutSession: String?)
    case paymentPayPal(checkoutSession: String?)
    case paymentAndroidPay(checkoutSession: String?)
    case paymentFailed(paymentMethod: String?, checkoutSession: String?)
    case confirmation(orderId: String?)
}
