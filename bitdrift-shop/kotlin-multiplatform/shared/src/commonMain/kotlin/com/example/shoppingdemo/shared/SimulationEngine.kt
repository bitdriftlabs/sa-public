package com.example.shoppingdemo.shared

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Interface for platform-specific navigation.
 * Android implements with NavController, iOS with NavigationPath.
 */
interface Navigator {
    fun navigate(route: String)
    fun navigateAndClear(route: String)
}

/**
 * Handles automated simulation of user journeys through the app.
 * Randomly selects paths at each decision point to generate varied journey data.
 * Shared across Android and iOS platforms.
 */
class SimulationEngine {

    private val _isSimulating = MutableStateFlow(false)
    val isSimulating: StateFlow<Boolean> = _isSimulating.asStateFlow()

    private val _currentRun = MutableStateFlow(0)
    val currentRun: StateFlow<Int> = _currentRun.asStateFlow()

    private val _totalRuns = MutableStateFlow(0)
    val totalRuns: StateFlow<Int> = _totalRuns.asStateFlow()

    private var isCancelled = false
    private val stepDelay = 50L

    val isInfiniteMode: Boolean get() = _totalRuns.value == -1

    private var simulationJob: Job? = null

    fun cancel() {
        isCancelled = true
        ScreenLogger.logInfo(
            "simulation_cancelled",
            mapOf(
                "completed_runs" to _currentRun.value.toString(),
                "total_runs" to _totalRuns.value.toString()
            )
        )
    }

    fun simulate(runs: Int, navigator: Navigator, scope: CoroutineScope) {
        simulationJob = scope.launch {
            _isSimulating.value = true
            isCancelled = false
            _totalRuns.value = runs
            _currentRun.value = 0

            ScreenLogger.logSimulationStart(runs)

            for (i in 1..runs) {
                if (isCancelled) break
                _currentRun.value = i
                runSingleJourney(navigator)
                if (isCancelled) break
                delay(50L)
            }

            val completedRuns = if (isCancelled) _currentRun.value else runs
            ScreenLogger.logSimulationEnd(completedRuns)

            navigator.navigateAndClear(AppScreen.Welcome.route)
            resetState()
        }
    }

    fun infiniteSimulate(navigator: Navigator, scope: CoroutineScope) {
        simulationJob = scope.launch {
            _isSimulating.value = true
            isCancelled = false
            _totalRuns.value = -1
            _currentRun.value = 0

            ScreenLogger.logInfo("infinite_simulation_start", emptyMap())

            while (!isCancelled) {
                _currentRun.value++
                runSingleJourney(navigator)
                delay(50L)
            }

            ScreenLogger.logInfo("infinite_simulation_end", mapOf("total_runs" to _currentRun.value.toString()))

            navigator.navigateAndClear(AppScreen.Welcome.route)
            resetState()
        }
    }

