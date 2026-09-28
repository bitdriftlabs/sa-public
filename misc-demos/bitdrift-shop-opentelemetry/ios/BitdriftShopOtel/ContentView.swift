import SwiftUI

/// Root navigation host -- mirrors `MainActivity.kt`'s `ShoppingDemoContent` `NavHost`. Welcome
/// is the stack root (not itself a `Screen` case, matching how it's the `startDestination` on
/// Android); every other screen is a `navigationDestination` case.
struct ContentView: View {
    @StateObject private var router = Router()
    @StateObject private var simulationManager = SimulationManager()

    var body: some View {
        NavigationStack(path: $router.path) {
            WelcomeScreen(simulationManager: simulationManager)
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .browse:
                        BrowseScreen(simulationManager: simulationManager)
                    case .search:
                        SearchScreen()
                    case .featuredProducts:
                        FeaturedProductsScreen()
                    case .categories:
                        CategoriesScreen()
                    case let .categoryBrowse(category):
                        CategoryBrowseScreen(category: category)
                    case let .productDetail(source, productId):
                        ProductDetailScreen(source: source, productId: productId, simulationManager: simulationManager)
                    case let .reviews(source, productId):
                        ReviewsScreen(source: source, productId: productId)
                    case let .cart(productId):
                        CartScreen(productId: productId)
                    case let .wishlist(productId):
                        WishlistScreen(productId: productId)
                    case let .checkoutGuest(productId):
                        CheckoutGuestScreen(productId: productId)
                    case let .checkoutSignIn(productId):
                        CheckoutSignInScreen(productId: productId)
                    case let .paymentCard(checkoutSession):
                        PaymentCardScreen(checkoutSession: checkoutSession)
                    case let .paymentApplePay(checkoutSession):
                        PaymentApplePayScreen(checkoutSession: checkoutSession)
                    case let .paymentPayPal(checkoutSession):
                        PaymentPayPalScreen(checkoutSession: checkoutSession)
                    case let .paymentAndroidPay(checkoutSession):
                        PaymentAndroidPayScreen(checkoutSession: checkoutSession)
                    case let .paymentFailed(paymentMethod, checkoutSession):
                        PaymentFailedScreen(paymentMethod: paymentMethod, checkoutSession: checkoutSession)
                    case let .confirmation(orderId):
                        ConfirmationScreen(orderId: orderId)
                    }
                }
        }
        .environmentObject(router)
        .overlay(alignment: .bottom) {
            if simulationManager.isSimulating {
                SimulationOverlay(simulationManager: simulationManager)
            }
        }
    }
}
