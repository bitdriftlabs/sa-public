package com.example.shoppingdemo

import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.shoppingdemo.ui.theme.ShoppingdemoTheme
import io.bitdrift.capture.Capture.Logger
import kotlin.time.Duration.Companion.milliseconds

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            ShoppingdemoTheme {
                ShoppingDemoContent()
            }
        }

        // Workshop 3 — App Launch TTI (android, basic sdk)
        // https://github.com/nicholasgasior/bitdrift → workshop-301.md § "3 — App Launch TTI"
        // Report time-to-interactive once the first frame is drawn.
        // Only the first call per Logger.start() takes effect.
        // Uses reportFullyDrawn() as the Android reference point, paired with
        // a post-first-frame callback so the measurement reflects real user-visible readiness.
        val contentView = findViewById<android.view.View>(android.R.id.content)
        contentView.post {
            val ttiMs = SystemClock.uptimeMillis() - ShoppingDemoApp.appStartUptimeMs
            Logger.logAppLaunchTTI(ttiMs.milliseconds)
            reportFullyDrawn()
        }
    }
}

@Composable
fun ShoppingDemoContent() {
    val navController = rememberNavController()
    val simulationManager: SimulationManager = viewModel()
    val context = androidx.compose.ui.platform.LocalContext.current
    val anrPrefs = remember {
        context.getSharedPreferences(SimulationManager.ANR_PREFS_NAME, android.content.Context.MODE_PRIVATE)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(
            navController = navController,
            startDestination = Screen.Welcome.route
        ) {
            composable(Screen.Welcome.route) {
                WelcomeScreen(navController, simulationManager)
                LaunchedEffect(Unit) {
                    simulationManager.syncAnrAEnabledState()
                            val restartPending = anrPrefs.getBoolean("restart_pending", false)

                            if (restartPending) {
                                val resumeInfinite = anrPrefs.getBoolean("resume_infinite", false)
                                anrPrefs.edit()
                                    .putBoolean("restart_pending", false)
                                    .putBoolean("resume_infinite", false)
                                    .commit()
                                simulationManager.restoreVariantFromPrefs()
                                ScreenLogger.logInfo(
                                    "anr_restart_resume",
                                    mapOf("mode" to if (resumeInfinite) "infinite" else "single")
                                )
                                if (resumeInfinite) {
                                    simulationManager.scheduleAutoStartInfinite()
                                } else {
                                    simulationManager.scheduleAutoStart()
                                }
                            }
                            simulationManager.tryAutoStart(navController)
                        }
                    }

                    // Step 2
                    composable(Screen.Browse.route) {
                        BrowseScreen(navController, simulationManager)
                    }
                    composable(Screen.Search.route) {
                        SearchScreen(navController)
                    }

                    // Step 3
                    composable(Screen.FeaturedProducts.route) {
                        FeaturedProductsScreen(navController)
                    }
                    composable(Screen.Categories.route) {
                        CategoriesScreen(navController)
                    }

                    // Step 3b: Category Browse (with category name)
                    composable(
                        route = Screen.CATEGORY_BROWSE_ROUTE,
                        arguments = listOf(navArgument("category") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val category = backStackEntry.arguments?.getString("category")
                        CategoryBrowseScreen(navController, category)
                    }

                    // Step 4 (with source + productId)
                    composable(
                        route = Screen.PRODUCT_DETAIL_ROUTE,
                        arguments = listOf(
                            navArgument("source") { type = NavType.StringType },
                            navArgument("productId") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val source = backStackEntry.arguments?.getString("source")
                        val productId = backStackEntry.arguments?.getString("productId")
                        ProductDetailScreen(navController, source, productId, simulationManager)
                    }
                    composable(
                        route = Screen.REVIEWS_ROUTE,
                        arguments = listOf(
                            navArgument("source") { type = NavType.StringType },
                            navArgument("productId") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val source = backStackEntry.arguments?.getString("source")
                        val productId = backStackEntry.arguments?.getString("productId")
                        ReviewsScreen(navController, source, productId)
                    }

                    // Step 5 (with productId)
                    composable(
                        route = Screen.CART_ROUTE,
                        arguments = listOf(navArgument("productId") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val productId = backStackEntry.arguments?.getString("productId")
                        CartScreen(navController, productId)
                    }
                    composable(
                        route = Screen.WISHLIST_ROUTE,
                        arguments = listOf(navArgument("productId") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val productId = backStackEntry.arguments?.getString("productId")
                        WishlistScreen(navController, productId)
                    }

                    // Step 6 (with productId)
                    composable(
                        route = Screen.CHECKOUT_GUEST_ROUTE,
                        arguments = listOf(navArgument("productId") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val productId = backStackEntry.arguments?.getString("productId")
                        CheckoutGuestScreen(navController, productId)
                    }
                    composable(
                        route = Screen.CHECKOUT_SIGNIN_ROUTE,
                        arguments = listOf(navArgument("productId") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val productId = backStackEntry.arguments?.getString("productId")
                        CheckoutSignInScreen(navController, productId)
                    }

                    // Step 7 - Payment methods (with checkoutSession)
                    composable(
                        route = Screen.PAYMENT_CARD_ROUTE,
                        arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                        PaymentCardScreen(navController, checkoutSession)
                    }
                    composable(
                        route = Screen.PAYMENT_APPLEPAY_ROUTE,
                        arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                        PaymentApplePayScreen(navController, checkoutSession)
                    }
                    composable(
                        route = Screen.PAYMENT_PAYPAL_ROUTE,
                        arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                        PaymentPayPalScreen(navController, checkoutSession)
                    }
                    composable(
                        route = Screen.PAYMENT_ANDROIDPAY_ROUTE,
                        arguments = listOf(navArgument("checkoutSession") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                        PaymentAndroidPayScreen(navController, checkoutSession)
                    }

                    // Payment failure (with paymentMethod + checkoutSession)
                    composable(
                        route = Screen.PAYMENT_FAILED_ROUTE,
                        arguments = listOf(
                            navArgument("paymentMethod") { type = NavType.StringType },
                            navArgument("checkoutSession") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val paymentMethod = backStackEntry.arguments?.getString("paymentMethod")
                        val checkoutSession = backStackEntry.arguments?.getString("checkoutSession")
                        PaymentFailedScreen(navController, paymentMethod, checkoutSession)
                    }

                    // Final step (with orderId)
                    composable(
                        route = Screen.CONFIRMATION_ROUTE,
                        arguments = listOf(navArgument("orderId") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val orderId = backStackEntry.arguments?.getString("orderId")
                        ConfirmationScreen(navController, orderId)
                    }
                }

                // Floating simulation overlay - visible on all screens during simulation
                if (simulationManager.isSimulating) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(bottom = 16.dp),
                        contentAlignment = Alignment.BottomCenter
                    ) {
                        SimulationOverlay(simulationManager)
                    }
                }
            }
}

