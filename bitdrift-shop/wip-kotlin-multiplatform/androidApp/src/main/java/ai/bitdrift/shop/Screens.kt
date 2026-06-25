package ai.bitdrift.shop

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import ai.bitdrift.shop.shared.*
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.CaptureResult
import kotlinx.coroutines.launch
import ai.bitdrift.shop.shared.SimVariant
import ai.bitdrift.shop.shared.variantDisplayName

// MARK: - Step 1: Welcome

@Composable
fun WelcomeScreen(navController: NavController, simulationViewModel: SimulationViewModel) {
    var apiData by remember { mutableStateOf<WelcomeResponse?>(null) }
    val isSimulating by simulationViewModel.isSimulating.collectAsState()

    LaunchedEffect(Unit) {
        try { apiData = ApiClient.getWelcome() } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val promoText = it.promotions.firstOrNull()?.title ?: ""
        "${it.tagline}\n$promoText"
    } ?: "Experience different shopping journeys"

    ScreenContainer(
        screenName = "Welcome",
        title = apiData?.storeName ?: "Welcome to Bitdrift Shop",
        subtitle = subtitle,
        step = 1,
        icon = Icons.Default.ShoppingCart,
        color = Color(0xFF2196F3),
        logoResId = R.drawable.bitdrift_logo
    ) {
        PrimaryButton(
            title = "Browse Products",
            icon = Icons.Default.Menu,
            enabled = !isSimulating
        ) {
            navController.navigate(AppScreen.Browse.route)
        }
        SecondaryButton(
            title = "Search for Items",
            icon = Icons.Default.Search,
            enabled = !isSimulating
        ) {
            navController.navigate(AppScreen.Search.route)
        }
        SecondaryButton(
            title = "Advanced",
            icon = Icons.Default.Settings,
            enabled = !isSimulating
        ) {
            navController.navigate(AppScreen.Advanced.route)
        }
        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

        if (isSimulating) {
            Text(
                text = "Simulation in progress...",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(16.dp)
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(modifier = Modifier.weight(1f)) {
                    SimButton(title = "Sim 10", color = Color(0xFFFF9800)) {
                        simulationViewModel.simulate(10, navController)
                    }
                }
                Box(modifier = Modifier.weight(1f)) {
                    SimButton(title = "Sim 100", color = Color(0xFFF44336)) {
                        simulationViewModel.simulate(100, navController)
                    }
                }
                Box(modifier = Modifier.weight(1f)) {
                    SimButton(title = "∞ Sim", color = Color(0xFF9C27B0)) {
                        simulationViewModel.infiniteSimulate(navController)
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(modifier = Modifier.weight(1f)) {
                    SimButton(title = "A/B Sim", color = Color(0xFF607D8B)) {
                        simulationViewModel.startAbSimulation(navController)
                    }
                }
                Box(modifier = Modifier.weight(1f)) {
                    SimButton(title = "Cardinality", color = Color(0xFF795548)) {
                        simulationViewModel.startCardinalitySimulation(navController)
                    }
                }
            }
        }

        var deviceCode by remember { mutableStateOf<String?>(null) }
        var supportLogEnabled by remember { mutableStateOf(false) }
        val clipboardManager = LocalClipboardManager.current

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = {
                    Logger.createTemporaryDeviceCode { result ->
                        when (result) {
                            is CaptureResult.Success -> {
                                deviceCode = result.value
                                clipboardManager.setText(AnnotatedString(result.value))
                            }
                            is CaptureResult.Failure -> {
                                deviceCode = "⚠ needs_sdk_key"
                            }
                        }
                    }
                },
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (deviceCode != null) Color(0xFF2196F3) else MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = if (deviceCode != null) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                ),
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
            ) {
                Text(
                    text = deviceCode ?: "Device Code",
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = if (deviceCode != null) 11.sp else 14.sp
                    ),
                    maxLines = 1
                )
            }

            Button(
                onClick = {
                    supportLogEnabled = !supportLogEnabled
                    Logger.addField("supportlog", supportLogEnabled.toString())
                },
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (supportLogEnabled) Color(0xFF4CAF50) else MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = if (supportLogEnabled) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                ),
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
            ) {
                Text(
                    text = if (supportLogEnabled) "Support Log: ON" else "Support Log: OFF",
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold)
                )
            }
        }
    }
}

// MARK: - Step 2: Browse / Search

