package ai.bitdrift.shop

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.SpanResult
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// bitdrift SDK: SimVariant drives setFeatureFlagExposure() calls so every log in a run is
// tagged with the active cohort, enabling dashboard slicing by checkout_flow, payment_ui,
// and cart_abandon_rate.
enum class SimVariant(val label: String) {
    CONTROL("Control"),    // baseline: fully random, no variant bias
    VARIANT_A("Variant A"), // digital native: snap decisions, skips research, guest + digital pay
    VARIANT_B("Variant B")  // deliberate shopper: reads everything, huge cart churn, signin + card
}

/**
 * Handles automated simulation of user journeys through the app.
 * Randomly selects paths at each decision point to generate varied journey data.
 */
class SimulationManager : ViewModel() {

    var isSimulating by mutableStateOf(false)
        private set

    var currentRun by mutableIntStateOf(0)
        private set

    var totalRuns by mutableIntStateOf(0)
        private set

    var slowModeEnabled by mutableStateOf(false)

    var crashLoopEnabled by mutableStateOf(false)

    // Fast crash mode: skips the shopping journey entirely and fires the next crash
    // combo immediately on every relaunch (see fireFastCrash). Selected on the startup
    // splash screen alongside crashLoopEnabled, not from Advanced settings.
    var fastCrashModeEnabled by mutableStateOf(false)

    var anrAEnabled by mutableStateOf(false)

    var forceQuitEnabled by mutableStateOf(false)

    private var eligibleForceQuitJourneysSinceInject = 0

    private var eligibleAnrGuestJourneysSinceInject = 0

    // Flag to signal cancellation
    private var isCancelled = false

    // Delay between navigation steps (in milliseconds)
    private val stepDelay = 50L

    /**
     * Cancels the current simulation
     */
    var activeVariant by mutableStateOf(SimVariant.CONTROL)
        private set

    // bitdrift SDK: setFeatureFlagExposure() records the variant choice at the moment it is
    // selected, tagging all subsequent logs with the active flag values for dashboard slicing.
    // POC: insights & visualization — A/B cohort comparison in dashboards, Workflows, and alerts
    @OptIn(ExperimentalBitdriftApi::class)
    fun setVariant(variant: SimVariant) {
        activeVariant = variant
        val checkoutFlow = when (variant) {
            SimVariant.CONTROL   -> "random"
            SimVariant.VARIANT_A -> "guest"
            SimVariant.VARIANT_B -> "signin"
        }
        val paymentUi = when (variant) {
            SimVariant.CONTROL   -> "random"
            SimVariant.VARIANT_A -> "digital"
            SimVariant.VARIANT_B -> "card"
        }
        val cartAbandon = when (variant) {
            SimVariant.CONTROL   -> "medium"
            SimVariant.VARIANT_A -> "high"
            SimVariant.VARIANT_B -> "low"
        }
        // Record feature flag exposures (per-session, triggers workflow transitions)
        Logger.setFeatureFlagExposure("checkout_flow", checkoutFlow)
        Logger.setFeatureFlagExposure("payment_ui", paymentUi)
        Logger.setFeatureFlagExposure("cart_abandon_rate", cartAbandon)
        // Also set as global fields so every log carries the active flag values for debugging
        Logger.addField("ff_checkout_flow", checkoutFlow)
        Logger.addField("ff_payment_ui", paymentUi)
        Logger.addField("ff_cart_abandon_rate", cartAbandon)
        Logger.addField("ff_variant", variant.label)
        // Android Pay flag: enabled for Control + Variant A, disabled for Variant B
        val androidPay = when (variant) {
            SimVariant.CONTROL   -> "enabled"
            SimVariant.VARIANT_A -> "enabled"
            SimVariant.VARIANT_B -> "disabled"
        }
        Logger.setFeatureFlagExposure("payment_android_pay", androidPay)
        Logger.addField("ff_payment_android_pay", androidPay)
        val orderSummary = if (crashLoopEnabled) "v2" else "v1"
        Logger.setFeatureFlagExposure("order_summary", orderSummary)
        Logger.addField("ff_order_summary", orderSummary)
        val anrAState = if (anrAEnabled) "enabled" else "disabled"
        Logger.setFeatureFlagExposure("anr_a", anrAState)
        Logger.addField("ff_anr_a", anrAState)
        val forceQuitState = if (forceQuitEnabled) "enabled" else "disabled"
        Logger.setFeatureFlagExposure("force_quit", forceQuitState)
        Logger.addField("ff_force_quit", forceQuitState)
        // Emit an explicit log so we can verify flag exposure in the log stream
        Logger.logInfo { "feature_flag_exposure_set" }
    }

    fun syncAnrAEnabledState() {
        val prefs = ShoppingDemoApp.appContext.getSharedPreferences(ANR_PREFS_NAME, Context.MODE_PRIVATE)
        anrAEnabled = prefs.getBoolean(KEY_ANR_A_ACTIVE, false)
    }

    fun syncForceQuitEnabledState() {
        val prefs = ShoppingDemoApp.appContext.getSharedPreferences(FORCE_QUIT_PREFS_NAME, Context.MODE_PRIVATE)
        forceQuitEnabled = prefs.getBoolean(KEY_FORCE_QUIT_ACTIVE, false)
    }

