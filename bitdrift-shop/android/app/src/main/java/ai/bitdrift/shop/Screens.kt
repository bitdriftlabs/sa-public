package ai.bitdrift.shop

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp

import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import ai.bitdrift.shop.BuildConfig
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.CaptureResult
import io.bitdrift.capture.LogLevel
import kotlinx.coroutines.launch
import org.json.JSONObject

// MARK: - Step 1: Welcome

@Composable
fun WelcomeScreen(navController: NavController, simulationManager: SimulationManager) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var latestSdkVersion by remember { mutableStateOf<String?>(null) }
    // bitdrift SDK: createTemporaryDeviceCode() generates a short-lived code for locating
    // this device's session in the dashboard.
    // POC: support debugging — pull any reported session from production without a repro case
    var deviceCode by remember { mutableStateOf<String?>(null) }
    val clipboardManager = LocalClipboardManager.current
    val localContext = androidx.compose.ui.platform.LocalContext.current
    val crashLoopPrefs = remember {
        localContext.getSharedPreferences(ShoppingDemoApp.PREFS, android.content.Context.MODE_PRIVATE)
    }
    var crashLoopOn by remember { mutableStateOf(crashLoopPrefs.getBoolean(ShoppingDemoApp.KEY_ACTIVE, false)) }

    LaunchedEffect(Unit) {
        try { apiData = ApiClient.getWelcome() } catch (_: Exception) {}
        latestSdkVersion = try { ApiClient.fetchLatestSdkVersion() } catch (_: Exception) { null }
    }

    val subtitle = apiData?.let {
        val tagline = it.optString("tagline", "")
        val promos = it.optJSONArray("promotions")
        val promoText = promos?.optJSONObject(0)?.optString("title", "") ?: ""
        "$tagline\n$promoText"
    } ?: "Experience different shopping journeys"

    ScreenContainer(
        screenName = "Welcome",
        title = apiData?.optString("store_name", "Welcome to bitdrift Shop") ?: "Welcome to bitdrift Shop",
        subtitle = subtitle,
        step = 1,
        icon = Icons.Default.ShoppingCart,
        color = Color(0xFF2196F3),
        logoResId = R.drawable.bitdrift_logo,
        latestSdkVersion = latestSdkVersion
    ) {
        PrimaryButton(
            title = "Browse Products",
            icon = Icons.Default.Menu,
            enabled = !simulationManager.isSimulating
        ) {
            navController.navigate(Screen.Browse.route)
        }

        SecondaryButton(
            title = "Search for Items",
            icon = Icons.Default.Search,
            enabled = !simulationManager.isSimulating
        ) {
            navController.navigate(Screen.Search.route)
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

        if (simulationManager.isSimulating) {
            Text(
                text = "Simulation in progress...",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(16.dp)
            )
        } else {
            if (crashLoopOn) {
                val oomOnlyOn = crashLoopPrefs.getBoolean(ShoppingDemoApp.KEY_OOM_ONLY, false)
                val crashes = if (oomOnlyOn) Crashes.oomOnly else Crashes.all
                val comboIdx = crashLoopPrefs.getInt(ShoppingDemoApp.KEY_NEXT_COMBO_INDEX, 0) % (crashes.size * 2)
                val nextCrashName = crashes[comboIdx / 2].first
                val nextContext = if (comboIdx % 2 == 1) "background" else "foreground"
                val fastModeOn = crashLoopPrefs.getBoolean(ShoppingDemoApp.KEY_FAST_MODE, false)
                AssistChip(
                    onClick = {},
                    enabled = false,
                    label = {
                        Text(
                            text = "${if (oomOnlyOn) "OOM loop" else "Crash loop"} ACTIVE${if (fastModeOn) " (fast)" else ""} — next: $nextCrashName/$nextContext",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        crashLoopPrefs.edit()
                            .putBoolean(ShoppingDemoApp.KEY_ACTIVE, false)
                            .putBoolean(ShoppingDemoApp.KEY_FAST_MODE, false)
                            .putBoolean(ShoppingDemoApp.KEY_OOM_ONLY, false)
                            .apply()
                        crashLoopOn = false
                        simulationManager.crashLoopEnabled = false
                        simulationManager.fastCrashModeEnabled = false
                        simulationManager.setVariant(simulationManager.activeVariant)
                        Logger.logInfo { "crash_loop_stopped" }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) { Text("Stop crash loop") }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SimButton(title = "Sim 10", color = Color(0xFFFF9800), modifier = Modifier.weight(1f)) {
                    simulationManager.simulate(10, navController)
                }
                SimButton(title = "SIM ∞", color = Color(0xFF9C27B0), modifier = Modifier.weight(1f)) {
                    simulationManager.infiniteSimulate(navController)
                }
            }

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
                modifier = Modifier.fillMaxWidth().height(48.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (deviceCode != null) Color(0xFF2196F3) else MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = if (deviceCode != null) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                )
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

            SecondaryButton(
                title = "Advanced",
                icon = Icons.Default.Settings
            ) {
                navController.navigate(Screen.Advanced.route)
            }
        }

    }
}

private val SIM_VARIANTS = listOf(SimVariant.CONTROL, SimVariant.VARIANT_A, SimVariant.VARIANT_B)

// MARK: - Advanced Controls

@Composable
fun AdvancedScreen(navController: NavController, simulationManager: SimulationManager) {
    val localContext = androidx.compose.ui.platform.LocalContext.current
    val anrAPrefs = remember {
        localContext.getSharedPreferences(SimulationManager.ANR_PREFS_NAME, android.content.Context.MODE_PRIVATE)
    }
    val crashLoopPrefs = remember {
        localContext.getSharedPreferences(ShoppingDemoApp.PREFS, android.content.Context.MODE_PRIVATE)
    }
    val forceQuitPrefs = remember {
        localContext.getSharedPreferences(SimulationManager.FORCE_QUIT_PREFS_NAME, android.content.Context.MODE_PRIVATE)
    }
    var anrAOn by remember { mutableStateOf(anrAPrefs.getBoolean(SimulationManager.KEY_ANR_A_ACTIVE, false)) }
    var crashLoopOn by remember { mutableStateOf(crashLoopPrefs.getBoolean(ShoppingDemoApp.KEY_ACTIVE, false)) }
    var oomOnlyOn by remember { mutableStateOf(crashLoopPrefs.getBoolean(ShoppingDemoApp.KEY_OOM_ONLY, false)) }
    var forceQuitOn by remember { mutableStateOf(forceQuitPrefs.getBoolean(SimulationManager.KEY_FORCE_QUIT_ACTIVE, false)) }
    var showAnrReminder by remember { mutableStateOf(false) }
    var showQuitReminder by remember { mutableStateOf(false) }
    val isVariantASelected = simulationManager.activeVariant == SimVariant.VARIANT_A
    var supportLogEnabled by remember { mutableStateOf(false) }

    LaunchedEffect(isVariantASelected, anrAOn) {
        val restartPending = anrAPrefs.getBoolean(SimulationManager.KEY_RESTART_PENDING, false)
        if (!restartPending && !isVariantASelected && anrAOn) {
            anrAPrefs.edit().putBoolean(SimulationManager.KEY_ANR_A_ACTIVE, false).apply()
            anrAOn = false
            simulationManager.anrAEnabled = false
            simulationManager.setVariant(simulationManager.activeVariant)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { navController.popBackStack() }) {
                Icon(imageVector = Icons.Default.ArrowBack, contentDescription = "Back")
            }
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "Advanced",
                style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold)
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Simulation Variant",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )

            // bitdrift SDK: setVariant() calls setFeatureFlagExposure() so every log in the
            // run is tagged with the active cohort for dashboard slicing.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SIM_VARIANTS.forEach { variant ->
                    val selected = simulationManager.activeVariant == variant
                    val variantColor = when (variant) {
                        SimVariant.CONTROL   -> Color(0xFF607D8B)
                        SimVariant.VARIANT_A -> Color(0xFF00BCD4)
                        SimVariant.VARIANT_B -> Color(0xFFFF9800)
                    }
                    Button(
                        onClick = { simulationManager.setVariant(variant) },
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (selected) variantColor else MaterialTheme.colorScheme.surfaceVariant,
                            contentColor = if (selected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                        ),
                        modifier = Modifier.weight(1f).height(40.dp),
                        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                    ) {
                        Text(
                            text = variant.label,
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                            maxLines = 1
                        )
                    }
                }
            }

            if (BuildConfig.SHOW_SIM_AB) {
                SimButton(title = "SIM\nA/B", color = Color(0xFF009688)) {
                    simulationManager.abSimulate(5, navController)
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (BuildConfig.SHOW_CARDINALITY) {
                    SimButton(title = "Cardinality", color = Color(0xFFE53935), modifier = Modifier.weight(1f)) {
                        simulationManager.cardinalitySimulate(navController)
                    }
                }
                Button(
                    onClick = {
                        simulationManager.recommendationsV2Enabled = !simulationManager.recommendationsV2Enabled
                        simulationManager.setVariant(simulationManager.activeVariant)
                    },
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (simulationManager.recommendationsV2Enabled) Color(0xFF3F51B5) else Color(0xFF795548)
                    ),
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                ) {
                    Text(
                        text = if (simulationManager.recommendationsV2Enabled) "Rec v2: ON" else "Rec v2",
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        textAlign = TextAlign.Center
                    )
                }
                Button(
                    onClick = {
                        // "Crash" always means the full catalog — turning it on clears
                        // OOM-only mode, in case that was left on from the OOMs button.
                        val newState = !(crashLoopOn && !oomOnlyOn)
                        crashLoopPrefs.edit()
                            .putBoolean(ShoppingDemoApp.KEY_ACTIVE, newState)
                            .putBoolean(ShoppingDemoApp.KEY_OOM_ONLY, false)
                            .apply()
                        crashLoopOn = newState
                        oomOnlyOn = false
                        simulationManager.crashLoopEnabled = newState
                        simulationManager.setVariant(simulationManager.activeVariant)
                    },
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (crashLoopOn && !oomOnlyOn) Color(0xFFD32F2F) else Color(0xFF795548)
                    ),
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                ) {
                    Text(
                        text = if (crashLoopOn && !oomOnlyOn) "Crash: ON" else "Crash",
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        textAlign = TextAlign.Center
                    )
                }
                Button(
                    onClick = {
                        // "OOMs" is the same crash loop, restricted to Crashes.oomOnly —
                        // turning it on enables the loop with the OOM-only flag set.
                        val newState = !(crashLoopOn && oomOnlyOn)
                        crashLoopPrefs.edit()
                            .putBoolean(ShoppingDemoApp.KEY_ACTIVE, newState)
                            .putBoolean(ShoppingDemoApp.KEY_OOM_ONLY, newState)
                            .apply()
                        crashLoopOn = newState
                        oomOnlyOn = newState
                        simulationManager.crashLoopEnabled = newState
                        simulationManager.setVariant(simulationManager.activeVariant)
                    },
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (crashLoopOn && oomOnlyOn) Color(0xFFD32F2F) else Color(0xFF795548)
                    ),
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                ) {
                    Text(
                        text = if (crashLoopOn && oomOnlyOn) "OOMs: ON" else "OOMs",
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        textAlign = TextAlign.Center
                    )
                }
                Button(
                    onClick = {
                        val newState = !anrAOn
                        if (newState) { showAnrReminder = true }
                        anrAPrefs.edit().putBoolean(SimulationManager.KEY_ANR_A_ACTIVE, newState).apply()
                        anrAOn = newState
                        simulationManager.anrAEnabled = newState
                        simulationManager.setVariant(simulationManager.activeVariant)
                    },
                    enabled = isVariantASelected,
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (anrAOn) Color(0xFFF44336) else Color(0xFF795548)
                    ),
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                ) {
                    Text(
                        text = "ANR-A",
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        textAlign = TextAlign.Center
                    )
                }
                Button(
                    onClick = {
                        val newState = !forceQuitOn
                        if (newState) { showQuitReminder = true }
                        forceQuitPrefs.edit().putBoolean(SimulationManager.KEY_FORCE_QUIT_ACTIVE, newState).apply()
                        forceQuitOn = newState
                        simulationManager.forceQuitEnabled = newState
                        simulationManager.setVariant(simulationManager.activeVariant)
                    },
                    modifier = Modifier.weight(1f).height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (forceQuitOn) Color(0xFFFF6F00) else Color(0xFF795548)
                    ),
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                ) {
                    Text(
                        text = if (forceQuitOn) "Quit: ON" else "Quit",
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1,
                        textAlign = TextAlign.Center
                    )
                }
            }

            AssistChip(
                onClick = {},
                enabled = false,
                label = {
                    val nextCrashText = if (crashLoopOn) {
                        val crashes = if (oomOnlyOn) Crashes.oomOnly else Crashes.all
                        val comboIdx = crashLoopPrefs.getInt(ShoppingDemoApp.KEY_NEXT_COMBO_INDEX, 0) % (crashes.size * 2)
                        val fastTag = if (crashLoopPrefs.getBoolean(ShoppingDemoApp.KEY_FAST_MODE, false)) "fast, " else ""
                        val ctx = if (comboIdx % 2 == 1) "background" else "foreground"
                        " ($fastTag next: ${crashes[comboIdx / 2].first}/$ctx)"
                    } else ""
                    Text(
                        text = "Crash: ${if (crashLoopOn) "${if (oomOnlyOn) "OOMs only, " else ""}enabled$nextCrashText" else "disabled"} | ANR-A: " +
                            when {
                                !isVariantASelected -> "unavailable (select Variant A)"
                                anrAOn -> "enabled"
                                else -> "disabled"
                            } +
                            " | Quit: ${if (forceQuitOn) "enabled" else "disabled"}"
                    )
                },
                modifier = Modifier.padding(top = 6.dp)
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            Text(
                text = "Debug Tools",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )

            // bitdrift SDK: addField("supportlog") tags all telemetry for filtering during
            // support investigations.
            // POC: ad-hoc debugging — filter Timeline to a specific device in production
            Button(
                onClick = {
                    supportLogEnabled = !supportLogEnabled
                    Logger.addField("supportlog", supportLogEnabled.toString())
                },
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier.fillMaxWidth().height(48.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (supportLogEnabled) Color(0xFF4CAF50) else MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = if (supportLogEnabled) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) {
                Text(
                    text = if (supportLogEnabled) "Support Log: ON" else "Support Log: OFF",
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold)
                )
            }
        }
    }

    if (showAnrReminder) {
        AlertDialog(
            onDismissRequest = { showAnrReminder = false },
            title = { Text("ANR Watchdog Required") },
            text = {
                Text(
                    "Run the host-side watchdog script to auto-dismiss ANR dialogs and relaunch:\n\n" +
                    "scripts/watchdog.sh"
                )
            },
            confirmButton = {
                TextButton(onClick = { showAnrReminder = false }) { Text("Got it") }
            }
        )
    }

    if (showQuitReminder) {
        AlertDialog(
            onDismissRequest = { showQuitReminder = false },
            title = { Text("Watchdog Script Required") },
            text = {
                Text(
                    "Force-quit kills the process instantly. Run the watchdog script to detect the dead process and relaunch:\n\n" +
                    "scripts/watchdog.sh"
                )
            },
            confirmButton = {
                TextButton(onClick = { showQuitReminder = false }) { Text("Got it") }
            }
        )
    }
}

