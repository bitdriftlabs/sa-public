import Capture
import SwiftUI

// MARK: - Step 1: Welcome

struct WelcomeScreen: View {
    @ObservedObject var sim: SimulationManager
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var latestSDKVersion: String?
    /// bitdrift SDK: createTemporaryDeviceCode() generates a short-lived code for
    /// locating this device's session in the dashboard.
    /// POC: support debugging — pull any reported session from production without
    /// a repro case.
    @State private var deviceCode: String?
    @State private var crashLoopOn = Prefs.crashLoop.bool(Prefs.keyActive)

    private var subtitle: String {
        guard let apiData else { return "Experience different shopping journeys" }
        let tagline = apiData.str("tagline")
        let promo = apiData["promotions"][0].str("title")
        return "\(tagline)\n\(promo)"
    }

    private var nextCrashLabel: String {
        let oomOnly = Prefs.crashLoop.bool(Prefs.keyOomOnly)
        let combo = Crashes.combo(
            atIndex: Prefs.crashLoop.int(Prefs.keyNextComboIndex), oomOnly: oomOnly
        )
        let context = combo.fireInBackground ? "background" : "foreground"
        let fast = Prefs.crashLoop.bool(Prefs.keyFastMode) ? " (fast)" : ""
        return "\(oomOnly ? "OOM loop" : "Crash loop") ACTIVE\(fast) — next: \(combo.name)/\(context)"
    }

    var body: some View {
        ScreenContainer(
            title: apiData?.str("store_name", "Welcome to bitdrift Shop") ?? "Welcome to bitdrift Shop",
            subtitle: subtitle,
            step: 1,
            systemImage: "cart.fill",
            color: Palette.blue,
            showLogo: true,
            latestSDKVersion: latestSDKVersion
        ) {
            PrimaryButton(title: "Browse Products", systemImage: "line.3.horizontal",
                          enabled: !sim.isSimulating) {
                nav.navigate(to: .browse)
            }

            SecondaryButton(title: "Search for Items", systemImage: "magnifyingglass",
                            enabled: !sim.isSimulating) {
                nav.navigate(to: .search)
            }

            Divider().padding(.vertical, 4)

            if sim.isSimulating {
                Text("Simulation in progress...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                if crashLoopOn {
                    Text(nextCrashLabel)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(.secondarySystemBackground), in: Capsule())

                    Button {
                        Prefs.crashLoop.set(Prefs.keyActive, false)
                        Prefs.crashLoop.set(Prefs.keyFastMode, false)
                        Prefs.crashLoop.set(Prefs.keyOomOnly, false)
                        crashLoopOn = false
                        sim.crashLoopEnabled = false
                        sim.fastCrashModeEnabled = false
                        sim.setVariant(sim.activeVariant)
                        ScreenLogger.logInfo("crash_loop_stopped")
                    } label: {
                        Text("Stop crash loop").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.deepRed)
                }

                HStack(spacing: 8) {
                    SimButton(title: "Sim 10", color: Palette.orange) {
                        sim.simulate(runs: 10, nav: nav)
                    }
                    SimButton(title: "SIM ∞", color: Palette.purple) {
                        sim.infiniteSimulate(nav: nav)
                    }
                }

                Button {
                    Logger.createTemporaryDeviceCode { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let code):
                                deviceCode = code
                                UIPasteboard.general.string = code
                            case .failure:
                                deviceCode = "⚠ needs_api_key"
                            }
                        }
                    }
                } label: {
                    Text(deviceCode ?? "Device Code")
                        .font(deviceCode != nil ? .caption.bold() : .subheadline.bold())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(deviceCode != nil ? Palette.blue : Color(.systemGray4))
                .foregroundStyle(deviceCode != nil ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                SecondaryButton(title: "Advanced", systemImage: "gearshape") {
                    nav.navigate(to: .advanced)
                }
            }
        }
        .task {
            apiData = try? await ApiClient.getWelcome()
            latestSDKVersion = await ApiClient.fetchLatestSDKVersion()
        }
        .onAppear {
            crashLoopOn = Prefs.crashLoop.bool(Prefs.keyActive)
        }
    }
}

// MARK: - Advanced controls

struct AdvancedScreen: View {
    @ObservedObject var sim: SimulationManager
    @ObservedObject var metrics: MetricsDemoManager
    @EnvironmentObject private var nav: Navigator

