import SwiftUI
import Shared

struct ContentView: View {
    @StateObject private var simulationState = SimulationState()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            WelcomeScreenView(simulationState: simulationState)
                .navigationDestination(for: ScreenRoute.self) { route in
                    screenView(for: route)
                }
        }
        .overlay(alignment: .bottom) {
            if simulationState.isSimulating {
                SimulationOverlayView(simulationState: simulationState)
                    .padding(.bottom, 16)
            }
        }
        .environmentObject(simulationState)
        .onReceive(simulationState.$navigationRoute) { route in
            guard let route = route else { return }
            simulationState.navigationRoute = nil
            if route == "welcome_clear" {
                navigationPath = NavigationPath()
            } else {
                navigationPath.append(ScreenRoute(route: route))
            }
        }
    }

    @ViewBuilder
    private func screenView(for route: ScreenRoute) -> some View {
        let parts = route.route.split(separator: "/").map(String.init)
        let base = parts.first ?? ""

        switch base {
        case "browse":
            BrowseScreenView()
        case "search":
            SearchScreenView()
        case "featured":
            FeaturedProductsScreenView()
        case "categories":
            CategoriesScreenView()
        case "categoryBrowse":
            CategoryBrowseScreenView(category: parts.count > 1 ? parts[1] : "Electronics")
        case "productDetail":
            ProductDetailScreenView(
                source: parts.count > 1 ? parts[1] : "browse",
                productId: parts.count > 2 ? parts[2] : "prod_a1b2c3"
            )
        case "reviews":
            ReviewsScreenView(
                source: parts.count > 1 ? parts[1] : "browse",
                productId: parts.count > 2 ? parts[2] : "prod_a1b2c3"
            )
        case "cart":
            CartScreenView(productId: parts.count > 1 ? parts[1] : "")
        case "wishlist":
            WishlistScreenView(productId: parts.count > 1 ? parts[1] : "prod_a1b2c3")
        case "checkoutGuest":
            CheckoutGuestScreenView(productId: parts.count > 1 ? parts[1] : "")
        case "checkoutSignIn":
            CheckoutSignInScreenView(productId: parts.count > 1 ? parts[1] : "")
        case "paymentCard":
            PaymentCardScreenView(checkoutSession: parts.count > 1 ? parts[1] : "")
        case "paymentApplePay":
            PaymentApplePayScreenView(checkoutSession: parts.count > 1 ? parts[1] : "")
        case "paymentPayPal":
            PaymentPayPalScreenView(checkoutSession: parts.count > 1 ? parts[1] : "")
        case "confirmation":
            ConfirmationScreenView(orderId: parts.count > 1 ? parts[1] : "")
        default:
            Text("Unknown screen: \(route.route)")
        }
    }
}

struct ScreenRoute: Hashable {
    let route: String
}