// MARK: - Step 2: Browse / Search

@Composable
fun BrowseScreen(navController: NavController, simulationManager: SimulationManager? = null) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var firstProductId by remember { mutableStateOf("") }
    var products by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var catalogJson by remember { mutableStateOf("[]") }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.getBrowse()
            catalogJson = ApiClient.getFullCatalogJson()
            val arr = apiData?.optJSONArray("products")
            if (arr != null && arr.length() > 0) {
                firstProductId = arr.getJSONObject(0).optString("id", "")
                products = (0 until arr.length()).map { arr.getJSONObject(it) }
            }
        } catch (_: Exception) {}
    }

    val recommendations = if (simulationManager?.recommendationsV2Enabled == true && products.isNotEmpty()) {
        val pid = products.first().optString("id", "")
        // bitdrift SDK: trackSpan() wraps the scoring work and records its duration in the session
        // timeline; ends SUCCESS on return, FAILURE on throw.
        // POC: event tracking — unsampled duration histogram (p50/p95) for any operation
        Logger.trackSpan("score_products", LogLevel.INFO, mapOf("product_id" to pid, "screen_name" to "Browse")) {
            RecommendationEngine.scoreProducts(catalogJson, pid)
        }
    } else emptyList()

    val subtitle = apiData?.let {
        val total = it.optInt("total_products", 0)
        val count = products.size
        "Showing $count of $total products"
    } ?: "Explore our product catalog"

    ScreenContainer(
        screenName = "Browse",
        title = "Browse",
        subtitle = subtitle,
        step = 2,
        icon = Icons.Default.Menu,
        color = Color(0xFF9C27B0),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        if (recommendations.isNotEmpty()) {
            RecommendedSection(recommendations) { productId ->
                navController.navigate(Screen.ProductDetail("browse", productId).route)
            }
        }
        ProductImageRow(products) { productId ->
            navController.navigate(Screen.ProductDetail("browse", productId).route)
        }
        PrimaryButton(
            title = "View Featured",
            icon = Icons.Default.Star
        ) {
            navController.navigate(Screen.FeaturedProducts.route)
        }
        SecondaryButton(
            title = "Shop by Category",
            icon = Icons.Default.List
        ) {
            navController.navigate(Screen.Categories.route)
        }
    }
}