    @State private var hangOn = Prefs.appHang.bool(Prefs.keyActive)
    @State private var crashLoopOn = Prefs.crashLoop.bool(Prefs.keyActive)
    @State private var oomOnlyOn = Prefs.crashLoop.bool(Prefs.keyOomOnly)
    @State private var forceQuitOn = Prefs.forceQuit.bool(Prefs.keyActive)
    @State private var showHangReminder = false
    @State private var showQuitReminder = false
    @State private var supportLogEnabled = false

    private var isVariantASelected: Bool { sim.activeVariant == .variantA }

    private var statusLine: String {
        var crashText = "disabled"
        if crashLoopOn {
            let combo = Crashes.combo(
                atIndex: Prefs.crashLoop.int(Prefs.keyNextComboIndex), oomOnly: oomOnlyOn
            )
            let fastTag = Prefs.crashLoop.bool(Prefs.keyFastMode) ? "fast, " : ""
            let context = combo.fireInBackground ? "background" : "foreground"
            crashText = "\(oomOnlyOn ? "OOMs only, " : "")enabled (\(fastTag)next: \(combo.name)/\(context))"
        }
        let hangText = !isVariantASelected
            ? "unavailable (select Variant A)"
            : (hangOn ? "enabled" : "disabled")
        return "Crash: \(crashText) | Hang-A: \(hangText) | Quit: \(forceQuitOn ? "enabled" : "disabled")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { nav.popBackStack() } label: {
                    Image(systemName: "chevron.left").font(.title3)
                }
                .accessibilityLabel("Back")
                Text("Advanced").font(.title2.bold()).padding(.leading, 8)
                Spacer()
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Simulation Variant")