@Composable
fun BrowseScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<BrowseResponse?>(null) }

    LaunchedEffect(Unit) {
        try { apiData = ApiClient.getBrowse() } catch (_: Exception) {}
    }

    val products = apiData?.products ?: emptyList()
    val subtitle = apiData?.let {
        "Showing ${products.size} of ${it.totalProducts} products"
    } ?: "Explore our product catalog"

    ScreenContainer(
        screenName = "Browse",
        title = "Browse",
        subtitle = subtitle,
        step = 2,
        icon = Icons.Default.Menu,
        color = Color(0xFF9C27B0),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(AppScreen.ProductDetail("browse", productId).route)
        }
        PrimaryButton(title = "View Featured", icon = Icons.Default.Star) {
            navController.navigate(AppScreen.FeaturedProducts.route)
        }
        SecondaryButton(title = "Shop by Category", icon = Icons.Default.List) {
            navController.navigate(AppScreen.Categories.route)
        }
    }
}

@Composable
fun SearchScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<SearchResponse?>(null) }

    LaunchedEffect(Unit) {
        try { apiData = ApiClient.search("headphones") } catch (_: Exception) {}
    }

    val products = apiData?.products ?: emptyList()
    val subtitle = apiData?.let {
        "Found ${it.resultCount} results for \"${it.query}\""
    } ?: "Find exactly what you're looking for"

    ScreenContainer(
        screenName = "Search",
        title = "Search",
        subtitle = subtitle,
        step = 2,
        icon = Icons.Default.Search,
        color = Color(0xFFFF9800),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(AppScreen.ProductDetail("search", productId).route)
        }
        PrimaryButton(title = "View Featured", icon = Icons.Default.Star) {
            navController.navigate(AppScreen.FeaturedProducts.route)
        }
        SecondaryButton(title = "Shop by Category", icon = Icons.Default.List) {
            navController.navigate(AppScreen.Categories.route)
        }
    }
}

// MARK: - Step 3: Featured Products / Categories

@Composable
fun FeaturedProductsScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<FeaturedResponse?>(null) }

    LaunchedEffect(Unit) {
        try { apiData = ApiClient.getFeatured() } catch (_: Exception) {}
    }

    val products = apiData?.featuredProducts ?: emptyList()
    val firstProductId = products.firstOrNull()?.id ?: "prod_a1b2c3"
    val subtitle = apiData?.let {
        val banner = it.banner?.text ?: ""
        "$banner — ${products.size} picks"
    } ?: "Our top picks for you"

    ScreenContainer(
        screenName = "Featured",
        title = "Featured Products",
        subtitle = subtitle,
        step = 3,
        icon = Icons.Default.Star,
        color = Color(0xFFFFEB3B),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(AppScreen.ProductDetail("featured", productId).route)
        }
        PrimaryButton(title = "View Product Details", icon = Icons.Default.Info) {
            navController.navigate(AppScreen.ProductDetail("featured", firstProductId).route)
        }
        SecondaryButton(title = "Read Reviews First", icon = Icons.Default.Email) {
            navController.navigate(AppScreen.Reviews("featured", firstProductId).route)
        }
    }
}

@Composable
fun CategoriesScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<CategoriesResponse?>(null) }

    LaunchedEffect(Unit) {
        try { apiData = ApiClient.getCategories() } catch (_: Exception) {}
    }

    val categories = apiData?.categories ?: emptyList()
    val subtitle = if (categories.isNotEmpty()) {
        categories.joinToString(", ") { it.name }
    } else "Browse by product type"

    ScreenContainer(
        screenName = "Categories",
        title = "Categories",
        subtitle = subtitle,
        step = 3,
        icon = Icons.Default.List,
        color = Color(0xFF4CAF50),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        CategoryRow(categories) { categoryName ->
            navController.navigate(AppScreen.CategoryBrowse(categoryName).route)
        }
        PrimaryButton(title = "View Product Details", icon = Icons.Default.Info) {
            navController.navigate(AppScreen.ProductDetail("categories", "prod_a1b2c3").route)
        }
        SecondaryButton(title = "Read Reviews First", icon = Icons.Default.Email) {
            navController.navigate(AppScreen.Reviews("categories", "prod_a1b2c3").route)
        }
    }
}

// MARK: - Step 3b: Category Browse