@Composable
fun SearchScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var products by remember { mutableStateOf<List<JSONObject>>(emptyList()) }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.search("headphones")
            val arr = apiData?.optJSONArray("products")
            if (arr != null) {
                products = (0 until arr.length()).map { arr.getJSONObject(it) }
            }
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val count = it.optInt("result_count", 0)
        "Found $count results for \"${it.optString("query", "")}\""
    } ?: "Find exactly what you're looking for"

    ScreenContainer(
        screenName = "Search",
        title = "Search",
        subtitle = subtitle,
        step = 2,
        icon = Icons.Default.Search,
        color = Color(0xFFFF9800),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(Screen.ProductDetail("search", productId).route)
        }
        PrimaryButton(
            title = "View Featured",
            icon = Icons.Default.Star
        ) {
            navController.navigate(Screen.FeaturedProducts.route)
        }
        SecondaryButton(
            title = "Shop by Category",
            icon = Icons.Default.List
        ) {
            navController.navigate(Screen.Categories.route)
        }
    }
}

// MARK: - Step 3: Featured Products / Categories

@Composable
fun FeaturedProductsScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var firstProductId by remember { mutableStateOf("prod_a1b2c3") }
    var products by remember { mutableStateOf<List<JSONObject>>(emptyList()) }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.getFeatured()
            val arr = apiData?.optJSONArray("featured_products")
            if (arr != null && arr.length() > 0) {
                firstProductId = arr.getJSONObject(0).optString("id", firstProductId)
                products = (0 until arr.length()).map { arr.getJSONObject(it) }
            }
        } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val banner = it.optJSONObject("banner")?.optString("text", "") ?: ""
        val products = it.optJSONArray("featured_products")
        val count = products?.length() ?: 0
        "$banner — $count picks"
    } ?: "Our top picks for you"

    ScreenContainer(
        screenName = "Featured",
        title = "Featured Products",
        subtitle = subtitle,
        step = 3,
        icon = Icons.Default.Star,
        color = Color(0xFFFFEB3B),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(Screen.ProductDetail("featured", productId).route)
        }
        PrimaryButton(
            title = "View Product Details",
            icon = Icons.Default.Info
        ) {
            navController.navigate(Screen.ProductDetail("featured", firstProductId).route)
        }
        SecondaryButton(
            title = "Read Reviews First",
            icon = Icons.Default.Email
        ) {
            navController.navigate(Screen.Reviews("featured", firstProductId).route)
        }
    }
}