    private fun resetState() {
        _isSimulating.value = false
        _currentRun.value = 0
        _totalRuns.value = 0
        isCancelled = false
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Fully Random Journey Simulator
    //
    // Each journey walks through every major step of the shopping funnel,
    // randomly choosing a branch at each decision point.
    // Every journey always completes to Confirmation.
    //
    //  Welcome
    //    → discovery: Browse | Search | Categories→CategoryBrowse (random)
    //    → maybe Featured (coin flip)
    //    → ProductDetail
    //    → maybe Reviews (coin flip)
    //    → maybe Wishlist (coin flip)
    //    → Cart (add multiple, remove, empty, re-add)
    //    → checkout: CheckoutGuest | CheckoutSignIn (random)
    //    → payment: PaymentCard | PaymentApplePay | PaymentPayPal (random)
    //    → Confirmation
    // ═══════════════════════════════════════════════════════════════════════

    private val searchQueries = listOf(
        "headphones", "jacket", "running shoes", "laptop", "watch",
        "camera", "speaker", "backpack", "tablet", "sneakers"
    )

    // ─── API helpers ─────────────────────────────────────────────────────

    private suspend fun fetchBrowseIds(): List<String> = try {
        ApiClient.getBrowse().products.map { it.id }.ifEmpty { listOf("prod_a1b2c3") }
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun fetchSearchIds(): List<String> = try {
        ApiClient.search(searchQueries.random()).products.map { it.id }.ifEmpty { listOf("prod_a1b2c3") }
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun fetchFeaturedIds(): List<String> = try {
        ApiClient.getFeatured().featuredProducts.map { it.id }.ifEmpty { listOf("prod_a1b2c3") }
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun fetchCategoryNames(): List<String> = try {
        ApiClient.getCategories().categories.map { it.name }.ifEmpty { listOf("Electronics") }
    } catch (_: Exception) { listOf("Electronics") }

    private suspend fun fetchCategoryProductIds(cat: String): List<String> = try {
        ApiClient.getCategoryProducts(cat).products.map { it.id }.ifEmpty { listOf("prod_a1b2c3") }
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun nav(navigator: Navigator, route: String) {
        navigator.navigate(route)
        delay(stepDelay)
    }

    // ─── The single journey ──────────────────────────────────────────────

    private suspend fun runSingleJourney(navigator: Navigator) {
        // Step 1: Welcome
        navigator.navigateAndClear(AppScreen.Welcome.route)
        try { ApiClient.getWelcome() } catch (_: Exception) {}
        delay(stepDelay)

        // Step 2: Discovery — randomly pick Browse, Search, or Categories
        var productIds: List<String>
        var source: String
        when ((0..2).random()) {
            0 -> {
                nav(navigator, AppScreen.Browse.route)
                productIds = fetchBrowseIds()
                source = "browse"
            }
            1 -> {
                nav(navigator, AppScreen.Search.route)
                productIds = fetchSearchIds()
                source = "search"
            }
            else -> {
                nav(navigator, AppScreen.Categories.route)
                val cats = fetchCategoryNames()
                val cat = cats.random()
                nav(navigator, AppScreen.CategoryBrowse(cat).route)
                productIds = fetchCategoryProductIds(cat)
                source = "categories"
            }
        }

        // Maybe visit Featured (50% chance)
        if (kotlin.random.Random.nextDouble() < 0.5) {
            nav(navigator, AppScreen.FeaturedProducts.route)
            productIds = fetchFeaturedIds()
            source = "featured"
        }

        val pid = productIds.random()

        // Step 3: ProductDetail
        nav(navigator, AppScreen.ProductDetail(source, pid).route)
        try { ApiClient.getProduct(pid) } catch (_: Exception) {}

        // Maybe visit Reviews (50% chance)
        if (kotlin.random.Random.nextDouble() < 0.5) {
            nav(navigator, AppScreen.Reviews(source, pid).route)
            try { ApiClient.getReviews(pid) } catch (_: Exception) {}
        }

        // Maybe visit Wishlist (40% chance)
        if (kotlin.random.Random.nextDouble() < 0.4) {
            nav(navigator, AppScreen.Wishlist(pid).route)
            try { ApiClient.addToWishlist(pid) } catch (_: Exception) {}
        }

        // Step 4: Cart — add multiple items, remove some, view cart
        val cartItems = mutableListOf(pid)
        nav(navigator, AppScreen.Cart(pid).route)
        try { ApiClient.addToCart(pid) } catch (_: Exception) {}

        // Add 1-3 more random products
        val extraCount = (1..3).random()
        repeat(extraCount) {
            val extraPid = productIds.random()
            cartItems.add(extraPid)
            try { ApiClient.addToCart(extraPid, (1..3).random()) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // View the cart
        try { ApiClient.getCart() } catch (_: Exception) {}
        delay(stepDelay)

        // Maybe remove an item (60% chance)
        if (kotlin.random.Random.nextDouble() < 0.6 && cartItems.size > 1) {
            val removeIdx = cartItems.indices.random()
            val removePid = cartItems.removeAt(removeIdx)
            try { ApiClient.deleteCartItem(removePid) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // Maybe empty cart and re-add (20% chance)
        if (kotlin.random.Random.nextDouble() < 0.2) {
            for (item in cartItems) {
                try { ApiClient.deleteCartItem(item) } catch (_: Exception) {}
                delay(stepDelay)
            }
            cartItems.clear()
            val rePid = productIds.random()
            cartItems.add(rePid)
            try { ApiClient.addToCart(rePid) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // Maybe remove and re-add same item (30% chance)
        if (kotlin.random.Random.nextDouble() < 0.3 && cartItems.isNotEmpty()) {
            val flippedPid = cartItems.random()
            try { ApiClient.deleteCartItem(flippedPid) } catch (_: Exception) {}
            delay(stepDelay)
            try { ApiClient.addToCart(flippedPid, (1..5).random()) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // View cart one more time before checkout
        try { ApiClient.getCart() } catch (_: Exception) {}
        delay(stepDelay)

        val checkoutPid = cartItems.lastOrNull() ?: pid

        // Step 5: Checkout — randomly pick Guest or SignIn
        val checkoutSession: String
        if (kotlin.random.Random.nextDouble() < 0.5) {
            nav(navigator, AppScreen.CheckoutGuest(checkoutPid).route)
            checkoutSession = try { ApiClient.checkoutGuest().checkoutSession } catch (_: Exception) { "" }
        } else {
            nav(navigator, AppScreen.CheckoutSignIn(checkoutPid).route)
            checkoutSession = try { ApiClient.checkoutSignIn().checkoutSession } catch (_: Exception) { "" }
        }

        // Step 6: Payment — randomly pick Card, ApplePay, or PayPal
        val orderId: String
        when ((0..2).random()) {
            0 -> {
                nav(navigator, AppScreen.PaymentCard(checkoutSession).route)
                orderId = try { ApiClient.payCard(checkoutSession).orderId } catch (_: Exception) { "" }
            }
            1 -> {
                nav(navigator, AppScreen.PaymentApplePay(checkoutSession).route)
                orderId = try { ApiClient.payApplePay(checkoutSession).orderId } catch (_: Exception) { "" }
            }
            else -> {
                nav(navigator, AppScreen.PaymentPayPal(checkoutSession).route)
                orderId = try { ApiClient.payPayPal(checkoutSession).orderId } catch (_: Exception) { "" }
            }
        }

        // Step 7: Confirmation
        nav(navigator, AppScreen.Confirmation(orderId).route)
        try { ApiClient.getConfirmation(orderId) } catch (_: Exception) {}
    }
}