@Composable
fun CategoryBrowseScreen(navController: NavController, category: String?) {
    val cat = category ?: "Electronics"
    var apiData by remember { mutableStateOf<CategoryProductsResponse?>(null) }

    LaunchedEffect(cat) {
        try { apiData = ApiClient.getCategoryProducts(cat) } catch (_: Exception) {}
    }

    val products = apiData?.products ?: emptyList()
    val firstProductId = products.firstOrNull()?.id ?: "prod_a1b2c3"
    val subtitle = if (products.isNotEmpty()) {
        "${products.size} products in $cat"
    } else "Loading $cat..."

    ScreenContainer(
        screenName = "CategoryBrowse",
        title = cat,
        subtitle = subtitle,
        step = 3,
        icon = Icons.Default.List,
        color = Color(0xFF4CAF50),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(AppScreen.ProductDetail("categories", productId).route)
        }
        PrimaryButton(title = "View Product Details", icon = Icons.Default.Info) {
            navController.navigate(AppScreen.ProductDetail("categories", firstProductId).route)
        }
        SecondaryButton(title = "Read Reviews First", icon = Icons.Default.Email) {
            navController.navigate(AppScreen.Reviews("categories", firstProductId).route)
        }
    }
}

// MARK: - Step 4: Product Detail / Reviews

@Composable
fun ProductDetailScreen(navController: NavController, source: String?, productId: String?) {
    val pid = productId ?: "prod_a1b2c3"
    var apiData by remember { mutableStateOf<ProductDetailResponse?>(null) }

    LaunchedEffect(pid) {
        try { apiData = ApiClient.getProduct(pid) } catch (_: Exception) {}
    }

    val title = apiData?.name ?: "Product Details"
    val imageUrl = apiData?.images?.firstOrNull()
    val subtitle = apiData?.let {
        "${it.brand} — \$${String.format("%.2f", it.price)} — ${it.stockCount} in stock"
    } ?: "Loading..."

    ScreenContainer(
        screenName = "ProductDetail",
        title = title,
        subtitle = subtitle,
        step = 4,
        icon = Icons.Default.Notifications,
        color = Color(0xFF00BCD4),
        imageUrl = imageUrl,
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Add to Cart", icon = Icons.Default.Add) {
            ScreenLogger.logInfo("add_to_cart", mapOf("product_id" to pid, "source" to (source ?: "detail")))
            navController.navigate(AppScreen.Cart(pid).route)
        }
        SecondaryButton(title = "Save to Wishlist", icon = Icons.Default.Favorite) {
            navController.navigate(AppScreen.Wishlist(pid).route)
        }
    }
}

@Composable
fun ReviewsScreen(navController: NavController, source: String?, productId: String?) {
    val pid = productId ?: "prod_a1b2c3"
    var apiData by remember { mutableStateOf<ReviewsResponse?>(null) }

    LaunchedEffect(pid) {
        try { apiData = ApiClient.getReviews(pid) } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val topTitle = it.reviews.firstOrNull()?.title ?: ""
        "${it.averageRating} stars from ${it.totalReviews} reviews\n\"$topTitle\""
    } ?: "Loading reviews..."

    ScreenContainer(
        screenName = "Reviews",
        title = "Customer Reviews",
        subtitle = subtitle,
        step = 4,
        icon = Icons.Default.Email,
        color = Color(0xFF00E5BD),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Add to Cart", icon = Icons.Default.Add) {
            ScreenLogger.logInfo("add_to_cart", mapOf("product_id" to pid, "source" to (source ?: "reviews")))
            navController.navigate(AppScreen.Cart(pid).route)
        }
        SecondaryButton(title = "Save to Wishlist", icon = Icons.Default.Favorite) {
            navController.navigate(AppScreen.Wishlist(pid).route)
        }
    }
}

// MARK: - Step 5: Cart / Wishlist