@Composable
fun CategoriesScreen(navController: NavController) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var categories by remember { mutableStateOf<List<JSONObject>>(emptyList()) }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.getCategories()
            val arr = apiData?.optJSONArray("categories")
            if (arr != null) {
                categories = (0 until arr.length()).map { arr.getJSONObject(it) }
            }
        } catch (_: Exception) {}
    }

    val subtitle = if (categories.isNotEmpty()) {
        categories.joinToString(", ") { it.optString("name") }
    } else "Browse by product type"

    ScreenContainer(
        screenName = "Categories",
        title = "Categories",
        subtitle = subtitle,
        step = 3,
        icon = Icons.Default.List,
        color = Color(0xFF4CAF50),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        CategoryRow(categories) { categoryName ->
            navController.navigate(Screen.CategoryBrowse(categoryName).route)
        }
        PrimaryButton(
            title = "View Product Details",
            icon = Icons.Default.Info
        ) {
            navController.navigate(Screen.ProductDetail("categories", "prod_a1b2c3").route)
        }
        SecondaryButton(
            title = "Read Reviews First",
            icon = Icons.Default.Email
        ) {
            navController.navigate(Screen.Reviews("categories", "prod_a1b2c3").route)
        }
    }
}

// MARK: - Step 3b: Category Browse