    fun restoreVariantFromPrefs() {
        // Check ANR prefs first, then force-quit prefs
        val anrPrefs = ShoppingDemoApp.appContext.getSharedPreferences(ANR_PREFS_NAME, Context.MODE_PRIVATE)
        var variantName = anrPrefs.getString(KEY_RESTART_VARIANT, null)
        if (variantName != null) {
            anrPrefs.edit().remove(KEY_RESTART_VARIANT).apply()
        } else {
            val fqPrefs = ShoppingDemoApp.appContext.getSharedPreferences(FORCE_QUIT_PREFS_NAME, Context.MODE_PRIVATE)
            variantName = fqPrefs.getString(KEY_RESTART_VARIANT, null)
            if (variantName != null) {
                fqPrefs.edit().remove(KEY_RESTART_VARIANT).apply()
            }
        }
        if (variantName == null) return
        val variant = try { SimVariant.valueOf(variantName) } catch (_: Exception) { return }
        setVariant(variant)
    }

    fun cancel() {
        isCancelled = true
        ScreenLogger.logInfo(
            "simulation_cancelled",
            mapOf(
                "completed_runs" to currentRun.toString(),
                "total_runs" to totalRuns.toString()
            )
        )
    }

    /**
     * Indicates infinite simulation mode (-1 means infinite)
     */
    val isInfiniteMode: Boolean
        get() = totalRuns == -1

    private enum class AutoStartMode {
        NONE,
        SINGLE,
        INFINITE
    }

    private var pendingAutoStartMode = AutoStartMode.NONE

    fun scheduleAutoStart() {
        pendingAutoStartMode = AutoStartMode.SINGLE
    }

    fun scheduleAutoStartInfinite() {
        pendingAutoStartMode = AutoStartMode.INFINITE
    }

    fun tryAutoStart(navController: NavController) {
        when (pendingAutoStartMode) {
            AutoStartMode.NONE -> return
            AutoStartMode.SINGLE -> {
                pendingAutoStartMode = AutoStartMode.NONE
                simulate(1, navController)
            }
            AutoStartMode.INFINITE -> {
                pendingAutoStartMode = AutoStartMode.NONE
                infiniteSimulate(navController)
            }
        }
    }

    /**
     * Runs the simulation for a specified number of journeys
     */
    fun simulate(runs: Int, navController: NavController) {
        viewModelScope.launch {
            isSimulating = true
            isCancelled = false
            totalRuns = runs
            currentRun = 0
            ScreenLogger.logSimulationStart(runs)

            for (i in 1..runs) {
                if (isCancelled) break
                currentRun = i
                runSingleJourney(navController)
                if (isCancelled) break
                delay(50L)
            }

            val completedRuns = if (isCancelled) currentRun else runs
            ScreenLogger.logSimulationEnd(completedRuns)

            navController.navigate(Screen.Welcome.route) {
                popUpTo(Screen.Welcome.route) { inclusive = true }
            }

            isSimulating = false
            currentRun = 0
            totalRuns = 0
            isCancelled = false
        }
    }

    /**
     * A/B split sim: runs runsEach journeys as each variant in sequence.
     * Each run is a flag transition, maximizing workflow matches in the dashboard.
     */
    fun abSimulate(runsEach: Int, navController: NavController) {
        viewModelScope.launch {
            isSimulating = true
            isCancelled = false
            totalRuns = runsEach * 3
            currentRun = 0
            val variants = SimVariant.entries  // [CONTROL, VARIANT_A, VARIANT_B]

            ScreenLogger.logInfo("ab_simulation_start", mapOf("runs_each" to runsEach.toString()))

            for (i in 0 until totalRuns) {
                if (isCancelled) break
                activeVariant = variants[i % variants.size]
                currentRun++
                runSingleJourney(navController)
                delay(50L)
            }

            ScreenLogger.logInfo("ab_simulation_end", mapOf("total_runs" to currentRun.toString()))

            navController.navigate(Screen.Welcome.route) {
                popUpTo(Screen.Welcome.route) { inclusive = true }
            }

            isSimulating = false
            currentRun = 0
            totalRuns = 0
            isCancelled = false
        }
    }