                    // bitdrift SDK: setVariant() calls setFeatureFlagExposure() so
                    // every log in the run is tagged with the active cohort.
                    HStack(spacing: 8) {
                        ForEach(SimVariant.allCases, id: \.self) { variant in
                            let selected = sim.activeVariant == variant
                            Button {
                                sim.setVariant(variant)
                            } label: {
                                Text(variant.label)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(selected ? variantColor(variant) : Color(.systemGray4))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if AppConfig.showSimAB {
                        SimButton(title: "SIM A/B", color: Palette.seafoam) {
                            sim.abSimulate(runsEach: 5, nav: nav)
                        }
                    }

                    faultGrid

                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)

                    Divider()

                    sectionHeader("Metrics Demo")

                    // bitdrift SDK: once a second, logs a single metric_values event
                    // with the waveform + counter fields, plus metric_work_latency_ms
                    // whose distribution auto-rotates across sim_app_version on its own.
                    ToggleChipButton(
                        title: metrics.isRunning ? "Metrics: ON" : "Metrics",
                        isOn: metrics.isRunning,
                        onColor: Palette.cyan
                    ) {
                        metrics.toggle()
                    }

                    Divider()

                    sectionHeader("Debug Tools")

                    // bitdrift SDK: addField("supportlog") tags all telemetry for
                    // filtering during support investigations.
                    // POC: ad-hoc debugging — filter Timeline to a specific device.
                    ToggleChipButton(
                        title: supportLogEnabled ? "Support Log: ON" : "Support Log: OFF",
                        isOn: supportLogEnabled,
                        onColor: Palette.green
                    ) {
                        supportLogEnabled.toggle()
                        Logger.addField(withKey: "supportlog", value: String(supportLogEnabled))
                    }
                }
            }
        }
        .padding(24)
        .onChange(of: isVariantASelected) { _ in syncHangEligibility() }
        .onAppear { syncHangEligibility() }
        .alert("Watchdog Script Required", isPresented: $showHangReminder) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("A main-thread hang freezes the app and then exits it. Run the host-side watchdog to relaunch:\n\nscripts/watchdog.sh")
        }
        .alert("Watchdog Script Required", isPresented: $showQuitReminder) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Force-quit terminates the process instantly. iOS apps cannot relaunch themselves — run the watchdog to detect the dead process and relaunch:\n\nscripts/watchdog.sh")
        }
    }

    private var faultGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            if AppConfig.showCardinality {
                ToggleChipButton(title: "Cardinality", isOn: false, onColor: Palette.red) {
                    sim.cardinalitySimulate(nav: nav)
                }
            }

            ToggleChipButton(
                title: sim.recommendationsV2Enabled ? "Rec v2: ON" : "Rec v2",
                isOn: sim.recommendationsV2Enabled,
                onColor: Palette.indigo
            ) {
                sim.recommendationsV2Enabled.toggle()
                sim.setVariant(sim.activeVariant)
            }

            // "Crash" always means the full catalog — turning it on clears
            // OOM-only mode, in case that was left on from the OOMs button.
            ToggleChipButton(
                title: crashLoopOn && !oomOnlyOn ? "Crash: ON" : "Crash",
                isOn: crashLoopOn && !oomOnlyOn,
                onColor: Palette.deepRed
            ) {
                let newState = !(crashLoopOn && !oomOnlyOn)
                Prefs.crashLoop.set(Prefs.keyActive, newState)
                Prefs.crashLoop.set(Prefs.keyOomOnly, false)
                crashLoopOn = newState
                oomOnlyOn = false
                sim.crashLoopEnabled = newState
                sim.setVariant(sim.activeVariant)
            }

            // "OOMs" is the same crash loop, restricted to Crashes.oomOnly.
            ToggleChipButton(
                title: crashLoopOn && oomOnlyOn ? "OOMs: ON" : "OOMs",
                isOn: crashLoopOn && oomOnlyOn,
                onColor: Palette.deepRed
            ) {
                let newState = !(crashLoopOn && oomOnlyOn)
                Prefs.crashLoop.set(Prefs.keyActive, newState)
                Prefs.crashLoop.set(Prefs.keyOomOnly, newState)
                crashLoopOn = newState
                oomOnlyOn = newState
                sim.crashLoopEnabled = newState
                sim.setVariant(sim.activeVariant)
            }

            ToggleChipButton(
                title: hangOn ? "Hang-A: ON" : "Hang-A",
                isOn: hangOn,
                onColor: Palette.crimson,
                enabled: isVariantASelected
            ) {
                let newState = !hangOn
                if newState { showHangReminder = true }
                Prefs.appHang.set(Prefs.keyActive, newState)
                hangOn = newState
                sim.appHangEnabled = newState
                sim.setVariant(sim.activeVariant)
            }

            ToggleChipButton(
                title: forceQuitOn ? "Quit: ON" : "Quit",
                isOn: forceQuitOn,
                onColor: Palette.amber
            ) {
                let newState = !forceQuitOn
                if newState { showQuitReminder = true }
                Prefs.forceQuit.set(Prefs.keyActive, newState)
                forceQuitOn = newState
                sim.forceQuitEnabled = newState
                sim.setVariant(sim.activeVariant)
            }
        }
    }

    /// Hang injection only ever fires on Variant A, so switching away from it
    /// silently disarms the flag rather than leaving it misleadingly "ON".
    private func syncHangEligibility() {
        guard !Prefs.appHang.bool(Prefs.keyRestartPending), !isVariantASelected, hangOn else { return }
        Prefs.appHang.set(Prefs.keyActive, false)
        hangOn = false
        sim.appHangEnabled = false
        sim.setVariant(sim.activeVariant)
    }

    private func variantColor(_ variant: SimVariant) -> Color {
        switch variant {
        case .control: return Palette.slate
        case .variantA: return Palette.cyan
        case .variantB: return Palette.orange
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Step 2: Browse / Search

struct BrowseScreen: View {
    @ObservedObject var sim: SimulationManager
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var products: [JSON] = []
    @State private var catalogJSON = "[]"

    /// Computed in the view body, unmemoized — the slow-rendering trap. See
    /// `RecommendationEngine` and `android/demo-slow-rendering.md`.
    private var recommendations: [(product: JSON, score: Double)] {
        guard sim.recommendationsV2Enabled, let first = products.first else { return [] }
        let pid = first.str("id")
        // bitdrift SDK: trackSpan() wraps the scoring work and records its
        // duration in the session timeline; ends SUCCESS on return, FAILURE on
        // throw. On iOS this span is the primary detection path for the jank —
        // the OOTB DROPPED_FRAME condition is Android-only.
        // POC: event tracking — unsampled duration histogram (p50/p95).
        return CaptureBridge.trackSpan(
            "score_products",
            fields: ["product_id": pid, "screen_name": "Browse"]
        ) {
            RecommendationEngine.scoreProducts(catalogJSON: catalogJSON, referenceProductID: pid)
        }
    }

    private var subtitle: String {
        guard let apiData else { return "Explore our product catalog" }
        return "Showing \(products.count) of \(apiData.int("total_products")) products"
    }

    var body: some View {
        ScreenContainer(
            title: "Browse",
            subtitle: subtitle,
            step: 2,
            systemImage: "line.3.horizontal",
            color: Palette.purple,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            RecommendedSection(recommendations: recommendations) { productID in
                nav.navigate(to: .productDetail(source: "browse", productID: productID))
            }
            ProductImageRow(products: products) { productID in
                nav.navigate(to: .productDetail(source: "browse", productID: productID))
            }
            PrimaryButton(title: "View Featured", systemImage: "star.fill") {
                nav.navigate(to: .featured)
            }
            SecondaryButton(title: "Shop by Category", systemImage: "list.bullet") {
                nav.navigate(to: .categories)
            }
        }
        .task {
            apiData = try? await ApiClient.getBrowse()
            products = apiData?["products"].array ?? []
            catalogJSON = apiData?["products"].serialized ?? "[]"
        }
    }
}

struct SearchScreen: View {
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var products: [JSON] = []

    private var subtitle: String {
        guard let apiData else { return "Find exactly what you're looking for" }
        return "Found \(apiData.int("result_count")) results for \"\(apiData.str("query"))\""
    }

    var body: some View {
        ScreenContainer(
            title: "Search",
            subtitle: subtitle,
            step: 2,
            systemImage: "magnifyingglass",
            color: Palette.orange,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            ProductImageRow(products: products) { productID in
                nav.navigate(to: .productDetail(source: "search", productID: productID))
            }
            PrimaryButton(title: "View Featured", systemImage: "star.fill") {
                nav.navigate(to: .featured)
            }
            SecondaryButton(title: "Shop by Category", systemImage: "list.bullet") {
                nav.navigate(to: .categories)
            }
        }
        .task {
            apiData = try? await ApiClient.search("headphones")
            products = apiData?["products"].array ?? []
        }
    }
}

// MARK: - Step 3: Featured / Categories

struct FeaturedProductsScreen: View {
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var products: [JSON] = []
    @State private var firstProductID = "prod_a1b2c3"

    private var subtitle: String {
        guard let apiData else { return "Our top picks for you" }
        return "\(apiData["banner"].str("text")) — \(products.count) picks"
    }

    var body: some View {
        ScreenContainer(
            title: "Featured Products",
            subtitle: subtitle,
            step: 3,
            systemImage: "star.fill",
            color: Palette.yellow,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            ProductImageRow(products: products) { productID in
                nav.navigate(to: .productDetail(source: "featured", productID: productID))
            }
            PrimaryButton(title: "View Product Details", systemImage: "info.circle") {
                nav.navigate(to: .productDetail(source: "featured", productID: firstProductID))
            }
            SecondaryButton(title: "Read Reviews First", systemImage: "envelope") {
                nav.navigate(to: .reviews(source: "featured", productID: firstProductID))
            }
        }
        .task {
            apiData = try? await ApiClient.getFeatured()
            products = apiData?["featured_products"].array ?? []
            firstProductID = products.first?.str("id", firstProductID) ?? firstProductID
        }
    }
}

struct CategoriesScreen: View {
    @EnvironmentObject private var nav: Navigator

    @State private var categories: [JSON] = []

    private var subtitle: String {
        categories.isEmpty
            ? "Browse by product type"
            : categories.map { $0.str("name") }.joined(separator: ", ")
    }

    var body: some View {
        ScreenContainer(
            title: "Categories",
            subtitle: subtitle,
            step: 3,
            systemImage: "list.bullet",
            color: Palette.green,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            CategoryRow(categories: categories) { name in
                nav.navigate(to: .categoryBrowse(category: name))
            }
            PrimaryButton(title: "View Product Details", systemImage: "info.circle") {
                nav.navigate(to: .productDetail(source: "categories", productID: "prod_a1b2c3"))
            }
            SecondaryButton(title: "Read Reviews First", systemImage: "envelope") {
                nav.navigate(to: .reviews(source: "categories", productID: "prod_a1b2c3"))
            }
        }
        .task {
            categories = (try? await ApiClient.getCategories())?["categories"].array ?? []
        }
    }
}

// MARK: - Step 3b: Category Browse

struct CategoryBrowseScreen: View {
    let category: String
    @EnvironmentObject private var nav: Navigator

    @State private var products: [JSON] = []
    @State private var firstProductID = "prod_a1b2c3"

    private var subtitle: String {
        products.isEmpty ? "Loading \(category)..." : "\(products.count) products in \(category)"
    }

    var body: some View {
        ScreenContainer(
            title: category,
            subtitle: subtitle,
            step: 3,
            systemImage: "list.bullet",
            color: Palette.green,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            ProductImageRow(products: products) { productID in
                nav.navigate(to: .productDetail(source: "categories", productID: productID))
            }
            PrimaryButton(title: "View Product Details", systemImage: "info.circle") {
                nav.navigate(to: .productDetail(source: "categories", productID: firstProductID))
            }
            SecondaryButton(title: "Read Reviews First", systemImage: "envelope") {
                nav.navigate(to: .reviews(source: "categories", productID: firstProductID))
            }
        }
        .task(id: category) {
            products = (try? await ApiClient.getCategoryProducts(category))?["products"].array ?? []
            firstProductID = products.first?.str("id", firstProductID) ?? firstProductID
        }
    }
}

// MARK: - Step 4: Product Detail / Reviews

struct ProductDetailScreen: View {
    let source: String
    let productID: String
    @ObservedObject var sim: SimulationManager
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var catalogJSON = "[]"

    /// Unmemoized on purpose — see `BrowseScreen.recommendations`.
    private var recommendations: [(product: JSON, score: Double)] {
        guard sim.recommendationsV2Enabled else { return [] }
        return CaptureBridge.trackSpan(
            "score_products",
            fields: ["product_id": productID, "screen_name": "ProductDetail"]
        ) {
            RecommendationEngine.scoreProducts(catalogJSON: catalogJSON, referenceProductID: productID)
        }
    }

    private var subtitle: String {
        guard let apiData else { return "Loading..." }
        return "\(apiData.str("brand")) — \(money(apiData.num("price"))) — \(apiData.int("stock_count")) in stock"
    }

    var body: some View {
        ScreenContainer(
            title: apiData?.str("name", "Product Details") ?? "Product Details",
            subtitle: subtitle,
            step: 4,
            systemImage: "bell.fill",
            color: Palette.cyan,
            imageURL: apiData?["images"][0].string,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            RecommendedSection(recommendations: recommendations) { recProductID in
                nav.navigate(to: .productDetail(source: "browse", productID: recProductID))
            }
            PrimaryButton(title: "Add to Cart", systemImage: "plus") {
                // bitdrift SDK: logInfo() with a stable event name and field map
                // enables aggregation in the dashboard.
                ScreenLogger.logInfo("add_to_cart", ["product_id": productID, "source_screen": source])
                nav.navigate(to: .cart(productID: productID))
            }
            SecondaryButton(title: "Save to Wishlist", systemImage: "heart.fill") {
                ScreenLogger.logInfo("add_to_wishlist", ["product_id": productID, "source_screen": source])
                nav.navigate(to: .wishlist(productID: productID))
            }
        }
        .task(id: productID) {
            apiData = try? await ApiClient.getProduct(productID)
            if sim.recommendationsV2Enabled {
                catalogJSON = (try? await ApiClient.getFullCatalogJSON()) ?? "[]"
            }
        }
    }
}

struct ReviewsScreen: View {
    let source: String
    let productID: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?

    private var subtitle: String {
        guard let apiData else { return "Loading reviews..." }
        let topTitle = apiData["reviews"][0].str("title")
        return "\(apiData.num("average_rating")) stars from \(apiData.int("total_reviews")) reviews\n\"\(topTitle)\""
    }

    var body: some View {
        ScreenContainer(
            title: "Customer Reviews",
            subtitle: subtitle,
            step: 4,
            systemImage: "envelope",
            color: Palette.teal,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            PrimaryButton(title: "Add to Cart", systemImage: "plus") {
                ScreenLogger.logInfo("add_to_cart", ["product_id": productID, "source_screen": source])
                nav.navigate(to: .cart(productID: productID))
            }
            SecondaryButton(title: "Save to Wishlist", systemImage: "heart.fill") {
                ScreenLogger.logInfo("add_to_wishlist", ["product_id": productID, "source_screen": source])
                nav.navigate(to: .wishlist(productID: productID))
            }
        }
        .task(id: productID) {
            apiData = try? await ApiClient.getReviews(productID)
        }
    }
}

// MARK: - Step 5: Cart / Wishlist

struct CartScreen: View {
    let productID: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?

    private var items: [JSON] { apiData?["items"].array ?? [] }

    private var subtitle: String {
        guard let apiData else { return "Loading cart..." }
        let count = items.count
        guard count > 0 else { return "Your cart is empty" }
        return "\(count) item\(count > 1 ? "s" : "") — Total: \(money(apiData.num("total"))) (incl. \(money(apiData.num("tax"))) tax)"
    }

    var body: some View {
        ScreenContainer(
            title: "Shopping Cart",
            subtitle: subtitle,
            step: 5,
            systemImage: "cart.fill",
            color: Palette.blue,
            onBack: { nav.popBackStack() }
        ) {
            if !items.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            cartRow(item)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            PrimaryButton(title: "Checkout as Guest", systemImage: "person") {
                // bitdrift SDK: logInfo() records checkout funnel entry for
                // conversion tracking.
                ScreenLogger.logInfo("checkout_started", ["checkout_type": "guest"])
                nav.navigate(to: .checkoutGuest(productID: productID))
            }
            SecondaryButton(title: "Sign In to Checkout", systemImage: "lock") {
                ScreenLogger.logInfo("checkout_started", ["checkout_type": "signin"])
                nav.navigate(to: .checkoutSignIn(productID: productID))
            }
            SecondaryButton(title: "Keep Shopping", systemImage: "cart") {
                nav.popToWelcome()
            }
        }
        .task(id: productID) {
            do {
                apiData = productID.isEmpty
                    ? try await ApiClient.getCart()
                    : try await ApiClient.addToCart(productID)
            } catch {
                // bitdrift SDK: logError() with an error captures the exception in
                // the session timeline.
                ScreenLogger.logError("cart_failed", error: error, ["product_id": productID])
            }
        }
    }

    private func cartRow(_ item: JSON) -> some View {
        let itemProductID = item.str("product_id")
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.str("name")).font(.subheadline.bold()).lineLimit(1)
                Text("Qty: \(item.int("quantity", 1))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(item.num("line_total"))).font(.subheadline.bold())
            Button {
                // bitdrift SDK: logInfo() records cart mutations for funnel analysis.
                ScreenLogger.logInfo("cart_item_removed", ["product_id": itemProductID])
                Task { apiData = try? await ApiClient.deleteCartItem(itemProductID) }
            } label: {
                Image(systemName: "trash").foregroundStyle(Palette.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WishlistScreen: View {
    let productID: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?

    private var subtitle: String {
        guard let apiData else { return "Loading wishlist..." }
        return "\(apiData.int("item_count")) items saved — \(apiData["items"][0].str("name"))"
    }

    var body: some View {
        ScreenContainer(
            title: "Wishlist",
            subtitle: subtitle,
            step: 5,
            systemImage: "heart.fill",
            color: Palette.pink,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            PrimaryButton(title: "Checkout as Guest", systemImage: "person") {
                nav.navigate(to: .checkoutGuest(productID: productID))
            }
            SecondaryButton(title: "Sign In to Checkout", systemImage: "lock") {
                nav.navigate(to: .checkoutSignIn(productID: productID))
            }
        }
        .task(id: productID) {
            apiData = try? await ApiClient.addToWishlist(productID)
        }
    }
}

// MARK: - Step 6: Checkout options

struct CheckoutGuestScreen: View {
    let productID: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var checkoutSession = ""

    private var subtitle: String {
        guard let apiData else { return "Loading checkout..." }
        let city = apiData["shipping_address"].str("city")
        let total = apiData["order_preview"].num("total")
        return "Shipping to \(city) — \(money(total))\n\(apiData.str("email"))"
    }

    var body: some View {
        ScreenContainer(
            title: "Guest Checkout",
            subtitle: subtitle,
            step: 6,
            systemImage: "person",
            color: Palette.indigo,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            PrimaryButton(title: "Pay with Card", systemImage: "checkmark") {
                nav.navigate(to: .paymentCard(checkoutSession: checkoutSession))
            }
            SecondaryButton(title: "Apple Pay", systemImage: "apple.logo") {
                nav.navigate(to: .paymentApplePay(checkoutSession: checkoutSession))
            }
        }
        .task {
            do {
                let data = try await ApiClient.checkoutGuest()
                apiData = data
                checkoutSession = data.str("checkout_session")
            } catch {
                ScreenLogger.logError("checkout_failed", error: error, ["checkout_type": "guest"])
            }
        }
    }
}

struct CheckoutSignInScreen: View {
    let productID: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var checkoutSession = ""

    private var subtitle: String {
        guard let apiData else { return "Loading checkout..." }
        let user = apiData["user"]
        let total = apiData["order_preview"].num("total")
        return "Welcome back, \(user.str("name"))\n\(user.str("email")) — \(user.int("loyalty_points")) pts — \(money(total))"
    }

    var body: some View {
        ScreenContainer(
            title: "Member Checkout",
            subtitle: subtitle,
            step: 6,
            systemImage: "lock",
            color: Palette.seafoam,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            PrimaryButton(title: "Pay with Card", systemImage: "checkmark") {
                nav.navigate(to: .paymentCard(checkoutSession: checkoutSession))
            }
            SecondaryButton(title: "PayPal", systemImage: "paperplane") {
                nav.navigate(to: .paymentPayPal(checkoutSession: checkoutSession))
            }
        }
        .task {
            do {
                let data = try await ApiClient.checkoutSignIn()
                apiData = data
                checkoutSession = data.str("checkout_session")
                // bitdrift SDK: addField() sets user_id on the session so every
                // subsequent log is tagged with this user. Persisted to
                // UserDefaults so UserIDFieldProvider survives startNewSession().
                // POC: per-user debugging — user_id appears in the Timeline
                // session header for instant identification.
                // `/api/checkout/signin` returns name, email, member_since and
                // loyalty_points — but no `id` (see backend/shopping_server.py).
                // Reading `id` alone left user_id permanently unset, so manual
                // sign-in never tagged the session despite the code claiming to.
                // Email is the only stable identifier the contract actually
                // provides. Fixed here rather than by adding a field to the
                // backend, which is shared with the other platform apps.
                let user = data["user"]
                let userID = user.str("id").isEmpty ? user.str("email") : user.str("id")
                if !userID.isEmpty {
                    Prefs.userSession.set(Prefs.keyUserID, userID)
                    Logger.addField(withKey: "user_id", value: userID)
                }
            } catch {
                ScreenLogger.logError("checkout_failed", error: error, ["checkout_type": "signin"])
            }
        }
    }
}

// MARK: - Step 6b: Payment methods

/// The four payment screens differ only in endpoint, copy, and colour, so they
/// share one implementation rather than four near-identical copies. Screen names
/// still come from the route (`Screen.screenName`), so the Sankey sees them as
/// four distinct destinations exactly as on Android.
struct PaymentScreen: View {
    enum Method {
        case card, applePay, payPal, androidPay

        var title: String {
            switch self {
            case .card: return "Card Payment"
            case .applePay: return "Apple Pay"
            case .payPal: return "PayPal"
            case .androidPay: return "Android Pay"
            }
        }

        /// Field value used in `payment_failed` logs; matches Android exactly.
        var fieldValue: String {
            switch self {
            case .card: return "card"
            case .applePay: return "apple_pay"
            case .payPal: return "paypal"
            case .androidPay: return "android_pay"
            }
        }

        var systemImage: String {
            switch self {
            case .card: return "checkmark"
            case .applePay: return "apple.logo"
            case .payPal: return "paperplane"
            case .androidPay: return "iphone"
            }
        }

        var color: Color {
            switch self {
            case .card: return Palette.blue
            case .applePay: return .black
            case .payPal: return Palette.blue
            case .androidPay: return Palette.green
            }
        }

        var loadingText: String {
            switch self {
            case .card: return "Processing payment..."
            case .applePay, .androidPay: return "Authenticating..."
            case .payPal: return "Connecting to PayPal..."
            }
        }

        func call(_ session: String) async throws -> JSON {
            switch self {
            case .card: return try await ApiClient.payCard(session)
            case .applePay: return try await ApiClient.payApplePay(session)
            case .payPal: return try await ApiClient.payPayPal(session)
            case .androidPay: return try await ApiClient.payAndroidPay(session)
            }
        }
    }

    let method: Method
    let checkoutSession: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?
    @State private var orderID = ""

    private var subtitle: String {
        guard let apiData else { return method.loadingText }
        let amount = money(apiData.num("amount_charged"))
        let txn = String(apiData.str("transaction_id").prefix(20))
        switch method {
        case .card:
            return "\(apiData.str("payment_method"))\n\(amount) — \(txn)…"
        case .payPal:
            return "PayPal — \(amount)\nRef: \(apiData.str("paypal_reference"))"
        case .applePay:
            return "Apple Pay — \(amount)\n\(txn)…"
        case .androidPay:
            return "Android Pay — \(amount)\n\(txn)…"
        }
    }

    var body: some View {
        ScreenContainer(
            title: method.title,
            subtitle: subtitle,
            step: 6,
            systemImage: method.systemImage,
            color: method.color,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            if method == .card {
                cardOption(label: "Visa ending 4242", brand: "visa", last4: "4242", primary: true)
                cardOption(label: "Mastercard ending 8888", brand: "mastercard", last4: "8888", primary: false)
                cardOption(label: "Amex ending 1001", brand: "amex", last4: "1001", primary: false)
            } else {
                PrimaryButton(title: "Complete Purchase", systemImage: "checkmark.circle") {
                    // bitdrift SDK: logInfo() records payment completion. Emitted
                    // for every method, not just card — the shared checkout-funnel
                    // workflow keys on this event, so omitting it here silently
                    // excluded every Apple Pay / PayPal / Android Pay completion
                    // from the conversion numbers.
                    ScreenLogger.logInfo("payment_completed", [
                        "payment_method": method.fieldValue,
                        "order_id": orderID,
                    ])
                    nav.navigate(to: .confirmation(orderID: orderID))
                }
            }
        }
        .task(id: checkoutSession) {
            do {
                let data = try await method.call(checkoutSession)
                apiData = data
                orderID = data.str("order_id")
            } catch {
                // bitdrift SDK: logError() with an error records payment failures
                // in the session timeline.
                ScreenLogger.logError("payment_failed", error: error, ["payment_method": method.fieldValue])
            }
        }
    }

    @ViewBuilder
    private func cardOption(label: String, brand: String, last4: String, primary: Bool) -> some View {
        let tap = {
            // bitdrift SDK: logInfo() records payment completion with method and
            // order ID for conversion tracking.
            ScreenLogger.logInfo("payment_completed", [
                "payment_method": brand, "card_last4": last4, "order_id": orderID,
            ])
            nav.navigate(to: .confirmation(orderID: orderID))
        }
        if primary {
            PrimaryButton(title: label, systemImage: "checkmark", action: tap)
        } else {
            SecondaryButton(title: label, systemImage: "checkmark", action: tap)
        }
    }
}

// MARK: - Payment failed

struct PaymentFailedScreen: View {
    let paymentMethod: String
    let checkoutSession: String
    @EnvironmentObject private var nav: Navigator

    private var methodLabel: String {
        switch paymentMethod {
        case "card": return "Credit Card"
        case "apple_pay": return "Apple Pay"
        case "paypal": return "PayPal"
        case "android_pay": return "Android Pay"
        default: return paymentMethod.prefix(1).uppercased() + paymentMethod.dropFirst()
        }
    }

    var body: some View {
        ScreenContainer(
            title: "Payment Failed",
            subtitle: "Your \(methodLabel) payment could not be processed.\nPlease try again or use a different payment method.",
            step: 6,
            systemImage: "exclamationmark.triangle.fill",
            color: Palette.red,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                nav.popBackStack()
            }
        }
    }
}

// MARK: - Step 7: Confirmation (all paths converge)

struct ConfirmationScreen: View {
    let orderID: String
    @EnvironmentObject private var nav: Navigator

    @State private var apiData: JSON?

    private var subtitle: String {
        if Prefs.crashLoop.bool(Prefs.keyActive) {
            OrderSummaryHelper.reset()
            return OrderSummaryHelper.formatOrderSummary(apiData, orderID: orderID)
        }
        guard let apiData else { return "Order \(orderID)\nThank you for your purchase!" }
        let shipping = apiData["shipping"]
        return """
        Order \(apiData.str("order_id", orderID))
        Total: \(money(apiData.num("total")))
        Delivery: \(shipping.str("estimated_delivery"))
        Tracking: \(shipping.str("tracking_number"))
        Txn: \(String(apiData.str("transaction_id").prefix(24)))…
        """
    }

    var body: some View {
        ScreenContainer(
            title: "Order Confirmed!",
            subtitle: subtitle,
            step: 7,
            systemImage: "checkmark.circle.fill",
            color: Palette.green,
            onBack: { nav.popBackStack() },
            onCart: { nav.navigate(to: .cart(productID: "")) }
        ) {
            Button {
                // bitdrift SDK: startNewSession() begins a new session for the next
                // journey, keeping each purchase flow separate in the timeline.
                // POC: session management — clean per-user Timeline entries.
                Logger.startNewSession()

                // bitdrift SDK: removeField() clears user_id when starting a new
                // journey — session-level logout.
                Prefs.userSession.remove(Prefs.keyUserID)
                Logger.removeField(withKey: "user_id")

                nav.popToWelcome()
            } label: {
                Label("Start New Journey", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.green)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .task(id: orderID) {
            apiData = try? await ApiClient.getConfirmation(orderID)
        }
    }
}