@Composable
fun CategoryBrowseScreen(navController: NavController, category: String?) {
    val cat = category ?: "Electronics"
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var products by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var firstProductId by remember { mutableStateOf("prod_a1b2c3") }

    LaunchedEffect(cat) {
        try {
            apiData = ApiClient.getCategoryProducts(cat)
            val arr = apiData?.optJSONArray("products")
            if (arr != null && arr.length() > 0) {
                products = (0 until arr.length()).map { arr.getJSONObject(it) }
                firstProductId = products[0].optString("id", firstProductId)
            }
        } catch (_: Exception) {}
    }

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
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        ProductImageRow(products) { productId ->
            navController.navigate(Screen.ProductDetail("categories", productId).route)
        }
        PrimaryButton(
            title = "View Product Details",
            icon = Icons.Default.Info
        ) {
            navController.navigate(Screen.ProductDetail("categories", firstProductId).route)
        }
        SecondaryButton(
            title = "Read Reviews First",
            icon = Icons.Default.Email
        ) {
            navController.navigate(Screen.Reviews("categories", firstProductId).route)
        }
    }
}

// MARK: - Step 4: Product Detail / Reviews

@Composable
fun ProductDetailScreen(navController: NavController, source: String?, productId: String?, simulationManager: SimulationManager? = null) {
    val pid = productId ?: "prod_a1b2c3"
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var catalogJson by remember { mutableStateOf("[]") }

    LaunchedEffect(pid) {
        try {
            apiData = ApiClient.getProduct(pid)
            if (simulationManager?.recommendationsV2Enabled == true) {
                catalogJson = ApiClient.getFullCatalogJson()
            }
        } catch (_: Exception) {}
    }

    val recommendations = if (simulationManager?.recommendationsV2Enabled == true) {
        // bitdrift SDK: trackSpan() wraps the scoring work and records its duration in the session
        // timeline; ends SUCCESS on return, FAILURE on throw.
        // POC: event tracking — unsampled duration histogram (p50/p95) for any operation
        Logger.trackSpan("score_products", LogLevel.INFO, mapOf("product_id" to pid, "screen_name" to "ProductDetail")) {
            RecommendationEngine.scoreProducts(catalogJson, pid)
        }
    } else emptyList()

    val title = apiData?.optString("name", "Product Details") ?: "Product Details"
    val imageUrl = apiData?.optJSONArray("images")?.optString(0)
    val subtitle = apiData?.let {
        val brand = it.optString("brand", "")
        val price = it.optDouble("price", 0.0)
        val stock = it.optInt("stock_count", 0)
        "$brand — \$${String.format("%.2f", price)} — $stock in stock"
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
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        if (recommendations.isNotEmpty()) {
            RecommendedSection(recommendations) { recProductId ->
                navController.navigate(Screen.ProductDetail("browse", recProductId).route)
            }
        }
        PrimaryButton(
            title = "Add to Cart",
            icon = Icons.Default.Add
        ) {
            // bitdrift SDK: logInfo() with a stable event name and field map enables aggregation in the dashboard.
            Logger.logInfo(mapOf("product_id" to pid, "source_screen" to (source ?: "unknown"))) { "add_to_cart" }
            navController.navigate(Screen.Cart(pid).route)
        }
        SecondaryButton(
            title = "Save to Wishlist",
            icon = Icons.Default.Favorite
        ) {
            // bitdrift SDK: logInfo() records wishlist events with product and source context.
            Logger.logInfo(mapOf("product_id" to pid, "source_screen" to (source ?: "unknown"))) { "add_to_wishlist" }
            navController.navigate(Screen.Wishlist(pid).route)
        }
    }
}

@Composable
fun ReviewsScreen(navController: NavController, source: String?, productId: String?) {
    val pid = productId ?: "prod_a1b2c3"
    var apiData by remember { mutableStateOf<JSONObject?>(null) }

    LaunchedEffect(pid) {
        try { apiData = ApiClient.getReviews(pid) } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val avg = it.optDouble("average_rating", 0.0)
        val total = it.optInt("total_reviews", 0)
        val topReview = it.optJSONArray("reviews")?.optJSONObject(0)
        val topTitle = topReview?.optString("title", "") ?: ""
        "$avg stars from $total reviews\n\"$topTitle\""
    } ?: "Loading reviews..."

    ScreenContainer(
        screenName = "Reviews",
        title = "Customer Reviews",
        subtitle = subtitle,
        step = 4,
        icon = Icons.Default.Email,
        color = Color(0xFF00E5BD),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Add to Cart",
            icon = Icons.Default.Add
        ) {
            // bitdrift SDK: logInfo() records cart-add events from the reviews screen.
            Logger.logInfo(mapOf("product_id" to pid, "source_screen" to (source ?: "unknown"))) { "add_to_cart" }
            navController.navigate(Screen.Cart(pid).route)
        }
        SecondaryButton(
            title = "Save to Wishlist",
            icon = Icons.Default.Favorite
        ) {
            // bitdrift SDK: logInfo() records wishlist events with product and source context.
            Logger.logInfo(mapOf("product_id" to pid, "source_screen" to (source ?: "unknown"))) { "add_to_wishlist" }
            navController.navigate(Screen.Wishlist(pid).route)
        }
    }
}