@Composable
fun CartScreen(navController: NavController, productId: String?) {
    val pid = productId ?: ""
    var apiData by remember { mutableStateOf<CartResponse?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(pid) {
        try {
            apiData = if (pid.isNotEmpty()) ApiClient.addToCart(pid) else ApiClient.getCart()
        } catch (_: Exception) {}
    }

    val items = apiData?.items ?: emptyList()
    val subtitle = apiData?.let {
        val count = items.size
        if (count == 0) "Your cart is empty"
        else "$count item${if (count > 1) "s" else ""} — Total: \$${String.format("%.2f", it.total)} (incl. \$${String.format("%.2f", it.tax)} tax)"
    } ?: "Loading cart..."

    ScreenContainer(
        screenName = "Cart",
        title = "Shopping Cart",
        subtitle = subtitle,
        step = 5,
        icon = Icons.Default.ShoppingCart,
        color = Color(0xFF2196F3),
        onBack = { navController.popBackStack() }
    ) {
        if (items.isNotEmpty()) {
            Column(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 200.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                items.forEach { item ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = item.name,
                                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                                    maxLines = 1
                                )
                                Text(
                                    text = "Qty: ${item.quantity}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                )
                            }
                            Text(
                                text = "\$${String.format("%.2f", item.lineTotal)}",
                                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                            )
                            IconButton(onClick = {
                                scope.launch {
                                    try {
                                        apiData = ApiClient.deleteCartItem(item.productId)
                                        ScreenLogger.logInfo("cart_item_removed", mapOf("product_id" to item.productId))
                                    } catch (_: Exception) {}
                                }
                            }) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = "Remove",
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                    }
                }
            }
        }
        PrimaryButton(title = "Checkout as Guest", icon = Icons.Default.Person) {
            ScreenLogger.logInfo("checkout_started", mapOf("type" to "guest"))
            navController.navigate(AppScreen.CheckoutGuest(pid).route)
        }
        SecondaryButton(title = "Sign In to Checkout", icon = Icons.Default.Lock) {
            ScreenLogger.logInfo("checkout_started", mapOf("type" to "signin"))
            navController.navigate(AppScreen.CheckoutSignIn(pid).route)
        }
        SecondaryButton(title = "Keep Shopping", icon = Icons.Default.ShoppingCart) {
            navController.navigate(AppScreen.Welcome.route) {
                popUpTo(AppScreen.Welcome.route) { inclusive = true }
            }
        }
    }
}

@Composable
fun WishlistScreen(navController: NavController, productId: String?) {
    val pid = productId ?: "prod_a1b2c3"
    var apiData by remember { mutableStateOf<WishlistResponse?>(null) }

    LaunchedEffect(pid) {
        try { apiData = ApiClient.addToWishlist(pid) } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val firstName = it.items.firstOrNull()?.name ?: ""
        "${it.itemCount} items saved — $firstName"
    } ?: "Loading wishlist..."

    ScreenContainer(
        screenName = "Wishlist",
        title = "Wishlist",
        subtitle = subtitle,
        step = 5,
        icon = Icons.Default.Favorite,
        color = Color(0xFFE91E63),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Checkout as Guest", icon = Icons.Default.Person) {
            ScreenLogger.logInfo("checkout_started", mapOf("type" to "guest", "source" to "wishlist"))
            navController.navigate(AppScreen.CheckoutGuest(pid).route)
        }
        SecondaryButton(title = "Sign In to Checkout", icon = Icons.Default.Lock) {
            ScreenLogger.logInfo("checkout_started", mapOf("type" to "signin", "source" to "wishlist"))
            navController.navigate(AppScreen.CheckoutSignIn(pid).route)
        }
    }
}

// MARK: - Step 6: Checkout Options

@Composable
fun CheckoutGuestScreen(navController: NavController, productId: String?) {
    var apiData by remember { mutableStateOf<CheckoutResponse?>(null) }
    var checkoutSession by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.checkoutGuest()
            checkoutSession = apiData?.checkoutSession ?: ""
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val city = it.shippingAddress?.city ?: ""
        val total = it.orderPreview?.total ?: 0.0
        "Shipping to $city — \$${String.format("%.2f", total)}\n${it.email}"
    } ?: "Loading checkout..."

    ScreenContainer(
        screenName = "CheckoutGuest",
        title = "Guest Checkout",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Person,
        color = Color(0xFF3F51B5),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Pay with Card", icon = Icons.Default.Done) {
            navController.navigate(AppScreen.PaymentCard(checkoutSession).route)
        }
        SecondaryButton(title = "Apple Pay", icon = Icons.Default.Phone) {
            navController.navigate(AppScreen.PaymentApplePay(checkoutSession).route)
        }
    }
}

@Composable
fun CheckoutSignInScreen(navController: NavController, productId: String?) {
    var apiData by remember { mutableStateOf<CheckoutResponse?>(null) }
    var checkoutSession by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.checkoutSignIn()
            checkoutSession = apiData?.checkoutSession ?: ""
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val user = it.user
        val name = user?.name ?: ""
        val email = user?.email ?: ""
        val points = user?.loyaltyPoints ?: 0
        val total = it.orderPreview?.total ?: 0.0
        "Welcome back, $name\n$email — $points pts — \$${String.format("%.2f", total)}"
    } ?: "Loading checkout..."

    ScreenContainer(
        screenName = "CheckoutSignIn",
        title = "Member Checkout",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Lock,
        color = Color(0xFF009688),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Pay with Card", icon = Icons.Default.Done) {
            navController.navigate(AppScreen.PaymentCard(checkoutSession).route)
        }
        SecondaryButton(title = "PayPal", icon = Icons.Default.Send) {
            navController.navigate(AppScreen.PaymentPayPal(checkoutSession).route)
        }
    }
}

