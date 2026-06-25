package ai.bitdrift.shop.shared

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

interface Navigator {
    fun navigate(route: String)
    fun navigateAndClear(route: String)
}

class SimulationEngine {

    // ── Progress ──────────────────────────────────────────────────────────────
    private val _isSimulating = MutableStateFlow(false)
    val isSimulating: StateFlow<Boolean> = _isSimulating.asStateFlow()

    private val _currentRun = MutableStateFlow(0)
    val currentRun: StateFlow<Int> = _currentRun.asStateFlow()

    private val _totalRuns = MutableStateFlow(0)
    val totalRuns: StateFlow<Int> = _totalRuns.asStateFlow()

    val isInfiniteMode: Boolean get() = _totalRuns.value == -1

    // ── Variant & chaos ───────────────────────────────────────────────────────
    private val _activeVariant = MutableStateFlow(SimVariant.CONTROL)
    val activeVariant: StateFlow<SimVariant> = _activeVariant.asStateFlow()

    private val _crashLoopEnabled = MutableStateFlow(false)
    val crashLoopEnabled: StateFlow<Boolean> = _crashLoopEnabled.asStateFlow()

    private val _anrAEnabled = MutableStateFlow(false)
    val anrAEnabled: StateFlow<Boolean> = _anrAEnabled.asStateFlow()

    private val _forceQuitEnabled = MutableStateFlow(false)
    val forceQuitEnabled: StateFlow<Boolean> = _forceQuitEnabled.asStateFlow()

    private val _slowModeEnabled = MutableStateFlow(false)
    val slowModeEnabled: StateFlow<Boolean> = _slowModeEnabled.asStateFlow()

    fun setVariant(v: SimVariant) { _activeVariant.value = v }
    fun setCrashLoop(b: Boolean) { _crashLoopEnabled.value = b }
    fun setAnrA(b: Boolean) { _anrAEnabled.value = b }
    fun setForceQuit(b: Boolean) { _forceQuitEnabled.value = b }
    fun setSlowMode(b: Boolean) { _slowModeEnabled.value = b }