// MARK: - Step 5: Cart / Wishlist

@Composable
fun CartScreen(navController: NavController, productId: String?) {
    val pid = productId ?: ""
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(pid) {
        try {
            apiData = if (pid.isNotEmpty()) ApiClient.addToCart(pid) else ApiClient.getCart()
        } catch (e: Exception) {
            // bitdrift SDK: logError() with throwable captures the exception in the session timeline.
            Logger.logError(mapOf("product_id" to pid), throwable = e) { "cart_failed" }
        }
    }

    val subtitle = apiData?.let {
        val items = it.optJSONArray("items")
        val count = items?.length() ?: 0
        val total = it.optDouble("total", 0.0)
        val tax = it.optDouble("tax", 0.0)
        if (count == 0) "Your cart is empty"
        else "$count item${if (count > 1) "s" else ""} — Total: \$${String.format("%.2f", total)} (incl. \$${String.format("%.2f", tax)} tax)"
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
        // Show cart items
        val items = apiData?.optJSONArray("items")
        if (items != null && items.length() > 0) {
            Column(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 200.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i) ?: continue
                    val name = item.optString("name", "")
                    val qty = item.optInt("quantity", 1)
                    val lineTotal = item.optDouble("line_total", 0.0)
                    val itemProductId = item.optString("product_id", "")
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
                                    text = name,
                                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                                    maxLines = 1
                                )
                                Text(
                                    text = "Qty: $qty",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                )
                            }
                            Text(
                                text = "\$${String.format("%.2f", lineTotal)}",
                                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                            )
                            IconButton(onClick = {
                                // bitdrift SDK: logInfo() records cart mutations for funnel analysis.
                                Logger.logInfo(mapOf("product_id" to itemProductId)) { "cart_item_removed" }
                                scope.launch {
                                    try { apiData = ApiClient.deleteCartItem(itemProductId) } catch (_: Exception) {}
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
        PrimaryButton(
            title = "Checkout as Guest",
            icon = Icons.Default.Person
        ) {
            // bitdrift SDK: logInfo() records checkout funnel entry for conversion tracking.
            Logger.logInfo(mapOf("checkout_type" to "guest")) { "checkout_started" }
            navController.navigate(Screen.CheckoutGuest(pid).route)
        }
        SecondaryButton(
            title = "Sign In to Checkout",
            icon = Icons.Default.Lock
        ) {
            // bitdrift SDK: logInfo() records checkout funnel entry for conversion tracking.
            Logger.logInfo(mapOf("checkout_type" to "signin")) { "checkout_started" }
            navController.navigate(Screen.CheckoutSignIn(pid).route)
        }
        SecondaryButton(
            title = "Keep Shopping",
            icon = Icons.Default.ShoppingCart
        ) {
            navController.navigate(Screen.Welcome.route) {
                popUpTo(Screen.Welcome.route) { inclusive = true }
            }
        }
    }
}

@Composable
fun WishlistScreen(navController: NavController, productId: String?) {
    val pid = productId ?: "prod_a1b2c3"
    var apiData by remember { mutableStateOf<JSONObject?>(null) }

    LaunchedEffect(pid) {
        try { apiData = ApiClient.addToWishlist(pid) } catch (_: Exception) {}
    }

    val subtitle = apiData?.let {
        val count = it.optInt("item_count", 0)
        val items = it.optJSONArray("items")
        val firstName = items?.optJSONObject(0)?.optString("name", "") ?: ""
        "$count items saved — $firstName"
    } ?: "Loading wishlist..."

    ScreenContainer(
        screenName = "Wishlist",
        title = "Wishlist",
        subtitle = subtitle,
        step = 5,
        icon = Icons.Default.Favorite,
        color = Color(0xFFE91E63),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Checkout as Guest",
            icon = Icons.Default.Person
        ) {
            navController.navigate(Screen.CheckoutGuest(pid).route)
        }
        SecondaryButton(
            title = "Sign In to Checkout",
            icon = Icons.Default.Lock
        ) {
            navController.navigate(Screen.CheckoutSignIn(pid).route)
        }
    }
}

// MARK: - Step 6: Checkout Options

@Composable
fun CheckoutGuestScreen(navController: NavController, productId: String?) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var checkoutSession by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.checkoutGuest()
            checkoutSession = apiData?.optString("checkout_session", "") ?: ""
        } catch (e: Exception) {
            // bitdrift SDK: logError() with throwable records checkout failures in the session timeline.
            Logger.logError(mapOf("checkout_type" to "guest"), throwable = e) { "checkout_failed" }
        }
    }

    val subtitle = apiData?.let {
        val email = it.optString("email", "")
        val addr = it.optJSONObject("shipping_address")
        val city = addr?.optString("city", "") ?: ""
        val preview = it.optJSONObject("order_preview")
        val total = preview?.optDouble("total", 0.0) ?: 0.0
        "Shipping to $city — \$${String.format("%.2f", total)}\n$email"
    } ?: "Loading checkout..."

    ScreenContainer(
        screenName = "CheckoutGuest",
        title = "Guest Checkout",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Person,
        color = Color(0xFF3F51B5),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Pay with Card",
            icon = Icons.Default.Done
        ) {
            navController.navigate(Screen.PaymentCard(checkoutSession).route)
        }
        SecondaryButton(
            title = "Apple Pay",
            icon = Icons.Default.Phone
        ) {
            navController.navigate(Screen.PaymentApplePay(checkoutSession).route)
        }
    }
}