// MARK: - Step 6b: Payment Methods

@Composable
fun PaymentCardScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<PaymentResponse?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payCard(session)
            orderId = apiData?.orderId ?: ""
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        "${it.paymentMethod}\n\$${String.format("%.2f", it.amountCharged)} — ${it.transactionId.take(20)}…"
    } ?: "Processing payment..."

    ScreenContainer(
        screenName = "PaymentCard",
        title = "Card Payment",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Done,
        color = Color(0xFF2196F3),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Visa ending 4242", icon = Icons.Default.Done) {
            ScreenLogger.logInfo("payment_completed", mapOf("method" to "card", "card" to "visa_4242", "order_id" to orderId))
            navController.navigate(AppScreen.Confirmation(orderId).route)
        }
        SecondaryButton(title = "Mastercard ending 8888", icon = Icons.Default.Done) {
            ScreenLogger.logInfo("payment_completed", mapOf("method" to "card", "card" to "mc_8888", "order_id" to orderId))
            navController.navigate(AppScreen.Confirmation(orderId).route)
        }
        SecondaryButton(title = "Amex ending 1001", icon = Icons.Default.Done) {
            ScreenLogger.logInfo("payment_completed", mapOf("method" to "card", "card" to "amex_1001", "order_id" to orderId))
            navController.navigate(AppScreen.Confirmation(orderId).route)
        }
    }
}

@Composable
fun PaymentApplePayScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<PaymentResponse?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payApplePay(session)
            orderId = apiData?.orderId ?: ""
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        "Apple Pay — \$${String.format("%.2f", it.amountCharged)}\n${it.transactionId.take(20)}…"
    } ?: "Authenticating..."

    ScreenContainer(
        screenName = "PaymentApplePay",
        title = "Apple Pay",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Phone,
        color = Color.Black,
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Complete Purchase", icon = Icons.Default.CheckCircle) {
            ScreenLogger.logInfo("payment_completed", mapOf("method" to "apple_pay", "order_id" to orderId))
            navController.navigate(AppScreen.Confirmation(orderId).route)
        }
    }
}

@Composable
fun PaymentPayPalScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<PaymentResponse?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payPayPal(session)
            orderId = apiData?.orderId ?: ""
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        "PayPal — \$${String.format("%.2f", it.amountCharged)}\nRef: ${it.paypalReference}"
    } ?: "Connecting to PayPal..."

    ScreenContainer(
        screenName = "PaymentPayPal",
        title = "PayPal",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Send,
        color = Color(0xFF2196F3),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Complete Purchase", icon = Icons.Default.CheckCircle) {
            ScreenLogger.logInfo("payment_completed", mapOf("method" to "paypal", "order_id" to orderId))
            navController.navigate(AppScreen.Confirmation(orderId).route)
        }
    }
}

// MARK: - Step 7: Confirmation

@Composable
fun ConfirmationScreen(navController: NavController, orderId: String?) {
    val oid = orderId ?: ""
    var apiData by remember { mutableStateOf<ConfirmationResponse?>(null) }

    LaunchedEffect(oid) {
        try { apiData = ApiClient.getConfirmation(oid) } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val delivery = it.shipping?.estimatedDelivery ?: ""
        val tracking = it.shipping?.trackingNumber ?: ""
        "Order ${it.orderId}\nTotal: \$${String.format("%.2f", it.total)}\nDelivery: $delivery\nTracking: $tracking\nTxn: ${it.transactionId.take(24)}…"
    } ?: "Order $oid\nThank you for your purchase!"

    ScreenContainer(
        screenName = "Confirmation",
        title = "Order Confirmed!",
        subtitle = subtitle,
        step = 7,
        icon = Icons.Default.CheckCircle,
        color = Color(0xFF4CAF50),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        Button(
            onClick = {
                navController.navigate(AppScreen.Welcome.route) {
                    popUpTo(AppScreen.Welcome.route) { inclusive = true }
                }
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4CAF50))
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(vertical = 8.dp)
            ) {
                Icon(imageVector = Icons.Default.Refresh, contentDescription = null)
                Text("Start New Journey", style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

// MARK: - New: Payment Android Pay

@Composable
fun PaymentAndroidPayScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<PaymentResponse?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payAndroidPay(session)
            orderId = apiData?.orderId ?: ""
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        "Google Pay — \$${String.format("%.2f", it.amountCharged)}\n${it.transactionId.take(20)}…"
    } ?: "Authenticating with Google Pay..."

    ScreenContainer(
        screenName = "PaymentAndroidPay",
        title = "Google Pay",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Phone,
        color = Color(0xFF4285F4),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Complete with Google Pay", icon = Icons.Default.CheckCircle) {
            ScreenLogger.logInfo("payment_completed", mapOf("method" to "android_pay", "order_id" to orderId))
            navController.navigate(AppScreen.Confirmation(orderId).route)
        }
    }
}

