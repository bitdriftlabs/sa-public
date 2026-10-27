package ai.bitdrift.shop

import ai.bitdrift.shop.generated.*
import ai.bitdrift.shop.generated.SpecJourney
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlin.coroutines.cancellation.CancellationException
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.SpanResult
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// bitdrift SDK: SimVariant drives setFeatureFlagExposure() calls so every log in a run is
// tagged with the active cohort, enabling dashboard slicing by checkout_flow, payment_ui,
// and cart_abandon_rate.
// `id` is the spec persona id (personas.yaml), which selects the journey's probability table.
enum class SimVariant(val id: String, val label: String) {
    CONTROL("control", SpecPersonas.CONTROL),        // baseline: fully random, no variant bias
    VARIANT_A("variant_a", SpecPersonas.VARIANT_A),  // digital native: snap decisions, skips research, guest + digital pay
    VARIANT_B("variant_b", SpecPersonas.VARIANT_B)   // deliberate shopper: reads everything, huge cart churn, signin + card
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

    var recommendationsV2Enabled by mutableStateOf(false)

    var crashLoopEnabled by mutableStateOf(false)

    // Fast crash mode: skips the shopping journey entirely and fires the next crash
    // combo immediately on every relaunch (see fireFastCrash). Selected on the startup
    // splash screen alongside crashLoopEnabled, not from Advanced settings.
    var fastCrashModeEnabled by mutableStateOf(false)

    // Surfaces what fireFastCrash() is about to do so the UI can show a full-screen
    // splash instead of looking hung -- fast mode skips all navigation/UI by design,
    // so without this there's no on-device signal distinguishing "about to crash in
    // 300ms" from "stuck".
    data class FastCrashStatus(val kind: String, val context: String, val oomOnly: Boolean)

    var fastCrashStatus by mutableStateOf<FastCrashStatus?>(null)
        private set

    var anrAEnabled by mutableStateOf(false)

    var forceQuitEnabled by mutableStateOf(false)