    // ── Internal counters ─────────────────────────────────────────────────────
    private var isCancelled = false
    private var crashIndex = 0
    private var entityIndex = 0
    private var journeysSinceAnr = 0
    private var journeysSinceForceQuit = 0
    private val stepDelay = 50L
    private var simulationJob: Job? = null

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    fun cancel() {
        isCancelled = true
        ScreenLogger.logInfo(
            "simulation_cancelled",
            mapOf(
                "completed_runs" to _currentRun.value.toString(),
                "total_runs" to _totalRuns.value.toString(),
            ),
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
                delay(stepDelay)
            }
            val completed = if (isCancelled) _currentRun.value else runs
            ScreenLogger.logSimulationEnd(completed)
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
                delay(stepDelay)
            }
            ScreenLogger.logInfo("infinite_simulation_end", mapOf("total_runs" to _currentRun.value.toString()))
            navigator.navigateAndClear(AppScreen.Welcome.route)
            resetState()
        }
    }

    fun startAbSimulation(navigator: Navigator, scope: CoroutineScope) {
        simulationJob = scope.launch {
            _isSimulating.value = true
            isCancelled = false
            val variants = SimVariant.entries
            _totalRuns.value = variants.size * 5
            _currentRun.value = 0
            ScreenLogger.logInfo("ab_simulation_start", mapOf("total_runs" to _totalRuns.value.toString()))
            for (variant in variants) {
                if (isCancelled) break
                _activeVariant.value = variant
                repeat(5) {
                    if (!isCancelled) {
                        _currentRun.value++
                        runSingleJourney(navigator)
                        delay(stepDelay)
                    }
                }
            }
            ScreenLogger.logInfo("ab_simulation_end", mapOf("completed_runs" to _currentRun.value.toString()))
            navigator.navigateAndClear(AppScreen.Welcome.route)
            resetState()
        }
    }

    fun startCardinalitySimulation(navigator: Navigator, scope: CoroutineScope) {
        simulationJob = scope.launch {
            _isSimulating.value = true
            isCancelled = false
            _totalRuns.value = 10
            _currentRun.value = 0
            ScreenLogger.logInfo("cardinality_simulation_start", emptyMap())
            repeat(10) { i ->
                if (!isCancelled) {
                    _currentRun.value = i + 1
                    runCardinalityJourney(navigator)
                    delay(100L)
                }
            }
            ScreenLogger.logInfo("cardinality_simulation_end", emptyMap())
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

    // ── API helpers ───────────────────────────────────────────────────────────

    private val searchQueries = listOf(
        "headphones", "jacket", "running shoes", "laptop", "watch",
        "camera", "speaker", "backpack", "tablet", "sneakers",
    )

    private suspend fun nav(navigator: Navigator, route: String) {
        navigator.navigate(route)
        delay(stepDelay)
    }

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

    // ── Cardinality journey ───────────────────────────────────────────────────
    // Hits /inventory/lookup/<item>/<session> with unique session IDs to demo the
    // x-capture-path-template fix for high-cardinality route grouping.

    private suspend fun runCardinalityJourney(navigator: Navigator) {
        navigator.navigateAndClear(AppScreen.Welcome.route)
        delay(stepDelay)
        nav(navigator, AppScreen.Browse.route)
        val pid = fetchBrowseIds().random()
        nav(navigator, AppScreen.ProductDetail("browse", pid).route)
        try {
            ApiClient.getProduct(pid)
            ApiClient.inventoryLookup(pid, randomHex16())
        } catch (_: Exception) {}
        delay(stepDelay)
        navigator.navigateAndClear(AppScreen.Welcome.route)
    }

    // ── Main journey ──────────────────────────────────────────────────────────

    private suspend fun runSingleJourney(navigator: Navigator) {
        val variant = _activeVariant.value
        val profile = VARIANT_PROFILES[variant] ?: VARIANT_PROFILES[SimVariant.CONTROL]!!

        applyVariant(variant)

        val entity = DEMO_ENTITIES[entityIndex % DEMO_ENTITIES.size]
        entityIndex++
        ScreenLogger.setEntityId(entity)

        val journeySpan = ScreenLogger.startSpan("journey", mapOf("variant" to variantDisplayName(variant)))
        ScreenLogger.logInfo("journey_started", mapOf("entity" to entity, "variant" to variantDisplayName(variant)))

        // Step 1: Welcome
        navigator.navigateAndClear(AppScreen.Welcome.route)
        try { ApiClient.getWelcome() } catch (_: Exception) {}
        delay(stepDelay)

        // Step 2: Discovery
        val discoverySpan = ScreenLogger.startSpan("product_discovery", emptyMap(), journeySpan.id)
        var productIds: List<String>
        val r = kotlin.random.Random.nextDouble()
        val source: String
        when {
            r < profile.discoveryBrowseMax -> {
                nav(navigator, AppScreen.Browse.route)
                productIds = fetchBrowseIds()
                source = "browse"
            }
            r < profile.discoverySearchMax -> {
                nav(navigator, AppScreen.Search.route)
                productIds = fetchSearchIds()
                source = "search"
            }
            else -> {
                nav(navigator, AppScreen.Categories.route)
                val cat = fetchCategoryNames().random()
                nav(navigator, AppScreen.CategoryBrowse(cat).route)
                productIds = fetchCategoryProductIds(cat)
                source = "categories"
            }
        }

        if (kotlin.random.Random.nextDouble() < profile.featuredProb) {
            nav(navigator, AppScreen.FeaturedProducts.route)
            productIds = fetchFeaturedIds()
        }

        val pid = productIds.random()

        // Step 3: Product detail
        nav(navigator, AppScreen.ProductDetail(source, pid).route)
        try { ApiClient.getProduct(pid) } catch (_: Exception) {}

        // Force quit injection at ProductDetail
        if (_forceQuitEnabled.value) {
            journeysSinceForceQuit++
            if (journeysSinceForceQuit >= 3 || kotlin.random.Random.nextDouble() < 0.6) {
                journeysSinceForceQuit = 0
                ScreenLogger.setFeatureFlagExposure("force_quit", "injected")
                ScreenLogger.logWarning("force_quit_injected", emptyMap())
                discoverySpan.end("canceled")
                journeySpan.end("canceled")
                triggerForceQuit()
                return
            }
        }

        if (kotlin.random.Random.nextDouble() < profile.reviewsProb) {
            nav(navigator, AppScreen.Reviews(source, pid).route)
            try { ApiClient.getReviews(pid) } catch (_: Exception) {}
        }

        if (kotlin.random.Random.nextDouble() < profile.wishlistProb) {
            nav(navigator, AppScreen.Wishlist(pid).route)
            try {
                ApiClient.addToWishlist(pid)
                ScreenLogger.logInfo("add_to_wishlist", mapOf("product_id" to pid))
            } catch (_: Exception) {}
        }

        discoverySpan.end("success", mapOf("source" to source))

        // Step 4: Cart
        val cartItems = mutableListOf(pid)
        nav(navigator, AppScreen.Cart(pid).route)
        try {
            ApiClient.addToCart(pid)
            ScreenLogger.logInfo("add_to_cart", mapOf("product_id" to pid, "source" to source))
        } catch (_: Exception) {}

        val extraCount = (profile.extraCartMin..profile.extraCartMax).random()
        repeat(extraCount) {
            val extra = productIds.random()
            cartItems.add(extra)
            try {
                ApiClient.addToCart(extra, (1..3).random())
                ScreenLogger.logInfo("add_to_cart", mapOf("product_id" to extra, "source" to "cart"))
            } catch (_: Exception) {}
            delay(stepDelay)
        }

        try { ApiClient.getCart() } catch (_: Exception) {}
        delay(stepDelay)

        if (kotlin.random.Random.nextDouble() < profile.removeItemProb && cartItems.size > 1) {
            val removePid = cartItems.removeAt(cartItems.indices.random())
            try {
                ApiClient.deleteCartItem(removePid)
                ScreenLogger.logInfo("cart_item_removed", mapOf("product_id" to removePid))
            } catch (_: Exception) {}
            delay(stepDelay)
        }

        if (kotlin.random.Random.nextDouble() < profile.emptyReaddProb) {
            for (item in cartItems.toList()) {
                try { ApiClient.deleteCartItem(item) } catch (_: Exception) {}
                delay(stepDelay)
            }
            cartItems.clear()
            val rePid = productIds.random()
            cartItems.add(rePid)
            try {
                ApiClient.addToCart(rePid)
                ScreenLogger.logInfo("add_to_cart", mapOf("product_id" to rePid, "source" to "rewishlist"))
            } catch (_: Exception) {}
            delay(stepDelay)
        }

        if (kotlin.random.Random.nextDouble() < profile.quantityFlipProb && cartItems.isNotEmpty()) {
            val flipPid = cartItems.random()
            try {
                ApiClient.deleteCartItem(flipPid)
                ApiClient.addToCart(flipPid, (1..5).random())
            } catch (_: Exception) {}
            delay(stepDelay)
        }

        try { ApiClient.getCart() } catch (_: Exception) {}
        delay(stepDelay)

        if (kotlin.random.Random.nextDouble() < profile.cartAbandonProb) {
            ScreenLogger.logInfo("cart_abandoned", mapOf("variant" to variantDisplayName(variant)))
            journeySpan.end("canceled", mapOf("reason" to "cart_abandon"))
            navigator.navigateAndClear(AppScreen.Welcome.route)
            maybeFireCrashLoop()
            return
        }

        // Step 5: Checkout
        val checkoutSpan = ScreenLogger.startSpan("checkout", emptyMap(), journeySpan.id)
        val checkoutPid = cartItems.lastOrNull() ?: pid
        val isGuest = kotlin.random.Random.nextDouble() < profile.guestProb

        ScreenLogger.logInfo(
            "checkout_started",
            mapOf("type" to if (isGuest) "guest" else "signin", "variant" to variantDisplayName(variant)),
        )

        val checkoutSession: String
        if (isGuest) {
            nav(navigator, AppScreen.CheckoutGuest(checkoutPid).route)
            checkoutSession = try { ApiClient.checkoutGuest().checkoutSession } catch (_: Exception) { "" }
        } else {
            nav(navigator, AppScreen.CheckoutSignIn(checkoutPid).route)
            checkoutSession = try { ApiClient.checkoutSignIn().checkoutSession } catch (_: Exception) { "" }
        }

        // ANR injection (Variant A + guest checkout)
        if (_anrAEnabled.value && isGuest && variant == SimVariant.VARIANT_A) {
            journeysSinceAnr++
            if (journeysSinceAnr >= 6 || kotlin.random.Random.nextDouble() < 0.25) {
                journeysSinceAnr = 0
                ScreenLogger.setFeatureFlagExposure("anr_a", "injected")
                ScreenLogger.logWarning("anr_injected", mapOf("block_ms" to "15000"))
                checkoutSpan.end("canceled")
                journeySpan.end("canceled")
                triggerAnr(15_000L)
                return
            }
        }

        if (kotlin.random.Random.nextDouble() < profile.checkoutDropoutProb) {
            ScreenLogger.logInfo("checkout_abandoned", mapOf("variant" to variantDisplayName(variant)))
            checkoutSpan.end("canceled", mapOf("reason" to "checkout_dropout"))
            journeySpan.end("canceled", mapOf("reason" to "checkout_dropout"))
            navigator.navigateAndClear(AppScreen.Welcome.route)
            maybeFireCrashLoop()
            return
        }

        // Step 6: Payment — weighted selection
        val totalWeight = profile.paymentCardWeight + profile.paymentApplePayWeight +
            profile.paymentPayPalWeight + profile.paymentAndroidPayWeight
        val r2 = kotlin.random.Random.nextDouble() * totalWeight
        val cardCut = profile.paymentCardWeight
        val appleCut = cardCut + profile.paymentApplePayWeight
        val paypalCut = appleCut + profile.paymentPayPalWeight

        var orderId = ""
        var paymentFailed = false
        val paymentMethod: String

        when {
            r2 < cardCut -> {
                paymentMethod = "card"
                nav(navigator, AppScreen.PaymentCard(checkoutSession).route)
                val result = if (kotlin.random.Random.nextDouble() < profile.paymentFailProb) null
                             else try { ApiClient.payCard(checkoutSession) } catch (_: Exception) { null }
                if (result != null) {
                    orderId = result.orderId
                    ScreenLogger.logInfo("payment_completed", mapOf("method" to "card", "order_id" to orderId))
                } else {
                    paymentFailed = true
                    ScreenLogger.logWarning("payment_failed", mapOf("method" to "card"))
                }
            }
            r2 < appleCut -> {
                paymentMethod = "apple_pay"
                nav(navigator, AppScreen.PaymentApplePay(checkoutSession).route)
                val result = if (kotlin.random.Random.nextDouble() < profile.paymentFailProb) null
                             else try { ApiClient.payApplePay(checkoutSession) } catch (_: Exception) { null }
                if (result != null) {
                    orderId = result.orderId
                    ScreenLogger.logInfo("payment_completed", mapOf("method" to "apple_pay", "order_id" to orderId))
                } else {
                    paymentFailed = true
                    ScreenLogger.logWarning("payment_failed", mapOf("method" to "apple_pay"))
                }
            }
            r2 < paypalCut -> {
                paymentMethod = "paypal"
                nav(navigator, AppScreen.PaymentPayPal(checkoutSession).route)
                val result = if (kotlin.random.Random.nextDouble() < profile.paymentFailProb) null
                             else try { ApiClient.payPayPal(checkoutSession) } catch (_: Exception) { null }
                if (result != null) {
                    orderId = result.orderId
                    ScreenLogger.logInfo("payment_completed", mapOf("method" to "paypal", "order_id" to orderId))
                } else {
                    paymentFailed = true
                    ScreenLogger.logWarning("payment_failed", mapOf("method" to "paypal"))
                }
            }
            else -> {
                paymentMethod = "android_pay"
                nav(navigator, AppScreen.PaymentAndroidPay(checkoutSession).route)
                val result = if (kotlin.random.Random.nextDouble() < profile.androidPayFailProb) null
                             else try { ApiClient.payAndroidPay(checkoutSession) } catch (_: Exception) { null }
                if (result != null) {
                    orderId = result.orderId
                    ScreenLogger.logInfo("payment_completed", mapOf("method" to "android_pay", "order_id" to orderId))
                } else {
                    paymentFailed = true
                    ScreenLogger.logWarning("payment_failed", mapOf("method" to "android_pay"))
                }
            }
        }
        delay(stepDelay)

        // Payment failure + optional retry
        if (paymentFailed) {
            nav(navigator, AppScreen.PaymentFailed(paymentMethod).route)
            if (kotlin.random.Random.nextDouble() < 0.5) {
                val retry = try { ApiClient.payCard(checkoutSession) } catch (_: Exception) { null }
                if (retry != null) {
                    orderId = retry.orderId
                    paymentFailed = false
                    ScreenLogger.logInfo("payment_completed", mapOf("method" to "card", "retry" to "true"))
                }
            }
        }

        if (paymentFailed) {
            checkoutSpan.end("failure", mapOf("reason" to "payment_failed"))
            journeySpan.end("failure", mapOf("reason" to "payment_failed"))
            navigator.navigateAndClear(AppScreen.Welcome.route)
            maybeFireCrashLoop()
            return
        }

        checkoutSpan.end("success", mapOf("order_id" to orderId))

        // Step 7: Confirmation
        nav(navigator, AppScreen.Confirmation(orderId).route)
        try { ApiClient.getConfirmation(orderId) } catch (_: Exception) {}

        journeySpan.end("success", mapOf("order_id" to orderId))
        maybeFireCrashLoop()
    }

    private fun maybeFireCrashLoop() {
        if (!_crashLoopEnabled.value) return
        val crash = CRASHES[crashIndex % CRASHES.size]
        crashIndex++
        triggerCrash(crash.name)
    }
}

// Random 16-char hex string for cardinality simulation unique session IDs.
internal fun randomHex16(): String {
    val chars = "0123456789abcdef"
    return (1..16).map { chars[kotlin.random.Random.nextInt(chars.length)] }.joinToString("")
}
