package ai.bitdrift.shop

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import ai.bitdrift.shop.shared.AppScreen

@Composable
fun ShoppingDemoContent() {
    val navController = rememberNavController()
    val simulationViewModel: SimulationViewModel = viewModel()
    val isSimulating by simulationViewModel.isSimulating.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(
            navController = navController,
            startDestination = AppScreen.Welcome.route
        ) {
            composable(AppScreen.Welcome.route) {
                WelcomeScreen(navController, simulationViewModel)
            }
            composable(AppScreen.Browse.route) {
                BrowseScreen(navController)
            }
            composable(AppScreen.Search.route) {
                SearchScreen(navController)
            }
            composable(AppScreen.FeaturedProducts.route) {
                FeaturedProductsScreen(navController)
            }
            composable(AppScreen.Categories.route) {
                CategoriesScreen(navController)
            }
            composable(
                route = AppScreen.CATEGORY_BROWSE_ROUTE,
                arguments = listOf(navArgument("category") { type = NavType.StringType })
            ) { backStackEntry ->
                val category = backStackEntry.arguments?.getString("category")
                CategoryBrowseScreen(navController, category)
            }
            composable(
                route = AppScreen.PRODUCT_DETAIL_ROUTE,
                arguments = listOf(
                    navArgument("source") { type = NavType.StringType },
                    navArgument("productId") { type = NavType.StringType }
                )
            ) { backStackEntry ->
                val source = backStackEntry.arguments?.getString("source")
                val productId = backStackEntry.arguments?.getString("productId")
                ProductDetailScreen(navController, source, productId)
            }
            composable(
                route = AppScreen.REVIEWS_ROUTE,
                arguments = listOf(
                    navArgument("source") { type = NavType.StringType },
                    navArgument("productId") { type = NavType.StringType }
                )
            ) { backStackEntry ->
                val source = backStackEntry.arguments?.getString("source")
                val productId = backStackEntry.arguments?.getString("productId")
                ReviewsScreen(navController, source, productId)
            }
            composable(
                route = AppScreen.CART_ROUTE,
                arguments = listOf(navArgument("productId") { type = NavType.StringType })
            ) { backStackEntry ->
                val productId = backStackEntry.arguments?.getString("productId")
                CartScreen(navController, productId)
            }
            composable(
                route = AppScreen.WISHLIST_ROUTE,
                arguments = listOf(navArgument("productId") { type = NavType.StringType })
            ) { backStackEntry ->
                val productId = backStackEntry.arguments?.getString("productId")
                WishlistScreen(navController, productId)
            }
            composable(
                route = AppScreen.CHECKOUT_GUEST_ROUTE,
                arguments = listOf(navArgument("productId") { type = NavType.StringType })
            ) { backStackEntry ->
                val productId = backStackEntry.arguments?.getString("productId")
                CheckoutGuestScreen(navController, productId)
            }
            composable(
                route = AppScreen.CHECKOUT_SIGNIN_ROUTE,
                arguments = listOf(navArgument("productId") { type = NavType.StringType })
            ) { backStackEntry ->
                val productId = backStackEntry.arguments?.getString("productId")
                CheckoutSignInScreen(navController, productId)
            }
            composable(
                route = AppScreen.PAYMENT_CARD_ROUTE,
                arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
            ) { backStackEntry ->
                val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                PaymentCardScreen(navController, checkoutSession)
            }
            composable(
                route = AppScreen.PAYMENT_APPLEPAY_ROUTE,
                arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
            ) { backStackEntry ->
                val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                PaymentApplePayScreen(navController, checkoutSession)
            }
            composable(
                route = AppScreen.PAYMENT_PAYPAL_ROUTE,
                arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
            ) { backStackEntry ->
                val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                PaymentPayPalScreen(navController, checkoutSession)
            }
            composable(
                route = AppScreen.CONFIRMATION_ROUTE,
                arguments = listOf(navArgument("orderId") { type = NavType.StringType })
            ) { backStackEntry ->
                val orderId = backStackEntry.arguments?.getString("orderId")
                ConfirmationScreen(navController, orderId)
            }
        }

        if (isSimulating) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = 16.dp),
                contentAlignment = Alignment.BottomCenter
            ) {
                SimulationOverlay(simulationViewModel)
            }
        }
    }
}
