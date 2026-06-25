package ai.bitdrift.shop

import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import ai.bitdrift.shop.ui.theme.ShoppingdemoTheme
import io.bitdrift.capture.Capture.Logger
import kotlinx.coroutines.delay
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

        // bitdrift SDK: logAppLaunchTTI() reports time-to-interactive from process start to first frame.
        // Only the first call per Logger.start() takes effect.
        // POC: event tracking — unsampled p50/p95/p99 TTI histogram across the full user population
        val contentView = findViewById<android.view.View>(android.R.id.content)
        contentView.post {
            val ttiMs = SystemClock.uptimeMillis() - ShoppingDemoApp.appStartUptimeMs
            Logger.logAppLaunchTTI(ttiMs.milliseconds)
            reportFullyDrawn()
        }
    }
}

enum class StartupPhase { CONFIG, APP }

// bitdrift SDK: log screen views centrally so they fire for both user navigation and
// simulator navigation (SimulationManager.nav()), independent of Compose composition timing.
// POC: User Journey Sankey diagram; per-screen crash analytics
private fun destinationToScreenName(route: String): String = when (route) {
    Screen.Welcome.route -> "Welcome"
    Screen.Advanced.route -> "Advanced"
    Screen.Browse.route -> "Browse"
    Screen.Search.route -> "Search"
    Screen.FeaturedProducts.route -> "Featured"
    Screen.Categories.route -> "Categories"
    Screen.CATEGORY_BROWSE_ROUTE -> "CategoryBrowse"
    Screen.PRODUCT_DETAIL_ROUTE -> "ProductDetail"
    Screen.REVIEWS_ROUTE -> "Reviews"
    Screen.CART_ROUTE -> "Cart"
    Screen.WISHLIST_ROUTE -> "Wishlist"
    Screen.CHECKOUT_GUEST_ROUTE -> "CheckoutGuest"
    Screen.CHECKOUT_SIGNIN_ROUTE -> "CheckoutSignIn"
    Screen.PAYMENT_CARD_ROUTE -> "PaymentCard"
    Screen.PAYMENT_APPLEPAY_ROUTE -> "PaymentApplePay"
    Screen.PAYMENT_PAYPAL_ROUTE -> "PaymentPayPal"
    Screen.PAYMENT_ANDROIDPAY_ROUTE -> "PaymentAndroidPay"
    Screen.PAYMENT_FAILED_ROUTE -> "PaymentFailed"
    Screen.CONFIRMATION_ROUTE -> "Confirmation"
    else -> route
}