// MARK: - New: Payment Failed

@Composable
fun PaymentFailedScreen(navController: NavController, paymentMethod: String?) {
    val method = paymentMethod ?: "unknown"

    ScreenContainer(
        screenName = "PaymentFailed",
        title = "Payment Failed",
        subtitle = "Your $method payment could not be processed.\nPlease try again or use a different method.",
        step = 6,
        icon = Icons.Default.Warning,
        color = Color(0xFFF44336),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(AppScreen.Cart().route) }
    ) {
        PrimaryButton(title = "Try Card Instead", icon = Icons.Default.Done) {
            navController.navigate(AppScreen.PaymentCard("").route)
        }
        SecondaryButton(title = "Return to Cart", icon = Icons.Default.ShoppingCart) {
            navController.navigate(AppScreen.Cart().route) {
                popUpTo(AppScreen.Cart().route) { inclusive = true }
            }
        }
    }
}

// MARK: - New: Advanced

@Composable
fun AdvancedScreen(navController: NavController, simulationViewModel: SimulationViewModel) {
    val activeVariant by simulationViewModel.activeVariant.collectAsState()
    val crashLoopEnabled by simulationViewModel.crashLoopEnabled.collectAsState()
    val anrAEnabled by simulationViewModel.anrAEnabled.collectAsState()
    val forceQuitEnabled by simulationViewModel.forceQuitEnabled.collectAsState()
    val isSimulating by simulationViewModel.isSimulating.collectAsState()

    ScreenLogger.logScreenView("Advanced")

    ScreenContainer(
        screenName = "Advanced",
        title = "Advanced",
        subtitle = "Simulation variant & chaos controls",
        step = 0,
        icon = Icons.Default.Settings,
        color = Color(0xFF607D8B),
        onBack = { navController.popBackStack() }
    ) {
        Text(
            text = "Simulation Variant",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(bottom = 4.dp)
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SimVariant.entries.forEach { variant ->
                val selected = activeVariant == variant
                Button(
                    onClick = { simulationViewModel.setVariant(variant) },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (selected) Color(0xFF2196F3) else MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = if (selected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                    ),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text(variantDisplayName(variant), style = MaterialTheme.typography.labelSmall)
                }
            }
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
        Text(
            text = "Chaos Injection",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(bottom = 4.dp)
        )

        fun chaosToggle(label: String, active: Boolean, onToggle: () -> Unit) {
            Button(
                onClick = onToggle,
                enabled = !isSimulating,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (active) Color(0xFFF44336) else MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = if (active) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) {
                Text(label, style = MaterialTheme.typography.labelLarge)
            }
        }

        chaosToggle(
            label = if (crashLoopEnabled) "Crash Loop: ON" else "Crash Loop: OFF",
            active = crashLoopEnabled
        ) { simulationViewModel.toggleCrashLoop() }

        chaosToggle(
            label = if (anrAEnabled) "ANR Injection: ON (Variant A + guest)" else "ANR Injection: OFF",
            active = anrAEnabled
        ) { simulationViewModel.toggleAnrA() }

        chaosToggle(
            label = if (forceQuitEnabled) "Force Quit: ON (at ProductDetail)" else "Force Quit: OFF",
            active = forceQuitEnabled
        ) { simulationViewModel.toggleForceQuit() }

        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

        val scope = rememberCoroutineScope()
        PrimaryButton(title = "A/B Simulation (3×5 journeys)", icon = Icons.Default.Refresh) {
            navController.popBackStack()
            simulationViewModel.startAbSimulation(navController)
        }
        SecondaryButton(title = "Cardinality Simulation", icon = Icons.Default.Search) {
            navController.popBackStack()
            simulationViewModel.startCardinalitySimulation(navController)
        }
    }
}