@Composable
fun CheckoutSignInScreen(navController: NavController, productId: String?) {
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var checkoutSession by remember { mutableStateOf("") }
    val context = androidx.compose.ui.platform.LocalContext.current

    LaunchedEffect(Unit) {
        try {
            apiData = ApiClient.checkoutSignIn()
            checkoutSession = apiData?.optString("checkout_session", "") ?: ""
            // bitdrift SDK: addField() sets user_id on the session so every subsequent log is tagged
            // with this user. Persisted to SharedPreferences so UserIdFieldProvider survives startNewSession().
            // POC: per-user debugging — user_id appears in the Timeline session header for instant identification
            val userId = apiData?.optJSONObject("user")?.optString("id", "") ?: ""
            if (userId.isNotEmpty()) {
                context.getSharedPreferences("user_session", android.content.Context.MODE_PRIVATE)
                    .edit().putString("user_id", userId).apply()
                Logger.addField("user_id", userId)
            }
        } catch (e: Exception) {
            // bitdrift SDK: logError() with throwable records checkout failures in the session timeline.
            Logger.logError(mapOf("checkout_type" to "signin"), throwable = e) { "checkout_failed" }
        }
    }

    val subtitle = apiData?.let {
        val user = it.optJSONObject("user")
        val name = user?.optString("name", "") ?: ""
        val email = user?.optString("email", "") ?: ""
        val points = user?.optInt("loyalty_points", 0) ?: 0
        val preview = it.optJSONObject("order_preview")
        val total = preview?.optDouble("total", 0.0) ?: 0.0
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
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Pay with Card",
            icon = Icons.Default.Done
        ) {
            navController.navigate(Screen.PaymentCard(checkoutSession).route)
        }
        SecondaryButton(
            title = "PayPal",
            icon = Icons.Default.Send
        ) {
            navController.navigate(Screen.PaymentPayPal(checkoutSession).route)
        }
    }
}

// MARK: - Step 6b: Payment Methods (all lead to confirmation)

@Composable
fun PaymentCardScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payCard(session)
            orderId = apiData?.optString("order_id", "") ?: ""
        } catch (e: Exception) {
            // bitdrift SDK: logError() with throwable records payment failures in the session timeline.
            Logger.logError(mapOf("payment_method" to "card"), throwable = e) { "payment_failed" }
        }
    }

    val subtitle = apiData?.let {
        val txn = it.optString("transaction_id", "")
        val method = it.optString("payment_method", "")
        val amount = it.optDouble("amount_charged", 0.0)
        "$method\n\$${String.format("%.2f", amount)} — ${txn.take(20)}…"
    } ?: "Processing payment..."

    ScreenContainer(
        screenName = "PaymentCard",
        title = "Card Payment",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Done,
        color = Color(0xFF2196F3),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Visa ending 4242",
            icon = Icons.Default.Done
        ) {
            // bitdrift SDK: logInfo() records payment completion with method and order ID for conversion tracking.
            Logger.logInfo(mapOf("payment_method" to "visa", "card_last4" to "4242", "order_id" to orderId)) { "payment_completed" }
            navController.navigate(Screen.Confirmation(orderId).route)
        }
        SecondaryButton(
            title = "Mastercard ending 8888",
            icon = Icons.Default.Done
        ) {
            // bitdrift SDK: logInfo() records payment completion.
            Logger.logInfo(mapOf("payment_method" to "mastercard", "card_last4" to "8888", "order_id" to orderId)) { "payment_completed" }
            navController.navigate(Screen.Confirmation(orderId).route)
        }
        SecondaryButton(
            title = "Amex ending 1001",
            icon = Icons.Default.Done
        ) {
            // bitdrift SDK: logInfo() records payment completion.
            Logger.logInfo(mapOf("payment_method" to "amex", "card_last4" to "1001", "order_id" to orderId)) { "payment_completed" }
            navController.navigate(Screen.Confirmation(orderId).route)
        }
    }
}

@Composable
fun PaymentApplePayScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payApplePay(session)
            orderId = apiData?.optString("order_id", "") ?: ""
        } catch (e: Exception) {
            // bitdrift SDK: logError() with throwable records payment failures.
            Logger.logError(mapOf("payment_method" to "apple_pay"), throwable = e) { "payment_failed" }
        }
    }

    val subtitle = apiData?.let {
        val txn = it.optString("transaction_id", "")
        val amount = it.optDouble("amount_charged", 0.0)
        "Apple Pay — \$${String.format("%.2f", amount)}\n${txn.take(20)}…"
    } ?: "Authenticating..."

    ScreenContainer(
        screenName = "PaymentApplePay",
        title = "Apple Pay",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Phone,
        color = Color.Black,
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Complete Purchase",
            icon = Icons.Default.CheckCircle
        ) {
            navController.navigate(Screen.Confirmation(orderId).route)
        }
    }
}