@Composable
fun ShoppingDemoContent() {
    val navController = rememberNavController()
    val simulationManager: SimulationManager = viewModel()

    DisposableEffect(navController) {
        val listener = NavController.OnDestinationChangedListener { _, destination, _ ->
            ScreenLogger.logScreenView(destinationToScreenName(destination.route ?: return@OnDestinationChangedListener))
        }
        navController.addOnDestinationChangedListener(listener)
        onDispose { navController.removeOnDestinationChangedListener(listener) }
    }

    val context = androidx.compose.ui.platform.LocalContext.current
    val anrPrefs = remember {
        context.getSharedPreferences(SimulationManager.ANR_PREFS_NAME, android.content.Context.MODE_PRIVATE)
    }
    val crashPrefs = remember {
        context.getSharedPreferences(ShoppingDemoApp.PREFS, android.content.Context.MODE_PRIVATE)
    }
    val autoInfinitePrefs = remember {
        context.getSharedPreferences("auto_infinite", android.content.Context.MODE_PRIVATE)
    }
    val forceQuitPrefs = remember {
        context.getSharedPreferences(SimulationManager.FORCE_QUIT_PREFS_NAME, android.content.Context.MODE_PRIVATE)
    }

    var phase by remember {
        mutableStateOf(
            if (anrPrefs.getBoolean("restart_pending", false) ||
                forceQuitPrefs.getBoolean("restart_pending", false) ||
                anrPrefs.getBoolean("resume_infinite", false) ||
                forceQuitPrefs.getBoolean("resume_infinite", false)
            ) StartupPhase.APP else StartupPhase.CONFIG
        )
    }
    var crashEnabled by remember { mutableStateOf(crashPrefs.getBoolean("active", false)) }
    var autoInfiniteEnabled by remember { mutableStateOf(autoInfinitePrefs.getBoolean("active", false)) }
    var countdown by remember { mutableStateOf(5) }

    when (phase) {
        StartupPhase.CONFIG -> {
            LaunchedEffect(Unit) {
                for (i in 5 downTo 1) {
                    countdown = i
                    delay(1000)
                }
                crashPrefs.edit().putBoolean("active", crashEnabled).apply()
                simulationManager.crashLoopEnabled = crashEnabled
                if (autoInfiniteEnabled) {
                    simulationManager.scheduleAutoStartInfinite()
                }
                phase = StartupPhase.APP
            }

            StartupConfigScreen(
                crashEnabled = crashEnabled,
                autoInfiniteEnabled = autoInfiniteEnabled,
                countdown = countdown,
                onToggleCrash = { crashEnabled = it },
                onToggleAutoInfinite = {
                    autoInfiniteEnabled = it
                    autoInfinitePrefs.edit().putBoolean("active", it).apply()
                },
                onSkip = {
                    crashPrefs.edit().putBoolean("active", false).apply()
                    simulationManager.crashLoopEnabled = false
                    phase = StartupPhase.APP
                }
            )
        }

        StartupPhase.APP -> {
            Box(modifier = Modifier.fillMaxSize()) {
                NavHost(
                    navController = navController,
                    startDestination = Screen.Welcome.route
                ) {
                    composable(Screen.Advanced.route) {
                        AdvancedScreen(navController, simulationManager)
                    }

                    composable(Screen.Welcome.route) {
                        WelcomeScreen(navController, simulationManager)
                        LaunchedEffect(Unit) {
                            simulationManager.crashLoopEnabled = crashPrefs.getBoolean("active", false)
                            simulationManager.syncAnrAEnabledState()
                            simulationManager.syncForceQuitEnabledState()
                            val anrRestartPending = anrPrefs.getBoolean("restart_pending", false)
                            val fqRestartPending = forceQuitPrefs.getBoolean("restart_pending", false)
                            val anrResumeInfinite = anrPrefs.getBoolean("resume_infinite", false)
                            val fqResumeInfinite = forceQuitPrefs.getBoolean("resume_infinite", false)
                            val crashResumeInfinite = crashPrefs.getBoolean("resume_infinite_with_crash", false)
                            val hadResumeRequest =
                                anrRestartPending || fqRestartPending || anrResumeInfinite || fqResumeInfinite || crashResumeInfinite

                            if (crashResumeInfinite) {
                                // Crash loop infinite mode resume after app restart
                                crashPrefs.edit()
                                    .putBoolean("resume_infinite_with_crash", false)
                                    .commit()
                                simulationManager.restoreVariantFromPrefs()
                                ScreenLogger.logInfo(
                                    "crash_restart_resume",
                                    mapOf("variant" to simulationManager.activeVariant.label)
                                )
                                simulationManager.scheduleAutoStartInfinite()
                            } else if (anrRestartPending || anrResumeInfinite) {
                                anrPrefs.edit()
                                    .putBoolean(SimulationManager.KEY_RESTART_PENDING, false)
                                    .putBoolean(SimulationManager.KEY_RESUME_INFINITE, false)
                                    .commit()
                                simulationManager.restoreVariantFromPrefs()
                                ScreenLogger.logInfo(
                                    "anr_restart_resume",
                                    mapOf(
                                        "mode" to if (anrResumeInfinite) "infinite" else "single",
                                        "pending_flag" to anrRestartPending.toString()
                                    )
                                )
                                if (anrResumeInfinite) {
                                    simulationManager.scheduleAutoStartInfinite()
                                } else {
                                    simulationManager.scheduleAutoStart()
                                }
                            } else if (fqRestartPending || fqResumeInfinite) {
                                forceQuitPrefs.edit()
                                    .putBoolean(SimulationManager.KEY_RESTART_PENDING, false)
                                    .putBoolean(SimulationManager.KEY_RESUME_INFINITE, false)
                                    .commit()
                                simulationManager.restoreVariantFromPrefs()
                                ScreenLogger.logInfo(
                                    "force_quit_restart_resume",
                                    mapOf(
                                        "mode" to if (fqResumeInfinite) "infinite" else "single",
                                        "pending_flag" to fqRestartPending.toString()
                                    )
                                )
                                if (fqResumeInfinite) {
                                    simulationManager.scheduleAutoStartInfinite()
                                } else {
                                    simulationManager.scheduleAutoStart()
                                }
                            }
                            // Relaunch timing can race with Compose/nav readiness.
                            // Retry auto-start a few times so infinite sim reliably resumes.
                            repeat(5) {
                                simulationManager.tryAutoStart(navController)
                                if (simulationManager.isSimulating) return@LaunchedEffect
                                delay(250)
                            }

                            if (hadResumeRequest && !simulationManager.isSimulating) {
                                ScreenLogger.logError(
                                    "restart_autostart_missed",
                                    mapOf(
                                        "anr_restart_pending" to anrRestartPending.toString(),
                                        "fq_restart_pending" to fqRestartPending.toString(),
                                        "anr_resume_infinite" to anrResumeInfinite.toString(),
                                        "fq_resume_infinite" to fqResumeInfinite.toString()
                                    )
                                )
                            }
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
    }
}

@Composable
fun StartupConfigScreen(
    crashEnabled: Boolean,
    autoInfiniteEnabled: Boolean,
    countdown: Int,
    onToggleCrash: (Boolean) -> Unit,
    onToggleAutoInfinite: (Boolean) -> Unit,
    onSkip: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Card(
            colors = CardDefaults.cardColors(containerColor = Color(0xFF1A1A2E)),
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp)
        ) {
            Column(
                modifier = Modifier.padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "Bitdrift Shop Config",
                    style = MaterialTheme.typography.headlineSmall.copy(
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                )

                Text(
                    text = "Auto-starting sim in",
                    style = MaterialTheme.typography.bodyMedium.copy(color = Color.White.copy(alpha = 0.7f))
                )

                Text(
                    text = "${countdown}s",
                    style = MaterialTheme.typography.displayLarge.copy(
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF4CAF50),
                        fontSize = 72.sp
                    )
                )

                HorizontalDivider(color = Color.White.copy(alpha = 0.2f))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Crash mode",
                        style = MaterialTheme.typography.titleMedium.copy(
                            color = if (crashEnabled) Color(0xFFF44336) else Color.White
                        )
                    )
                    Switch(
                        checked = crashEnabled,
                        onCheckedChange = onToggleCrash,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = Color(0xFFF44336)
                        )
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Auto ∞ sim",
                        style = MaterialTheme.typography.titleMedium.copy(
                            color = if (autoInfiniteEnabled) Color(0xFF9C27B0) else Color.White
                        )
                    )
                    Switch(
                        checked = autoInfiniteEnabled,
                        onCheckedChange = onToggleAutoInfinite,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = Color(0xFF9C27B0)
                        )
                    )
                }

                Button(
                    onClick = onSkip,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.15f))
                ) {
                    Text(
                        text = "Skip -> Normal App",
                        style = MaterialTheme.typography.titleMedium.copy(color = Color.White),
                        modifier = Modifier.padding(vertical = 4.dp)
                    )
                }
            }
        }
    }
}