    // Flag to signal cancellation
    private var isCancelled = false

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
        RecordingLogger.setFeatureFlagExposure(SpecFlags.CHECKOUT_FLOW, checkoutFlow)
        RecordingLogger.setFeatureFlagExposure(SpecFlags.PAYMENT_UI, paymentUi)
        RecordingLogger.setFeatureFlagExposure(SpecFlags.CART_ABANDON_RATE, cartAbandon)
        // Also set as global fields so every log carries the active flag values for debugging
        RecordingLogger.addField(SpecFields.FF_CHECKOUT_FLOW, checkoutFlow)
        RecordingLogger.addField(SpecFields.FF_PAYMENT_UI, paymentUi)
        RecordingLogger.addField(SpecFields.FF_CART_ABANDON_RATE, cartAbandon)
        RecordingLogger.addField(SpecFields.FF_VARIANT, variant.label)
        // Android Pay flag: enabled for Control + Variant A, disabled for Variant B
        val androidPay = when (variant) {
            SimVariant.CONTROL   -> "enabled"
            SimVariant.VARIANT_A -> "enabled"
            SimVariant.VARIANT_B -> "disabled"
        }
        RecordingLogger.setFeatureFlagExposure(SpecFlags.PAYMENT_ANDROID_PAY, androidPay)
        RecordingLogger.addField(SpecFields.FF_PAYMENT_ANDROID_PAY, androidPay)
        val orderSummary = if (crashLoopEnabled) "v2" else "v1"
        RecordingLogger.setFeatureFlagExposure(SpecFlags.ORDER_SUMMARY, orderSummary)
        RecordingLogger.addField(SpecFields.FF_ORDER_SUMMARY, orderSummary)
        val anrAState = if (anrAEnabled) "enabled" else "disabled"
        RecordingLogger.setFeatureFlagExposure(SpecFlags.ANR_A, anrAState)
        RecordingLogger.addField(SpecFields.FF_ANR_A, anrAState)
        val forceQuitState = if (forceQuitEnabled) "enabled" else "disabled"
        RecordingLogger.setFeatureFlagExposure(SpecFlags.FORCE_QUIT, forceQuitState)
        RecordingLogger.addField(SpecFields.FF_FORCE_QUIT, forceQuitState)
        val recommendationsV2State = if (recommendationsV2Enabled) "enabled" else "disabled"
        RecordingLogger.setFeatureFlagExposure(SpecFlags.RECOMMENDATIONS_V2, recommendationsV2State)
        RecordingLogger.addField(SpecFields.FF_RECOMMENDATIONS_V2, recommendationsV2State)
        // Emit an explicit log so we can verify flag exposure in the log stream
        RecordingLogger.logInfo { SpecEvents.FEATURE_FLAG_EXPOSURE_SET }
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
        val variant = try { SimVariant.valueOf(variantName) } catch (ce: CancellationException) { throw ce } catch (_: Exception) { return }
        setVariant(variant)
    }

    fun cancel() {
        isCancelled = true
        ScreenLogger.logInfo(
            SpecEvents.SIMULATION_CANCELLED,
            mapOf(
                SpecFields.COMPLETED_RUNS to currentRun.toString(),
                SpecFields.TOTAL_RUNS to totalRuns.toString()
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
    fun simulate(runs: Int, navController: NavController, seed: Long? = null): kotlinx.coroutines.Job {
        return viewModelScope.launch {
            isSimulating = true
            isCancelled = false
            totalRuns = runs
            currentRun = 0
            simSeed = seed ?: newSimSeed()
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
     * Test-harness autorun (launch arguments, see [AutorunConfig]): runs [AutorunConfig.runs]
     * journeys as the requested persona, then logs [SpecEvents.SIM_AUTORUN_COMPLETE] so
     * the script driving the app knows to stop waiting. Lives in the view model's scope so
     * it survives the Welcome screen being recomposed when the sim navigates home.
     */
    fun autorun(navController: NavController) {
        viewModelScope.launch {
            val runs = AutorunConfig.runs
            setVariant(AutorunConfig.variant())
            simulate(runs, navController, AutorunConfig.seed and 0x7FFFFFFFL).join()
            ScreenLogger.logInfo(
                SpecEvents.SIM_AUTORUN_COMPLETE,
                mapOf(
                    SpecFields.TOTAL_RUNS to runs.toString(),
                    SpecFields.SIM_SEED to (AutorunConfig.seed and 0x7FFFFFFFL).toString(),
                    SpecFields.PERSONA to AutorunConfig.persona,
                )
            )
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
            simSeed = newSimSeed()
            val variants = SimVariant.entries  // [CONTROL, VARIANT_A, VARIANT_B]

            ScreenLogger.logInfo(SpecEvents.AB_SIMULATION_START, mapOf(SpecFields.RUNS_EACH to runsEach.toString()))

            for (i in 0 until totalRuns) {
                if (isCancelled) break
                activeVariant = variants[i % variants.size]
                currentRun++
                runSingleJourney(navController)
                delay(50L)
            }

            ScreenLogger.logInfo(SpecEvents.AB_SIMULATION_END, mapOf(SpecFields.TOTAL_RUNS to currentRun.toString()))

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
            simSeed = newSimSeed()

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

            ScreenLogger.logInfo(SpecEvents.INFINITE_SIMULATION_START, emptyMap())

            while (!isCancelled) {
                currentRun++
                runSingleJourney(navController)

                // Small delay between runs
                delay(50L)
            }

            ScreenLogger.logInfo(SpecEvents.INFINITE_SIMULATION_END, mapOf(SpecFields.TOTAL_RUNS to currentRun.toString()))

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

            ScreenLogger.logInfo(SpecEvents.CARDINALITY_SIMULATION_START, emptyMap())

            while (!isCancelled) {
                currentRun++
                val item = searchQueries.random()
                try { ApiClient.inventoryLookup(item) } catch (ce: CancellationException) { throw ce } catch (_: Exception) {}
                delay(50L)
            }

            ScreenLogger.logInfo(
                SpecEvents.CARDINALITY_SIMULATION_END,
                mapOf(SpecFields.TOTAL_RUNS to currentRun.toString())
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

    // The journey itself is data: spec/journey.yaml, interpreted by JourneyEngine
    // (identically on iOS, React Native and Flutter). This class keeps only what is
    // Android-specific: navigation, the API client, the SDK calls, and how each fault
    // physically happens (journeyAdapter below).

    // Cardinality demo search terms (personas.yaml sim_data.search_terms).
    private val searchQueries = listOf(
        "headphones", "jacket", "running shoes", "laptop", "watch",
        "camera", "speaker", "backpack", "tablet", "sneakers"
    )

    /** Seed for the current simulation: the autorun seed, else random. Logged as sim_seed. */
    private var simSeed = 0L

    private fun newSimSeed(): Long = (Math.random() * 2147483647.0).toLong()

    private var navController: NavController? = null

    private val journeyAdapter = object : JourneyAdapter {
        override fun isCancelled() = isCancelled
        // In `realistic` session mode the SDK's inactivity timeout owns session boundaries, so one
        // session spans several journeys; only `per_journey` (the default) starts one per journey.
        override fun startNewSession() {
            if (DemoSettings.activeSessionMode == SessionMode.PER_JOURNEY) RecordingLogger.startNewSession()
        }
        override fun applyExposures(persona: String) = setVariant(activeVariant)
        override fun setEntity(entity: String) {
            // bitdrift SDK: setEntityId() associates all subsequent logs with this user identity.
            // POC: ad-hoc debugging — search any entity in the dashboard to retrieve all their sessions on demand
            RecordingLogger.setEntityId(entity)
        }
        override suspend fun delay(ms: Long) = kotlinx.coroutines.delay(ms)

        override suspend fun navigate(screen: String, args: Map<String, String>) {
            val nc = navController ?: return
            val spec = SpecScreen.entries.first { it.id == screen }
            // `step` is a global field, so every log, span and crash report carries where the journey is.
            RecordingLogger.addField(SpecFields.STEP, screen)
            val route = args.entries.fold(spec.route) { r, (k, v) -> r.replace("{$k}", v) }
            android.util.Log.d("SimNav", "→ navigating to: $route")
            if (spec == SpecScreen.WELCOME) {
                nc.navigate(route) { popUpTo(Screen.Welcome.route) { inclusive = true } }
            } else {
                nc.navigate(route)
            }
        }

        // Latest cart response, so checkout_started can carry it as cart_json.
        private var lastCart: org.json.JSONObject? = null

        override suspend fun callApi(endpoint: String, args: Map<String, String>): org.json.JSONObject? {
            val result = callApiRaw(endpoint, args)
            when (endpoint) {
                "cart_get", "cart_add", "cart_delete" -> lastCart = result
                "confirmation" -> if (result == null) {
                    // Payment succeeded but the order cannot be shown: a business-critical failure.
                    RecordingLogger.logCritical(
                        mapOf(SpecFields.ORDER_ID to (args["id"] ?: ""), SpecFields.REASON to "confirmation_unavailable")
                    ) { SpecEvents.ORDER_LOST }
                }
            }
            return result
        }

        private suspend fun callApiRaw(endpoint: String, args: Map<String, String>): org.json.JSONObject? = try {
            fun a(k: String) = args[k] ?: ""
            if (endpoint == "confirmation" && DemoSettings.loseOrders(ShoppingDemoApp.appContext)) {
                throw java.io.IOException("order lookup disabled (demo: lose orders)")
            }
            when (endpoint) {
                "welcome" -> ApiClient.getWelcome()
                "browse" -> ApiClient.getBrowse()
                "search" -> ApiClient.search(a("q"))
                "featured" -> ApiClient.getFeatured()
                "categories" -> ApiClient.getCategories()
                "category_products" -> ApiClient.getCategoryProducts(a("category"))
                "product" -> ApiClient.getProduct(a("id"))
                "reviews" -> ApiClient.getReviews(a("id"))
                "cart_get" -> ApiClient.getCart()
                "cart_add" -> ApiClient.addToCart(a("product_id"), a("quantity").toIntOrNull() ?: 1)
                "cart_delete" -> ApiClient.deleteCartItem(a("id"))
                "wishlist_add" -> ApiClient.addToWishlist(a("product_id"))
                "checkout_guest" -> ApiClient.checkoutGuest()
                "checkout_signin" -> ApiClient.checkoutSignIn()
                "pay_card" -> ApiClient.payCard(a("checkout_session"), args["card_last4"] ?: "4242")
                "pay_apple_pay" -> ApiClient.payApplePay(a("checkout_session"))
                "pay_paypal" -> ApiClient.payPayPal(a("checkout_session"))
                "pay_android_pay" -> ApiClient.payAndroidPay(a("checkout_session"))
                "confirmation" -> ApiClient.getConfirmation(a("id"))
                else -> error("unknown endpoint $endpoint")
            }
        } catch (ce: CancellationException) { throw ce } catch (_: Exception) { null }

        override fun log(level: String, event: String, fields: Map<String, String>) {
            // checkout_started carries the cart as one JSON field (JSON-path workflow metrics).
            val f = if (event == SpecEvents.CHECKOUT_STARTED) fields + (SpecFields.CART_JSON to CartJson.from(lastCart)) else fields
            when (level) {
                "critical" -> RecordingLogger.logCritical(f) { event }
                "error" -> RecordingLogger.logError(f) { event }
                "warning" -> RecordingLogger.logWarning(f) { event }
                else -> RecordingLogger.logInfo(f) { event }
            }
        }

        // bitdrift SDK: startSpan() with parentSpanId builds the journey waterfall
        // (journey → product_discovery/cart_assembly/checkout → sub-phases); all logs are
        // correlated via _span_id. POC: spans waterfall in Timeline; _duration_ms p50/p95.
        override fun startSpan(name: String, parent: Any?, fields: Map<String, String>): Any? =
            RecordingLogger.startSpan(name, LogLevel.INFO, fields.ifEmpty { null }, parentSpanId = (parent as? Span)?.id)

        override fun endSpan(handle: Any, result: String, fields: Map<String, String>) {
            val r = when (result) {
                "failure" -> SpanResult.FAILURE
                "canceled" -> SpanResult.CANCELED
                else -> SpanResult.SUCCESS
            }
            (handle as Span).end(r, fields.ifEmpty { null })
        }

        override fun addField(key: String, value: String) = RecordingLogger.addField(key, value)

        override fun injectFault(id: String) {
            when (id) {
                "force_quit" -> performForceQuit()
                "anr" -> performGuestAnr()
            }
        }

        override fun fireCrash() {
            navController?.let { fireCrashNow(it) }
        }
    }

    private val journeyEngine = JourneyEngine(SpecJourney.JSON, journeyAdapter)

    /**
     * Simulates a force-quit (swipe-up from recents) on the ProductDetail screen. The
     * engine decided to inject it and logged force_quit_injected; this persists the
     * restart intent and stops the sim so the host watchdog can recents swipe-dismiss
     * (Android then classifies the exit as user-requested app removal rather than an
     * in-process self-termination). The Sankey shows ProductDetail → (dropout).
     */
    private fun performForceQuit() {
        val prefs = ShoppingDemoApp.appContext.getSharedPreferences(FORCE_QUIT_PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_RESTART_PENDING, true)
            .putBoolean(KEY_RESUME_INFINITE, isInfiniteMode)
            .putString(KEY_RESTART_VARIANT, activeVariant.name)
            .commit()
        // Stop scheduling new journeys and let the watchdog perform a recents dismiss.
        isCancelled = true
    }

    /**
     * Simulates an ANR on the CheckoutGuest screen — as if a synchronous post-checkout
     * validation call blocks the main thread. The engine calls this after the screen
     * rendered and the checkout API returned, so Android's input dispatcher detects the
     * blocked thread and shows the ANR dialog. The Sankey shows CheckoutGuest → (dropout).
     */
    private fun performGuestAnr() {
        val prefs = ShoppingDemoApp.appContext.getSharedPreferences(ANR_PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_RESTART_PENDING, true)
            .putBoolean(KEY_RESUME_INFINITE, isInfiniteMode)
            .putString(KEY_RESTART_VARIANT, activeVariant.name)
            .commit()
        // The external watchdog script detects the ANR dialog, force-stops, and relaunches.
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
    // OOM crash kinds (see Crashes.oomOnly) need the longer restart delay -- see
    // OOM_CRASH_RESTART_DELAY_MS's comment for why.
    private fun restartDelayFor(crashKind: String): Long =
        if (crashKind.startsWith("oom_")) OOM_CRASH_RESTART_DELAY_MS else CRASH_RESTART_DELAY_MS

    private fun pickNextCrashCombo(prefs: android.content.SharedPreferences): Triple<String, () -> Unit, Boolean> {
        // Test harness (`crash=<name>` launch argument): that crash, in the foreground, not the sweep.
        AutorunConfig.crash?.let { wanted ->
            Crashes.all.firstOrNull { it.first == wanted }?.let { return Triple(it.first, it.second, false) }
        }
        val crashes = if (prefs.getBoolean(ShoppingDemoApp.KEY_OOM_ONLY, false)) Crashes.oomOnly else Crashes.all
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
     * Fires the next crash-loop crash at the journey point the engine chose (spec OPEN-3:
     * crash_journey_point is already set): picks the next combo, logs it, pre-schedules an
     * AlarmManager restart (survives native signals), then dispatches the crash.
     */
    private fun fireCrashNow(nc: NavController) {
        android.util.Log.d("SimNav", "fireCrashNow: crashLoopEnabled=$crashLoopEnabled")
        if (!crashLoopEnabled) return
        val ctx = ShoppingDemoApp.appContext
        val prefs = ctx.getSharedPreferences(ShoppingDemoApp.PREFS, Context.MODE_PRIVATE)
        val (name, fn, fireInBackground) = pickNextCrashCombo(prefs)
        val crashContext = if (fireInBackground) "background" else "foreground"
        android.util.Log.d("SimNav", "firing crash $name ($crashContext), realistic=${Crashes.precursors.containsKey(name)}")
        val precursor = Crashes.precursors[name]
        if (precursor != null) {
            // Realistic crash: no announcement and no crash_kind fields, just the lead-up a real app would log.
            precursor()
        } else {
            RecordingLogger.addField(SpecFields.CRASH_KIND, name)
            RecordingLogger.addField(SpecFields.CRASH_CONTEXT, crashContext)
            RecordingLogger.logWarning { "about_to_crash: $name (context=$crashContext)" }
        }
        // Pre-schedule the restart BEFORE the crash — AlarmManager survives even
        // SIGSEGV/SIGBUS where the JVM uncaught-exception handler cannot run.
        ShoppingDemoApp.scheduleRestart(ctx, restartDelayFor(name))
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
        fastCrashStatus = FastCrashStatus(name, crashContext, prefs.getBoolean(ShoppingDemoApp.KEY_OOM_ONLY, false))
        RecordingLogger.startNewSession()
        RecordingLogger.addField(SpecFields.CRASH_KIND, name)
        RecordingLogger.addField(SpecFields.CRASH_CONTEXT, crashContext)
        RecordingLogger.logWarning { "about_to_crash (fast): $name (context=$crashContext)" }
        ShoppingDemoApp.scheduleRestart(ctx, restartDelayFor(name))
        dispatchCrash(fn, fireInBackground, activity)
    }

    // ─── The single journey ──────────────────────────────────────────────

    private suspend fun runSingleJourney(nc: NavController) {
        navController = nc
        val toggles = buildSet {
            if (crashLoopEnabled) add("crash_loop")
            if (anrAEnabled) add("anr")
            if (forceQuitEnabled) add("force_quit")
        }
        // journey_id is a global field for the whole journey: every log, span, network request and
        // (if it comes to that) crash report inside it carries the id.
        RecordingLogger.addField(SpecFields.JOURNEY_ID, "j" + java.util.UUID.randomUUID().toString().take(8))
        val outcome = journeyEngine.run(activeVariant.id, currentRun, simSeed, toggles, isInfiniteMode)
        android.util.Log.d("SimNav", "journey $currentRun (${activeVariant.label}, seed=$simSeed): $outcome")
    }

    companion object {
        private const val CRASH_RESTART_DELAY_MS = 2000L
        // OOM crashes materialize on their own schedule (background allocation/thread/
        // bitmap loop until the allocator gives up) instead of throwing synchronously,
        // so 2s is not long enough to guarantee the process has actually died by the
        // time the alarm fires. A too-short delay doesn't lose the crash -- the
        // background thread still eventually OOMs and kills the process whenever it
        // gets there -- but it does mean the alarm relaunches the (still-alive) app
        // early, and the still-running leaked thread from the first attempt keeps
        // accumulating alongside whatever the relaunch fires next. Confirmed live:
        // two concurrent "oom-bitmap-decode" threads in one process from exactly this.
        //
        // Also needs to stay above Crashes.OOM_GRADUAL_WAIT_MS (35s) -- those loops are
        // now deliberately paced to run for ~20-30s so the session lasts long enough
        // to collect multiple Resource Utilization snapshots (3s capture interval)
        // and show an actual rising memory graph instead of 0-1 flat points.
        private const val OOM_CRASH_RESTART_DELAY_MS = 45000L
        private const val CRASH_FLUSH_MS = 300L
        // Longer than CRASH_FLUSH_MS: gives ActivityManager time to actually demote
        // process importance away from foreground after moveTaskToBack, before the
        // crash fires. Empirical starting point — validate against reported
        // app_metrics.running_state and tune if crashes still land as foreground.
        private const val BACKGROUND_SETTLE_MS = 2000L
        const val KEY_RESTART_VARIANT = "restart_variant"

        const val ANR_PREFS_NAME = "anr_a"
        const val KEY_ANR_A_ACTIVE = "active"
        const val KEY_RESTART_PENDING = "restart_pending"
        const val KEY_RESUME_INFINITE = "resume_infinite"
        private const val ANR_BLOCK_DURATION_MS = 15000L
        private const val ANR_HARD_FREEZE_SLEEP_MS = 60000L

        const val FORCE_QUIT_PREFS_NAME = "force_quit"
        const val KEY_FORCE_QUIT_ACTIVE = "active"
    }
}