@Composable
fun PaymentPayPalScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payPayPal(session)
            orderId = apiData?.optString("order_id", "") ?: ""
        } catch (e: Exception) {
            // bitdrift SDK: logError() with throwable records payment failures.
            Logger.logError(mapOf("payment_method" to "paypal"), throwable = e) { "payment_failed" }
        }
    }

    val subtitle = apiData?.let {
        val txn = it.optString("transaction_id", "")
        val ref = it.optString("paypal_reference", "")
        val amount = it.optDouble("amount_charged", 0.0)
        "PayPal — \$${String.format("%.2f", amount)}\nRef: $ref"
    } ?: "Connecting to PayPal..."

    ScreenContainer(
        screenName = "PaymentPayPal",
        title = "PayPal",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Send,
        color = Color(0xFF2196F3),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Complete Purchase",
            icon = Icons.Default.CheckCircle
        ) {
            navController.navigate(Screen.Confirmation(orderId).route)
        }
    }
}

@Composable
fun PaymentAndroidPayScreen(navController: NavController, checkoutSession: String?) {
    val session = checkoutSession ?: ""
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    var orderId by remember { mutableStateOf("") }

    LaunchedEffect(session) {
        try {
            apiData = ApiClient.payAndroidPay(session)
            orderId = apiData?.optString("order_id", "") ?: ""
        } catch (e: Exception) {
            Logger.logError(mapOf("payment_method" to "android_pay"), throwable = e) { "payment_failed" }
        }
    }

    val subtitle = apiData?.let {
        val txn = it.optString("transaction_id", "")
        val amount = it.optDouble("amount_charged", 0.0)
        "Android Pay — \$${String.format("%.2f", amount)}\n${txn.take(20)}…"
    } ?: "Authenticating..."

    ScreenContainer(
        screenName = "PaymentAndroidPay",
        title = "Android Pay",
        subtitle = subtitle,
        step = 6,
        icon = Icons.Default.Phone,
        color = Color(0xFF4CAF50),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Complete Purchase",
            icon = Icons.Default.CheckCircle
        ) {
            navController.navigate(Screen.Confirmation(orderId).route)
        }
    }
}

// MARK: - Payment Failed

@Composable
fun PaymentFailedScreen(navController: NavController, paymentMethod: String?, checkoutSession: String?) {
    val method = paymentMethod ?: "unknown"
    val session = checkoutSession ?: ""

    val methodLabel = when (method) {
        "card" -> "Credit Card"
        "apple_pay" -> "Apple Pay"
        "paypal" -> "PayPal"
        "android_pay" -> "Android Pay"
        else -> method.replaceFirstChar { it.uppercase() }
    }

    ScreenContainer(
        screenName = "PaymentFailed",
        title = "Payment Failed",
        subtitle = "Your $methodLabel payment could not be processed.\nPlease try again or use a different payment method.",
        step = 6,
        icon = Icons.Default.Warning,
        color = Color(0xFFE53935),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        PrimaryButton(
            title = "Try Again",
            icon = Icons.Default.Refresh
        ) {
            navController.popBackStack()
        }
    }
}

// MARK: - Step 7: Confirmation (Final - All Paths Converge)

@Composable
fun ConfirmationScreen(navController: NavController, orderId: String?) {
    val oid = orderId ?: ""
    var apiData by remember { mutableStateOf<JSONObject?>(null) }
    val context = androidx.compose.ui.platform.LocalContext.current

    LaunchedEffect(oid) {
        try { apiData = ApiClient.getConfirmation(oid) } catch (_: Exception) {}
    }

    val crashLoopActive = remember {
        context.getSharedPreferences(ShoppingDemoApp.PREFS, android.content.Context.MODE_PRIVATE)
            .getBoolean(ShoppingDemoApp.KEY_ACTIVE, false)
    }

    val subtitle = if (crashLoopActive) {
        OrderSummaryHelper.reset()
        OrderSummaryHelper.formatOrderSummary(apiData, oid)
    } else {
        apiData?.let {
            val txn = it.optString("transaction_id", "")
            val total = it.optDouble("total", 0.0)
            val shipping = it.optJSONObject("shipping")
            val delivery = shipping?.optString("estimated_delivery", "") ?: ""
            val tracking = shipping?.optString("tracking_number", "") ?: ""
            "Order ${it.optString("order_id", oid)}\nTotal: \$${String.format("%.2f", total)}\nDelivery: $delivery\nTracking: $tracking\nTxn: ${txn.take(24)}…"
        } ?: "Order $oid\nThank you for your purchase!"
    }

    ScreenContainer(
        screenName = "Confirmation",
        title = "Order Confirmed!",
        subtitle = subtitle,
        step = 7,
        icon = Icons.Default.CheckCircle,
        color = Color(0xFF4CAF50),
        onBack = { navController.popBackStack() },
        onCart = { navController.navigate(Screen.Cart().route) }
    ) {
        Button(
            onClick = {
                // bitdrift SDK: startNewSession() begins a new session for the next journey,
                // keeping each purchase flow separate in the timeline.
                // POC: session management — clean per-user Timeline entries; each journey is its own session
                Logger.startNewSession()

                // bitdrift SDK: removeField() clears user_id when starting a new journey — session-level logout.
                context.getSharedPreferences("user_session", android.content.Context.MODE_PRIVATE)
                    .edit().remove("user_id").apply()
                Logger.removeField("user_id")

                navController.navigate(Screen.Welcome.route) {
                    popUpTo(Screen.Welcome.route) { inclusive = true }
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