    /**
     * Runs infinite simulation until cancelled
     */
    fun infiniteSimulate(navController: NavController) {
        viewModelScope.launch {
            isSimulating = true
            isCancelled = false
            totalRuns = -1  // -1 indicates infinite mode
            currentRun = 0

            // If crash loop is enabled, save a resume flag so the app can restart the
            // infinite loop after each crash (via AlarmManager restart)
            if (crashLoopEnabled) {
                val ctx = ShoppingDemoApp.appContext
                val prefs = ctx.getSharedPreferences(ShoppingDemoApp.PREFS, Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("resume_infinite_with_crash", true)
                    .putString(KEY_RESTART_VARIANT, activeVariant.name)
                    .commit()
            }

            ScreenLogger.logInfo("infinite_simulation_start", emptyMap())

            while (!isCancelled) {
                currentRun++
                runSingleJourney(navController)

                // Small delay between runs
                delay(50L)
            }

            ScreenLogger.logInfo("infinite_simulation_end", mapOf("total_runs" to currentRun.toString()))

            // Reset navigation to welcome screen
            navController.navigate(Screen.Welcome.route) {
                popUpTo(Screen.Welcome.route) { inclusive = true }
            }

            isSimulating = false
            currentRun = 0
            totalRuns = 0
            isCancelled = false
        }
    }

    /**
     * Cardinality demo: hammers /api/inventory/lookup/{item}/{session} with a
     * fresh random session path segment on every request, flooding the Bitdrift
     * dashboard with infinite-cardinality URLs. Runs until cancelled.
     */
    fun cardinalitySimulate(navController: NavController) {
        viewModelScope.launch {
            isSimulating = true
            isCancelled = false
            totalRuns = -1
            currentRun = 0

            ScreenLogger.logInfo("cardinality_simulation_start", emptyMap())

            while (!isCancelled) {
                currentRun++
                val item = searchQueries.random()
                try { ApiClient.inventoryLookup(item) } catch (_: Exception) {}
                delay(stepDelay)
            }

            ScreenLogger.logInfo(
                "cardinality_simulation_end",
                mapOf("total_runs" to currentRun.toString())
            )

            navController.navigate(Screen.Welcome.route) {
                popUpTo(Screen.Welcome.route) { inclusive = true }
            }

            isSimulating = false
            currentRun = 0
            totalRuns = 0
            isCancelled = false
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Fully random journey simulator — each journey walks through every
    // major step of the shopping funnel, randomly choosing a branch at
    // each decision point. Every journey always completes to Confirmation.
    //
    //  Welcome
    //    → discovery: Browse | Search | Categories→CategoryBrowse (random)
    //    → maybe Featured (coin flip)
    //    → ProductDetail
    //    → maybe Reviews (coin flip)
    //    → maybe Wishlist (coin flip)
    //    → Cart
    //    → checkout: CheckoutGuest | CheckoutSignIn (random)
    //    → payment: PaymentCard | PaymentApplePay | PaymentPayPal (random)
    //    → Confirmation
    // ═══════════════════════════════════════════════════════════════════════

    private val searchQueries = listOf(
        "headphones", "jacket", "running shoes", "laptop", "watch",
        "camera", "speaker", "backpack", "tablet", "sneakers"
    )

    private suspend fun nav(nc: NavController, route: String) {
        try {
            android.util.Log.d("SimNav", "→ navigating to: $route")
            nc.navigate(route)
        } catch (e: Exception) {
            android.util.Log.e("SimNav", "✗ nav FAILED for route: $route", e)
            throw e
        }
        delay(stepDelay)
    }

    // ─── API helpers ─────────────────────────────────────────────────────

    private suspend fun fetchBrowseIds(): List<String> = try {
        val arr = ApiClient.getBrowse().optJSONArray("products")
        if (arr != null) (0 until arr.length()).map { arr.getJSONObject(it).optString("id", "prod_a1b2c3") }.ifEmpty { listOf("prod_a1b2c3") }
        else listOf("prod_a1b2c3")
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun fetchSearchIds(): List<String> = try {
        val arr = ApiClient.search(searchQueries.random()).optJSONArray("products")
        if (arr != null) (0 until arr.length()).map { arr.getJSONObject(it).optString("id", "prod_a1b2c3") }.ifEmpty { listOf("prod_a1b2c3") }
        else listOf("prod_a1b2c3")
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun fetchFeaturedIds(): List<String> = try {
        val arr = ApiClient.getFeatured().optJSONArray("featured_products")
        if (arr != null) (0 until arr.length()).map { arr.getJSONObject(it).optString("id", "prod_a1b2c3") }.ifEmpty { listOf("prod_a1b2c3") }
        else listOf("prod_a1b2c3")
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    private suspend fun fetchCategoryNames(): List<String> = try {
        val arr = ApiClient.getCategories().optJSONArray("categories")
        if (arr != null) (0 until arr.length()).map { arr.getJSONObject(it).optString("name", "Electronics") }.ifEmpty { listOf("Electronics") }
        else listOf("Electronics")
    } catch (_: Exception) { listOf("Electronics") }

    private suspend fun fetchCategoryProductIds(cat: String): List<String> = try {
        val arr = ApiClient.getCategoryProducts(cat).optJSONArray("products")
        if (arr != null) (0 until arr.length()).map { arr.getJSONObject(it).optString("id", "prod_a1b2c3") }.ifEmpty { listOf("prod_a1b2c3") }
        else listOf("prod_a1b2c3")
    } catch (_: Exception) { listOf("prod_a1b2c3") }

    /**
     * Simulates a force-quit (swipe-up from recents) on the ProductDetail screen.
        * Requests a host-side recents swipe-dismiss so Android classifies exit as
        * user-requested app removal (rather than an in-process self-termination).
     * The Sankey shows ProductDetail → (dropout) since no subsequent screens are reached.
     */
    private fun maybeInjectForceQuit(): Boolean {
        if (!forceQuitEnabled) return false

        eligibleForceQuitJourneysSinceInject += 1
        val randomHit = Math.random() < FORCE_QUIT_PROBABILITY
        val forcedHit = isInfiniteMode && eligibleForceQuitJourneysSinceInject >= FORCE_QUIT_FORCE_AFTER_JOURNEYS
        if (!randomHit && !forcedHit) return false
        eligibleForceQuitJourneysSinceInject = 0

        val context = ShoppingDemoApp.appContext
        val prefs = context.getSharedPreferences(FORCE_QUIT_PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_RESTART_PENDING, true)
            .putBoolean(KEY_RESUME_INFINITE, isInfiniteMode)
            .putString(KEY_RESTART_VARIANT, activeVariant.name)
            .commit()

        ScreenLogger.logError(
            "force_quit_injected",
            mapOf(
                "force_quit_enabled" to "true",
                "force_quit_screen" to FORCE_QUIT_TARGET_SCREEN,
                "variant" to activeVariant.label,
                "trigger_mode" to if (forcedHit) "forced_infinite" else "random"
            )
        )

        // Stop scheduling new journeys and let the watchdog perform a recents dismiss.
        isCancelled = true

        return true
    }

    /**
     * Simulates an ANR on the CheckoutGuest screen — as if a synchronous
     * post-checkout validation call blocks the main thread.  Called after
     * nav() + API complete so the screen is rendered and focused; Android's
     * input dispatcher will detect the blocked thread and show the ANR dialog.
     * The Sankey shows CheckoutGuest → (dropout) since Payment is never reached.
     */
    private fun maybeInjectGuestAnr(isGuest: Boolean): Boolean {
        if (!anrAEnabled || activeVariant != SimVariant.VARIANT_A || !isGuest) {
            return false
        }

        eligibleAnrGuestJourneysSinceInject += 1
        val randomHit = Math.random() < ANR_PROBABILITY
        val forcedHit = isInfiniteMode && eligibleAnrGuestJourneysSinceInject >= ANR_FORCE_AFTER_ELIGIBLE_GUEST_JOURNEYS
        if (!randomHit && !forcedHit) {
            return false
        }
        eligibleAnrGuestJourneysSinceInject = 0

        val context = ShoppingDemoApp.appContext
        val prefs = context.getSharedPreferences(ANR_PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_RESTART_PENDING, true)
            .putBoolean(KEY_RESUME_INFINITE, isInfiniteMode)
            .putString(KEY_RESTART_VARIANT, activeVariant.name)
            .commit()

        ScreenLogger.logError(
            "guest_anr_injected",
            mapOf(
                "anr_a_enabled" to "true",
                "journey_type" to "guest",
                "anr_screen_name" to ANR_TARGET_SCREEN_NAME,
                "variant" to activeVariant.label,
                "trigger_mode" to if (forcedHit) "forced_infinite" else "random"
            )
        )

        // Block the main thread so Android classifies this as a real ANR.
        // Simulates a synchronous guest-session validation call that hangs.
        // The external watchdog script detects the ANR dialog, force-stops,
        // and relaunches the app.
        Thread.sleep(ANR_BLOCK_DURATION_MS)

        while (true) {
            Thread.sleep(ANR_HARD_FREEZE_SLEEP_MS)
        }
    }

    // ─── Crash cycling ───────────────────────────────────────────────────

    /**
     * Picks the next (crash type, foreground/background) combo in a deterministic
     * sweep and advances the persisted index. comboIdx cycles 0 until
     * Crashes.all.size * 2, so every crash type is guaranteed to occur in both
     * foreground and background exactly once per full sweep, rather than relying on
     * independent random coin-flips to eventually cover all combinations.
     */
    private fun pickNextCrashCombo(prefs: android.content.SharedPreferences): Triple<String, () -> Unit, Boolean> {
        val crashes = Crashes.all
        val totalCombos = crashes.size * 2
        val comboIdx = prefs.getInt(ShoppingDemoApp.KEY_NEXT_COMBO_INDEX, 0) % totalCombos
        // commit() not apply() — the process dies moments later
        prefs.edit()
            .putInt(ShoppingDemoApp.KEY_NEXT_COMBO_INDEX, (comboIdx + 1) % totalCombos)
            .commit()
        val (name, fn) = crashes[comboIdx / 2]
        val fireInBackground = comboIdx % 2 == 1
        return Triple(name, fn, fireInBackground)
    }

    /**
     * Fires fn(), backgrounding the app first via moveTaskToBack if fireInBackground
     * and an Activity is available — waiting BACKGROUND_SETTLE_MS for ActivityManager
     * to actually demote process importance away from foreground before the crash
     * lands. Otherwise fires after the shorter CRASH_FLUSH_MS SDK-flush window.
     */
    private fun dispatchCrash(fn: () -> Unit, fireInBackground: Boolean, activity: android.app.Activity?) {
        if (fireInBackground && activity != null) {
            activity.moveTaskToBack(true)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                fn()
            }, BACKGROUND_SETTLE_MS)
            return
        }
        // Foreground path, or no Activity available to background with. Mirror
        // crashdemo exactly: fire from a plain main-thread runnable, outside coroutine
        // machinery, with a blocking flush window so the SDK persists the crash report
        // and preceding logs before the process dies.
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try { Thread.sleep(CRASH_FLUSH_MS) } catch (_: InterruptedException) {}
            fn()
        }
    }

    /**
     * If crash loop is enabled, picks the next crash combo, logs it, pre-schedules an
     * AlarmManager restart (survives native signals), then dispatches the crash.
     * Called once per completed shopping journey from runSingleJourney().
     */
    private fun maybeFireCrash(nc: NavController) {
        if (!crashLoopEnabled) return
        val ctx = ShoppingDemoApp.appContext
        val prefs = ctx.getSharedPreferences(ShoppingDemoApp.PREFS, Context.MODE_PRIVATE)
        val (name, fn, fireInBackground) = pickNextCrashCombo(prefs)
        val crashContext = if (fireInBackground) "background" else "foreground"
        Logger.addField("crash_kind", name)
        Logger.addField("crash_context", crashContext)
        Logger.logWarning { "about_to_crash: $name (context=$crashContext)" }
        // Pre-schedule the restart BEFORE the crash — AlarmManager survives even
        // SIGSEGV/SIGBUS where the JVM uncaught-exception handler cannot run.
        ShoppingDemoApp.scheduleRestart(ctx, CRASH_RESTART_DELAY_MS)
        // Stop the simulator loop so it does not start another journey (and a fresh
        // session) racing the crash — the crash must land in the session that holds
        // the about_to_crash breadcrumb. The AlarmManager restart resumes the loop.
        isCancelled = true
        val activity = if (fireInBackground) nc.context as? android.app.Activity else null
        dispatchCrash(fn, fireInBackground, activity)
    }

    /**
     * Fast crash-loop entry point: skips the shopping journey entirely. Picks the
     * next combo and fires immediately, relying on the AlarmManager restart to
     * relaunch through the startup splash — which MainActivity is wired to skip when
     * fast mode is active — and MainActivity re-invoking this from the Welcome
     * screen on every relaunch. Self-sustaining across process restarts; no Sim
     * button or journey is involved.
     */
    fun fireFastCrash(activity: android.app.Activity?) {
        if (!crashLoopEnabled || !fastCrashModeEnabled) return
        val ctx = ShoppingDemoApp.appContext
        val prefs = ctx.getSharedPreferences(ShoppingDemoApp.PREFS, Context.MODE_PRIVATE)
        val (name, fn, fireInBackground) = pickNextCrashCombo(prefs)
        val crashContext = if (fireInBackground) "background" else "foreground"
        Logger.startNewSession()
        Logger.addField("crash_kind", name)
        Logger.addField("crash_context", crashContext)
        Logger.logWarning { "about_to_crash (fast): $name (context=$crashContext)" }
        ShoppingDemoApp.scheduleRestart(ctx, CRASH_RESTART_DELAY_MS)
        dispatchCrash(fn, fireInBackground, activity)
    }

    // ─── The single journey ──────────────────────────────────────────────

    private suspend fun runSingleJourney(nc: NavController) {
        // Keep force-quit runs in the startup session so workflows that begin with
        // SDK configuration and end with app termination can match in a single session.
        if (!forceQuitEnabled) {
            Logger.startNewSession()
            ScreenLogger.logInfo(
                "journey_started",
                mapOf("run" to currentRun.toString(), "variant" to activeVariant.label)
            )
            // Give the SDK time to fully initialise the new session before recording exposures
            delay(200L)
            // Re-apply flag exposures after startNewSession() — exposure is per-session,
            // so it must be recorded again on the new session for the dashboard to detect it.
            setVariant(activeVariant)
            // Small settle time so the exposure is fully registered before the first journey log
            delay(200L)
        }

        // Rotate through the fixed entity list so each journey appears as a different user
        // in the bitdrift Entities view. currentRun is 1-indexed, so subtract 1 before mod.
        val entity = DEMO_ENTITIES[(currentRun - 1) % DEMO_ENTITIES.size]
        // bitdrift SDK: setEntityId() associates all subsequent logs with this user identity.
        // POC: ad-hoc debugging — search any entity in the dashboard to retrieve all their sessions on demand
        Logger.setEntityId(entity)

        // bitdrift SDK: startSpan() opens a root span for the journey. All logs are
        // correlated via _span_id; child spans form a two-level hierarchy in the timeline.
        // POC: spans waterfall visualization in Timeline; query _duration_ms for p50/p95 of any flow
        val journeySpan = Logger.startSpan(
            name = "journey",
            level = LogLevel.INFO,
            fields = mapOf("variant" to activeVariant.label, "entity" to entity),
        )
        // Tracks the discovery phase: Welcome → Browse/Search/Categories → ProductDetail → Cart.
        // Ends with SUCCESS when the first item is added to cart.
        val discoverySpan = Logger.startSpan(
            name = "product_discovery",
            level = LogLevel.INFO,
            fields = mapOf("variant" to activeVariant.label),
            parentSpanId = journeySpan?.id,
        )

        // ── Step 1: Welcome ──────────────────────────────────────────────
        nc.navigate(Screen.Welcome.route) { popUpTo(Screen.Welcome.route) { inclusive = true } }
        try { ApiClient.getWelcome() } catch (_: Exception) {}
        delay(stepDelay)

        // ── Step 2: Discovery — randomly pick Browse, Search, or Categories
        var productIds: List<String>
        var source: String
        // Discovery is variant-biased but still random:
        //   A (digital native)  — 45% Search, 40% Browse, 15% Categories (knows what they want)
        //   B (deliberate)      — 50% Categories, 25% Browse, 25% Search (systematic exploration)
        //   Control             — equal 33 / 33 / 33
        val discoveryRoll = Math.random()
        val discoveryChoice = when (activeVariant) {
            SimVariant.VARIANT_A -> if (discoveryRoll < 0.40) 0 else if (discoveryRoll < 0.85) 1 else 2
            SimVariant.VARIANT_B -> if (discoveryRoll < 0.25) 0 else if (discoveryRoll < 0.50) 1 else 2
            SimVariant.CONTROL   -> (0..2).random()
        }
        when (discoveryChoice) {
            0 -> {
                // Browse
                nav(nc, Screen.Browse.route)
                productIds = fetchBrowseIds()
                source = "browse"
            }
            1 -> {
                // Search
                nav(nc, Screen.Search.route)
                productIds = fetchSearchIds()
                source = "search"
            }
            else -> {
                // Categories → CategoryBrowse
                nav(nc, Screen.Categories.route)
                val cats = fetchCategoryNames()
                val cat = cats.random()
                nav(nc, Screen.CategoryBrowse(cat).route)
                productIds = fetchCategoryProductIds(cat)
                source = "categories"
            }
        }

        // ── Maybe visit Featured — A skips it (15%), B always browses (75%)
        val featuredProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.5
            SimVariant.VARIANT_A -> 0.15  // decisive, goes straight to product
            SimVariant.VARIANT_B -> 0.75  // comparison shopper, checks everything
        }
        if (Math.random() < featuredProb) {
            nav(nc, Screen.FeaturedProducts.route)
            val featIds = fetchFeaturedIds()
            productIds = featIds
            source = "featured"
        }

        val pid = productIds.random()

        // ── Step 3: ProductDetail ────────────────────────────────────────
        nav(nc, Screen.ProductDetail(source, pid).route)
        try { ApiClient.getProduct(pid) } catch (_: Exception) {}

        // Force-quit injection: fires after ProductDetail renders + API completes.
        // Simulates the user swiping up from recents on an uninteresting product page.
        if (maybeInjectForceQuit()) return

        // ── Maybe visit Reviews — A rarely does (10%), B almost always does (90%)
        val reviewsProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.5
            SimVariant.VARIANT_A -> 0.10  // trusts the product, skips reviews
            SimVariant.VARIANT_B -> 0.90  // reads every review before deciding
        }
        if (Math.random() < reviewsProb) {
            nav(nc, Screen.Reviews(source, pid).route)
            try { ApiClient.getReviews(pid) } catch (_: Exception) {}
        }

        // ── Maybe visit Wishlist — A almost never (5%), B very often (75%)
        val wishlistProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.4
            SimVariant.VARIANT_A -> 0.05  // immediate buyer, doesn't save for later
            SimVariant.VARIANT_B -> 0.75  // saves many items before committing
        }
        if (Math.random() < wishlistProb) {
            nav(nc, Screen.Wishlist(pid).route)
            try { ApiClient.addToWishlist(pid) } catch (_: Exception) {}
        }

        // ── Step 4: Cart — add items; A adds just 1, B loads up with 3-5
        val cartItems = mutableListOf(pid)
        nav(nc, Screen.Cart(pid).route)
        try { ApiClient.addToCart(pid) } catch (_: Exception) {}
        // Discovery phase complete — first item is in the cart.
        discoverySpan?.end(SpanResult.SUCCESS, mapOf("source" to source, "product_id" to pid))

        val extraCount = when (activeVariant) {
            SimVariant.CONTROL   -> (1..3).random()   // 1-3 extra
            SimVariant.VARIANT_A -> (0..1).random()   // usually 1 item, occasionally grabs a second
            SimVariant.VARIANT_B -> (2..4).random()   // loads up the cart
        }
        for (i in 0 until extraCount) {
            val extraPid = productIds.random()
            cartItems.add(extraPid)
            try { ApiClient.addToCart(extraPid, quantity = (1..3).random()) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // View the cart
        try { ApiClient.getCart() } catch (_: Exception) {}
        delay(stepDelay)

        // Maybe remove an item — A almost never (10%), B almost always (90%)
        val removeProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.6
            SimVariant.VARIANT_A -> 0.10  // keeps what they add
            SimVariant.VARIANT_B -> 0.90  // constant second-guessing
        }
        if (Math.random() < removeProb && cartItems.size > 1) {
            val removeIdx = cartItems.indices.random()
            val removePid = cartItems.removeAt(removeIdx)
            try { ApiClient.deleteCartItem(removePid) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // Maybe empty cart and re-add — A almost never (5%), B very often (60%)
        val emptyCartProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.2
            SimVariant.VARIANT_A -> 0.05  // commits to their choice
            SimVariant.VARIANT_B -> 0.60  // starts over frequently
        }
        if (Math.random() < emptyCartProb) {
            for (item in cartItems.toList()) {
                try { ApiClient.deleteCartItem(item) } catch (_: Exception) {}
                delay(stepDelay)
            }
            cartItems.clear()
            // Re-add one product so checkout works
            val rePid = productIds.random()
            cartItems.add(rePid)
            try { ApiClient.addToCart(rePid) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // Maybe remove and re-add same item — A almost never (5%), B very often (70%)
        val flipProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.3
            SimVariant.VARIANT_A -> 0.05  // no quantity dithering
            SimVariant.VARIANT_B -> 0.70  // changes quantity repeatedly
        }
        if (Math.random() < flipProb && cartItems.isNotEmpty()) {
            val flippedPid = cartItems.random()
            try { ApiClient.deleteCartItem(flippedPid) } catch (_: Exception) {}
            delay(stepDelay)
            try { ApiClient.addToCart(flippedPid, quantity = (1..5).random()) } catch (_: Exception) {}
            delay(stepDelay)
        }

        // View cart one more time before checkout
        try { ApiClient.getCart() } catch (_: Exception) {}
        delay(stepDelay)

        // ── Cart abandonment — A (impulsive): 15%, Control: 5%, B (deliberate): 0%
        val cartAbandonProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.05
            SimVariant.VARIANT_A -> 0.15
            SimVariant.VARIANT_B -> 0.0
        }
        if (Math.random() < cartAbandonProb) {
            ScreenLogger.logInfo(
                "cart_abandoned",
                mapOf(
                    "items_in_cart" to cartItems.size.toString(),
                    "variant" to activeVariant.label
                )
            )
            android.util.Log.d("SimNav", "✗ cart_abandoned, items=${cartItems.size}, variant=${activeVariant.label}")
            delay(200L)
            journeySpan?.end(SpanResult.CANCELED, mapOf("reason" to "cart_abandoned"))
            return
        }

        val checkoutPid = cartItems.lastOrNull() ?: pid

        // ── Step 5: Checkout — A almost always guest (95%), B almost always signin (95%)
        val guestProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.5    // 50/50 baseline
            SimVariant.VARIANT_A -> 0.95   // never bothers with an account
            SimVariant.VARIANT_B -> 0.05   // always signs in for loyalty points
        }
        // Keep ANR-A behavior deterministic across environments: when ANR-A is enabled
        // and Variant A is selected, always take the guest checkout branch.
        val isGuest = if (anrAEnabled && activeVariant == SimVariant.VARIANT_A) {
            true
        } else {
            Math.random() < guestProb
        }
        // Checkout span: child of the journey span, covers Checkout → Payment → Confirmation.
        // parentSpanId links it to the root journey span so both appear together in the timeline.
        val checkoutSpan = Logger.startSpan(
            name = "checkout",
            level = LogLevel.INFO,
            fields = mapOf("checkout_type" to if (isGuest) "guest" else "signin"),
            parentSpanId = journeySpan?.id,
        )
        val session: String
        if (isGuest) {
            nav(nc, Screen.CheckoutGuest(checkoutPid).route)
            session = try { ApiClient.checkoutGuest().optString("checkout_session", "") } catch (_: Exception) { "" }
            // ANR injection: fires after the checkout API call completes, which
            // gives Compose time to render the screen and establish window focus.
            // The Sankey shows CheckoutGuest → (dropout) since Payment is never reached.
            if (maybeInjectGuestAnr(isGuest)) return
        } else {
            nav(nc, Screen.CheckoutSignIn(checkoutPid).route)
            session = try { ApiClient.checkoutSignIn().optString("checkout_session", "") } catch (_: Exception) { "" }
        }

        // ── Checkout dropout — Guest (Variant A): 35%, SignIn (Variant B): 5%, Control: 0%
        val checkoutDropoutProb = when (activeVariant) {
            SimVariant.CONTROL   -> 0.0
            SimVariant.VARIANT_A -> 0.35
            SimVariant.VARIANT_B -> 0.05
        }
        if (Math.random() < checkoutDropoutProb) {
            val checkoutType = if (isGuest) "guest" else "signin"
            ScreenLogger.logInfo(
                "checkout_abandoned",
                mapOf(
                    "checkout_type" to checkoutType,
                    "variant" to activeVariant.label
                )
            )
            android.util.Log.d("SimNav", "✗ checkout_abandoned, type=$checkoutType, variant=${activeVariant.label}")
            delay(200L)
            checkoutSpan?.end(SpanResult.CANCELED, mapOf("reason" to "checkout_abandoned"))
            journeySpan?.end(SpanResult.CANCELED, mapOf("reason" to "checkout_abandoned"))
            return
        }

        // ── Step 6: Payment — A uses digital (Apple Pay / PayPal / Android Pay), B uses card only
        // 0=card, 1=apple_pay, 2=paypal, 3=android_pay
        val paymentChoice = when (activeVariant) {
            SimVariant.CONTROL -> (0..3).random()   // equal 25/25/25/25
            SimVariant.VARIANT_A -> {               // 5% card, 40% Apple Pay, 35% PayPal, 20% Android Pay
                val r = Math.random()
                if (r < 0.05) 0 else if (r < 0.45) 1 else if (r < 0.80) 2 else 3
            }
            SimVariant.VARIANT_B -> {               // 95% card, 3% Apple Pay, 2% PayPal, 0% Android Pay
                val r = Math.random()
                if (r < 0.95) 0 else if (r < 0.98) 1 else 2
            }
        }
        val paymentMethod = when (paymentChoice) {
            0 -> "card"
            1 -> "apple_pay"
            2 -> "paypal"
            else -> "android_pay"
        }

        // ── Payment failure simulation ────────────────────────────────────
        // Android Pay has its own elevated failure rates; other methods use variant-level rates.
        // Control: 15% (30% for Android Pay), Guest (A): 35% (20% for Android Pay), SignIn (B): 5% (never uses Android Pay)
        val failureProb = if (paymentMethod == "android_pay") {
            when (activeVariant) {
                SimVariant.CONTROL   -> 0.30
                SimVariant.VARIANT_A -> 0.20
                SimVariant.VARIANT_B -> 0.0   // never reaches here — signin doesn't use Android Pay
            }
        } else {
            when (activeVariant) {
                SimVariant.CONTROL   -> 0.15
                SimVariant.VARIANT_A -> 0.35
                SimVariant.VARIANT_B -> 0.05
            }
        }
        val willPaymentFail = Math.random() < failureProb

        val orderId: String
        when (paymentChoice) {
            0 -> {
                nav(nc, Screen.PaymentCard(session).route)
                orderId = try { ApiClient.payCard(session).optString("order_id", "") } catch (_: Exception) { "" }
            }
            1 -> {
                nav(nc, Screen.PaymentApplePay(session).route)
                orderId = try { ApiClient.payApplePay(session).optString("order_id", "") } catch (_: Exception) { "" }
            }
            2 -> {
                nav(nc, Screen.PaymentPayPal(session).route)
                orderId = try { ApiClient.payPayPal(session).optString("order_id", "") } catch (_: Exception) { "" }
            }
            else -> {
                nav(nc, Screen.PaymentAndroidPay(session).route)
                orderId = try { ApiClient.payAndroidPay(session).optString("order_id", "") } catch (_: Exception) { "" }
            }
        }

        if (willPaymentFail) {
            ScreenLogger.logError(
                "payment_failed",
                mapOf(
                    "payment_method" to paymentMethod,
                    "checkout_session" to session,
                    "variant" to activeVariant.label
                )
            )
            android.util.Log.d("SimNav", "✗ payment_failed, method=$paymentMethod, variant=${activeVariant.label}")

            // Navigate to the PaymentFailed screen so it appears in the Sankey
            nav(nc, Screen.PaymentFailed(paymentMethod, session).route)
            delay(200L)

            // ── Payment retry: 50% chance to retry with a different method
            val retryProb = 0.50
            if (Math.random() < retryProb) {
                // Pick a different payment method for retry
                val retryMethods = listOf(0, 1, 2, 3).filter { it != paymentChoice }
                val retryChoice = retryMethods.random()
                val retryMethod: String
                val retryOrderId: String
                when (retryChoice) {
                    0 -> {
                        nav(nc, Screen.PaymentCard(session).route)
                        retryOrderId = try { ApiClient.payCard(session).optString("order_id", "") } catch (_: Exception) { "" }
                        retryMethod = "card"
                    }
                    1 -> {
                        nav(nc, Screen.PaymentApplePay(session).route)
                        retryOrderId = try { ApiClient.payApplePay(session).optString("order_id", "") } catch (_: Exception) { "" }
                        retryMethod = "apple_pay"
                    }
                    2 -> {
                        nav(nc, Screen.PaymentPayPal(session).route)
                        retryOrderId = try { ApiClient.payPayPal(session).optString("order_id", "") } catch (_: Exception) { "" }
                        retryMethod = "paypal"
                    }
                    else -> {
                        nav(nc, Screen.PaymentAndroidPay(session).route)
                        retryOrderId = try { ApiClient.payAndroidPay(session).optString("order_id", "") } catch (_: Exception) { "" }
                        retryMethod = "android_pay"
                    }
                }
                ScreenLogger.logInfo(
                    "payment_retry",
                    mapOf(
                        "original_method" to paymentMethod,
                        "retry_method" to retryMethod,
                        "variant" to activeVariant.label
                    )
                )
                android.util.Log.d("SimNav", "↻ payment_retry, $paymentMethod → $retryMethod")

                // Retry succeeds — proceed to confirmation with retried order ID
                setVariant(activeVariant)
                delay(100L)
                nav(nc, Screen.Confirmation(retryOrderId).route)
                Logger.logInfo(
                    mapOf("_screen_name" to "Confirmation", "payment_retried" to "true", "retry_method" to retryMethod)
                ) { "confirmation_reached" }
                try { ApiClient.getConfirmation(retryOrderId) } catch (_: Exception) {}
                delay(200L)
                checkoutSpan?.end(SpanResult.SUCCESS, mapOf("payment_method" to retryMethod, "retried" to "true"))
                journeySpan?.end(SpanResult.SUCCESS)
                maybeFireCrash(nc)
            return
        }

        // ── Step 7: Confirmation ─────────────────────────────────────────
        android.util.Log.d("SimNav", "★ REACHED Confirmation step, orderId=$orderId, variant=${activeVariant.label}")
        // Re-assert flag exposure right before Confirmation to guarantee it's on this session
        setVariant(activeVariant)
        delay(100L)
        nav(nc, Screen.Confirmation(orderId).route)
        // Emit an explicit tagged log so we can verify fields in the raw stream
        Logger.logInfo(
            mapOf("_screen_name" to "Confirmation", "checkout_flow" to when (activeVariant) {
                SimVariant.CONTROL -> "random"; SimVariant.VARIANT_A -> "guest"; SimVariant.VARIANT_B -> "signin"
            })
        ) { "confirmation_reached" }
        try { ApiClient.getConfirmation(orderId) } catch (_: Exception) {}
        // Extra settle time so Compose's DisposableEffect fires logScreenView("Confirmation")
        // before the next journey's startNewSession() clears session-level flag state.
        delay(200L)
        android.util.Log.d("SimNav", "★ Confirmation DONE, variant=${activeVariant.label}")
        checkoutSpan?.end(SpanResult.SUCCESS, mapOf("payment_method" to paymentMethod))
        journeySpan?.end(SpanResult.SUCCESS)
        maybeFireCrash(nc)
    }
    }

    companion object {
        private const val CRASH_RESTART_DELAY_MS = 2000L
        private const val CRASH_FLUSH_MS = 300L
        // Longer than CRASH_FLUSH_MS: gives ActivityManager time to actually demote
        // process importance away from foreground after moveTaskToBack, before the
        // crash fires. Empirical starting point — validate against reported
        // app_metrics.running_state and tune if crashes still land as foreground.
        private const val BACKGROUND_SETTLE_MS = 2000L
        const val KEY_RESTART_VARIANT = "restart_variant"

        val DEMO_ENTITIES = listOf(
            "Groucho", "Harpo", "Chico", "Gummo", "Zeppo",
            "Moe", "Larry", "Curly", "Abbott", "Costello"
        )

        const val ANR_PREFS_NAME = "anr_a"
        const val KEY_ANR_A_ACTIVE = "active"
        const val KEY_RESTART_PENDING = "restart_pending"
        const val KEY_RESUME_INFINITE = "resume_infinite"
        private const val ANR_TARGET_SCREEN_NAME = "CheckoutGuest"
        private const val ANR_PROBABILITY = 0.25
        private const val ANR_FORCE_AFTER_ELIGIBLE_GUEST_JOURNEYS = 6
        private const val ANR_BLOCK_DURATION_MS = 15000L
        private const val ANR_HARD_FREEZE_SLEEP_MS = 60000L

        const val FORCE_QUIT_PREFS_NAME = "force_quit"
        const val KEY_FORCE_QUIT_ACTIVE = "active"
        private const val FORCE_QUIT_TARGET_SCREEN = "ProductDetail"
        private const val FORCE_QUIT_PROBABILITY = 0.60
        private const val FORCE_QUIT_FORCE_AFTER_JOURNEYS = 3
    }
}
