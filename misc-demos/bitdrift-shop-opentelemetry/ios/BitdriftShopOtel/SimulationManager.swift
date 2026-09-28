import Capture
import Foundation

/// Three simulation presets, each representing a distinct user cohort. Selecting a preset
/// records feature flag exposures on the current bitdrift session so every log in the run is
/// automatically tagged with the active variant -- enabling dashboard slicing by
/// checkout_flow, payment_ui, and cart_abandon_rate. Mirrors `SimVariant` in `SimulationManager.kt`.
enum SimVariant: String, CaseIterable {
    case control = "Control"    // baseline: fully random, no variant bias
    case variantA = "Variant A" // digital native: snap decisions, skips research, guest + digital pay
    case variantB = "Variant B" // deliberate shopper: reads everything, huge cart churn, signin + card

    var label: String { self.rawValue }
}

/// Handles automated simulation of user journeys through the app. Randomly selects paths at each
/// decision point to generate varied journey data. Direct port of `SimulationManager.kt`, minus
/// the Android-specific ANR (App Not Responding) injection path -- iOS has no ANR-dialog
/// equivalent, and the closest analog (watchdog hangs, per `bitdrift-shop/ios-clean`) is a
/// separate crash-demo concern out of scope here. Everything else -- variant-biased branching,
/// feature flag exposure, and the full random journey walk -- matches exactly.
@MainActor
final class SimulationManager: ObservableObject {
    @Published private(set) var isSimulating = false
    @Published private(set) var currentRun = 0
    @Published private(set) var totalRuns = 0
    @Published var slowModeEnabled = false
    @Published private(set) var activeVariant: SimVariant = .control

    private var isCancelled = false
    private let stepDelayNanos: UInt64 = 50_000_000 // 50ms

    var isInfiniteMode: Bool { self.totalRuns == -1 }

    // Workshop 6 -- Feature Flag Exposure (basic sdk)
    // Called when the user taps a preset button. Records exposure at the moment the variant is
    // chosen -- which is the moment it starts affecting simulator behaviour. All logs in
    // subsequent runs are tagged with the three active flag values.
    func setVariant(_ variant: SimVariant) {
        self.activeVariant = variant
        let checkoutFlow = switch variant {
        case .control: "random"
        case .variantA: "guest"
        case .variantB: "signin"
        }
        let paymentUi = switch variant {
        case .control: "random"
        case .variantA: "digital"
        case .variantB: "card"
        }
        let cartAbandon = switch variant {
        case .control: "medium"
        case .variantA: "high"
        case .variantB: "low"
        }
        Capture.Logger.shared?.setFeatureFlagExposure(withName: "checkout_flow", variant: checkoutFlow)
        Capture.Logger.shared?.setFeatureFlagExposure(withName: "payment_ui", variant: paymentUi)
        Capture.Logger.shared?.setFeatureFlagExposure(withName: "cart_abandon_rate", variant: cartAbandon)
        Capture.Logger.shared?.addField(withKey: "ff_checkout_flow", value: checkoutFlow)
        Capture.Logger.shared?.addField(withKey: "ff_payment_ui", value: paymentUi)
        Capture.Logger.shared?.addField(withKey: "ff_cart_abandon_rate", value: cartAbandon)
        Capture.Logger.shared?.addField(withKey: "ff_variant", value: variant.label)
        Capture.Logger.shared?.logInfo("feature_flag_exposure_set")
    }

    func cancel() {
        self.isCancelled = true
        ScreenLogger.logInfo("simulation_cancelled", ["completed_runs": String(self.currentRun), "total_runs": String(self.totalRuns)])
    }

    func simulate(_ runs: Int, router: Router) {
        Task {
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = runs
            self.currentRun = 0
            ScreenLogger.logSimulationStart(runs)

            for i in 1 ... runs {
                if self.isCancelled { break }
                self.currentRun = i
                await self.runSingleJourney(router)
                if self.isCancelled { break }
                try? await Task.sleep(nanoseconds: self.stepDelayNanos)
            }

            ScreenLogger.logSimulationEnd(self.isCancelled ? self.currentRun : runs)
            router.popToWelcome()
            self.isSimulating = false
            self.currentRun = 0
            self.totalRuns = 0
            self.isCancelled = false
        }
    }

    /// Workshop 6 -- A/B split sim: runs `runsEach` journeys as Variant A then `runsEach` as
    /// Variant B. Each journey cycles through Control -> Variant A -> Variant B -> Control -> ...
    /// so every run is a flag transition, maximizing workflow matches.
    func abSimulate(runsEach: Int, router: Router) {
        Task {
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = runsEach * 3
            self.currentRun = 0
            let variants = SimVariant.allCases

            ScreenLogger.logInfo("ab_simulation_start", ["runs_each": String(runsEach)])

            for i in 0 ..< self.totalRuns {
                if self.isCancelled { break }
                self.activeVariant = variants[i % variants.count]
                self.currentRun += 1
                await self.runSingleJourney(router)
                try? await Task.sleep(nanoseconds: self.stepDelayNanos)
            }

            ScreenLogger.logInfo("ab_simulation_end", ["total_runs": String(self.currentRun)])
            router.popToWelcome()
            self.isSimulating = false
            self.currentRun = 0
            self.totalRuns = 0
            self.isCancelled = false
        }
    }

    func infiniteSimulate(router: Router) {
        Task {
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = -1
            self.currentRun = 0
            ScreenLogger.logInfo("infinite_simulation_start")

            while !self.isCancelled {
                self.currentRun += 1
                await self.runSingleJourney(router)
                try? await Task.sleep(nanoseconds: self.stepDelayNanos)
            }

            ScreenLogger.logInfo("infinite_simulation_end", ["total_runs": String(self.currentRun)])
            router.popToWelcome()
            self.isSimulating = false
            self.currentRun = 0
            self.totalRuns = 0
            self.isCancelled = false
        }
    }

    /// Cardinality demo: hammers `/api/inventory/lookup/{item}/{session}` with a fresh random
    /// session path segment on every request, flooding the Bitdrift dashboard with
    /// infinite-cardinality URLs. Runs until cancelled.
    func cardinalitySimulate(router: Router) {
        Task {
            self.isSimulating = true
            self.isCancelled = false
            self.totalRuns = -1
            self.currentRun = 0
            ScreenLogger.logInfo("cardinality_simulation_start")

            while !self.isCancelled {
                self.currentRun += 1
                let item = Self.searchQueries.randomElement()!
                _ = try? await ApiClient.inventoryLookup(item)
                try? await Task.sleep(nanoseconds: self.stepDelayNanos)
            }

            ScreenLogger.logInfo("cardinality_simulation_end", ["total_runs": String(self.currentRun)])
            router.popToWelcome()
            self.isSimulating = false
            self.currentRun = 0
            self.totalRuns = 0
            self.isCancelled = false
        }
    }

    // ============================================================================
    // Fully random journey simulator -- each journey walks through every major step
    // of the shopping funnel, randomly choosing a branch at each decision point.
    //
    //  Welcome
    //    -> discovery: Browse | Search | Categories->CategoryBrowse (random)
    //    -> maybe Featured (coin flip)
    //    -> ProductDetail
    //    -> maybe Reviews (coin flip)
    //    -> maybe Wishlist (coin flip)
    //    -> Cart
    //    -> checkout: CheckoutGuest | CheckoutSignIn (random)
    //    -> payment: PaymentCard | PaymentApplePay | PaymentPayPal | PaymentAndroidPay (random)
    //    -> Confirmation
    // ============================================================================

    private static let searchQueries = [
        "headphones", "jacket", "running shoes", "laptop", "watch",
        "camera", "speaker", "backpack", "tablet", "sneakers",
    ]

    private func nav(_ router: Router, _ screen: Screen) async {
        router.navigate(to: screen)
        try? await Task.sleep(nanoseconds: self.stepDelayNanos)
    }

    // Fetch helpers return only real product IDs from the backend's own response -- never a
    // fabricated placeholder. A hardcoded fallback ID doesn't exist in the OpenTelemetry Demo
    // catalog, so using one would cause every downstream call to fail with a real backend
    // 500/NOT_FOUND instead of the simulation just skipping this journey.
    private func fetchBrowseIds() async -> [String] {
        (try? await ApiClient.getBrowse().optJSONArray("products")?.compactMap { $0.optString("id").isEmpty ? nil : $0.optString("id") }) ?? []
    }

    private func fetchSearchIds() async -> [String] {
        (try? await ApiClient.search(Self.searchQueries.randomElement()!).optJSONArray("products")?.compactMap { $0.optString("id").isEmpty ? nil : $0.optString("id") }) ?? []
    }

    private func fetchFeaturedIds() async -> [String] {
        (try? await ApiClient.getFeatured().optJSONArray("featured_products")?.compactMap { $0.optString("id").isEmpty ? nil : $0.optString("id") }) ?? []
    }

    private func fetchCategoryNames() async -> [String] {
        let names = (try? await ApiClient.getCategories().optJSONArray("categories")?.map { $0.optString("name", "Electronics") }) ?? nil
        return (names?.isEmpty ?? true) ? ["Electronics"] : names!
    }

    private func fetchCategoryProductIds(_ category: String) async -> [String] {
        (try? await ApiClient.getCategoryProducts(category).optJSONArray("products")?.compactMap { $0.optString("id").isEmpty ? nil : $0.optString("id") }) ?? []
    }

    private func runSingleJourney(_ router: Router) async { // swiftlint:disable:this function_body_length cyclomatic_complexity
        // Workshop 1d (Session Strategy): start a new session for each journey so each shopping
        // flow is tracked independently in the bitdrift dashboard.
        Capture.Logger.startNewSession()
        try? await Task.sleep(nanoseconds: 200_000_000)
        self.setVariant(self.activeVariant)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // -- Step 1: Welcome --
        router.popToWelcome()
        _ = try? await ApiClient.getWelcome()
        try? await Task.sleep(nanoseconds: self.stepDelayNanos)

        // -- Step 2: Discovery -- randomly pick Browse, Search, or Categories, variant-biased.
        var productIds: [String]
        var source: String
        let discoveryRoll = Double.random(in: 0 ..< 1)
        let discoveryChoice: Int = switch self.activeVariant {
        case .variantA: discoveryRoll < 0.40 ? 0 : (discoveryRoll < 0.85 ? 1 : 2)
        case .variantB: discoveryRoll < 0.25 ? 0 : (discoveryRoll < 0.50 ? 1 : 2)
        case .control: Int.random(in: 0 ... 2)
        }
        switch discoveryChoice {
        case 0:
            await self.nav(router, .browse)
            productIds = await self.fetchBrowseIds()
            source = "browse"
        case 1:
            await self.nav(router, .search)
            productIds = await self.fetchSearchIds()
            source = "search"
        default:
            await self.nav(router, .categories)
            let cat = await self.fetchCategoryNames().randomElement()!
            await self.nav(router, .categoryBrowse(category: cat))
            productIds = await self.fetchCategoryProductIds(cat)
            source = "categories"
        }

        let featuredProb: Double = switch self.activeVariant {
        case .control: 0.5
        case .variantA: 0.15
        case .variantB: 0.75
        }
        if Double.random(in: 0 ..< 1) < featuredProb {
            await self.nav(router, .featuredProducts)
            let featIds = await self.fetchFeaturedIds()
            if !featIds.isEmpty {
                productIds = featIds
                source = "featured"
            }
        }

        guard let pid = productIds.randomElement() else { return }

        // -- Step 3: ProductDetail --
        await self.nav(router, .productDetail(source: source, productId: pid))
        _ = try? await ApiClient.getProduct(pid)

        let reviewsProb: Double = switch self.activeVariant {
        case .control: 0.5
        case .variantA: 0.10
        case .variantB: 0.90
        }
        if Double.random(in: 0 ..< 1) < reviewsProb {
            await self.nav(router, .reviews(source: source, productId: pid))
            _ = try? await ApiClient.getReviews(pid)
        }

        let wishlistProb: Double = switch self.activeVariant {
        case .control: 0.4
        case .variantA: 0.05
        case .variantB: 0.75
        }
        if Double.random(in: 0 ..< 1) < wishlistProb {
            await self.nav(router, .wishlist(productId: pid))
            _ = try? await ApiClient.addToWishlist(pid)
        }

        // -- Step 4: Cart -- add items; A adds just 1, B loads up with 3-5.
        var cartItems = [pid]
        await self.nav(router, .cart(productId: pid))
        _ = try? await ApiClient.addToCart(pid)

        let extraCount: Int = switch self.activeVariant {
        case .control: Int.random(in: 1 ... 3)
        case .variantA: Int.random(in: 0 ... 1)
        case .variantB: Int.random(in: 2 ... 4)
        }
        for _ in 0 ..< extraCount {
            let extraPid = productIds.randomElement()!
            cartItems.append(extraPid)
            _ = try? await ApiClient.addToCart(extraPid, quantity: Int.random(in: 1 ... 3))
            try? await Task.sleep(nanoseconds: self.stepDelayNanos)
        }

        _ = try? await ApiClient.getCart()
        try? await Task.sleep(nanoseconds: self.stepDelayNanos)

        let removeProb: Double = switch self.activeVariant {
        case .control: 0.6
        case .variantA: 0.10
        case .variantB: 0.90
        }
        if Double.random(in: 0 ..< 1) < removeProb, cartItems.count > 1 {
            let removePid = cartItems.remove(at: Int.random(in: 0 ..< cartItems.count))
            _ = try? await ApiClient.deleteCartItem(removePid)
            try? await Task.sleep(nanoseconds: self.stepDelayNanos)
        }

        let emptyCartProb: Double = switch self.activeVariant {
        case .control: 0.2
        case .variantA: 0.05
        case .variantB: 0.60
        }
        if Double.random(in: 0 ..< 1) < emptyCartProb {
            for item in cartItems {
                _ = try? await ApiClient.deleteCartItem(item)
                try? await Task.sleep(nanoseconds: self.stepDelayNanos)
            }
            cartItems.removeAll()
            let rePid = productIds.randomElement()!
            cartItems.append(rePid)
            _ = try? await ApiClient.addToCart(rePid)
            try? await Task.sleep(nanoseconds: self.stepDelayNanos)
        }

        let flipProb: Double = switch self.activeVariant {
        case .control: 0.3
        case .variantA: 0.05
        case .variantB: 0.70
        }
        if Double.random(in: 0 ..< 1) < flipProb, !cartItems.isEmpty {
            let flippedPid = cartItems.randomElement()!
            _ = try? await ApiClient.deleteCartItem(flippedPid)
            try? await Task.sleep(nanoseconds: self.stepDelayNanos)
            _ = try? await ApiClient.addToCart(flippedPid, quantity: Int.random(in: 1 ... 5))
            try? await Task.sleep(nanoseconds: self.stepDelayNanos)
        }

        _ = try? await ApiClient.getCart()
        try? await Task.sleep(nanoseconds: self.stepDelayNanos)

        let cartAbandonProb: Double = switch self.activeVariant {
        case .control: 0.05
        case .variantA: 0.15
        case .variantB: 0.0
        }
        if Double.random(in: 0 ..< 1) < cartAbandonProb {
            ScreenLogger.logInfo("cart_abandoned", ["items_in_cart": String(cartItems.count), "variant": self.activeVariant.label])
            try? await Task.sleep(nanoseconds: 200_000_000)
            return
        }

        let checkoutPid = cartItems.last ?? pid

        // -- Step 5: Checkout -- A almost always guest (95%), B almost always signin (95%).
        let guestProb: Double = switch self.activeVariant {
        case .control: 0.5
        case .variantA: 0.95
        case .variantB: 0.05
        }
        let isGuest = Double.random(in: 0 ..< 1) < guestProb
        var session = ""
        if isGuest {
            await self.nav(router, .checkoutGuest(productId: checkoutPid))
            session = (try? await ApiClient.checkoutGuest().optString("checkout_session")) ?? ""
        } else {
            await self.nav(router, .checkoutSignIn(productId: checkoutPid))
            session = (try? await ApiClient.checkoutSignIn().optString("checkout_session")) ?? ""
        }

        let checkoutDropoutProb: Double = switch self.activeVariant {
        case .control: 0.0
        case .variantA: 0.35
        case .variantB: 0.05
        }
        if Double.random(in: 0 ..< 1) < checkoutDropoutProb {
            ScreenLogger.logInfo("checkout_abandoned", ["checkout_type": isGuest ? "guest" : "signin", "variant": self.activeVariant.label])
            try? await Task.sleep(nanoseconds: 200_000_000)
            return
        }

        // -- Step 6: Payment -- A uses digital (Apple Pay / PayPal / Android Pay), B uses card only.
        // 0=card, 1=apple_pay, 2=paypal, 3=android_pay
        let paymentChoice: Int = {
            switch self.activeVariant {
            case .control: return Int.random(in: 0 ... 3)
            case .variantA:
                let r = Double.random(in: 0 ..< 1)
                return r < 0.05 ? 0 : (r < 0.45 ? 1 : (r < 0.80 ? 2 : 3))
            case .variantB:
                let r = Double.random(in: 0 ..< 1)
                return r < 0.95 ? 0 : (r < 0.98 ? 1 : 2)
            }
        }()
        let paymentMethod = ["card", "apple_pay", "paypal", "android_pay"][paymentChoice]

        let failureProb: Double = if paymentMethod == "android_pay" {
            switch self.activeVariant {
            case .control: 0.30
            case .variantA: 0.20
            case .variantB: 0.0
            }
        } else {
            switch self.activeVariant {
            case .control: 0.15
            case .variantA: 0.35
            case .variantB: 0.05
            }
        }
        let willPaymentFail = Double.random(in: 0 ..< 1) < failureProb

        var orderId = ""
        switch paymentChoice {
        case 0:
            await self.nav(router, .paymentCard(checkoutSession: session))
            orderId = (try? await ApiClient.payCard(session).optString("order_id")) ?? ""
        case 1:
            await self.nav(router, .paymentApplePay(checkoutSession: session))
            orderId = (try? await ApiClient.payApplePay(session).optString("order_id")) ?? ""
        case 2:
            await self.nav(router, .paymentPayPal(checkoutSession: session))
            orderId = (try? await ApiClient.payPayPal(session).optString("order_id")) ?? ""
        default:
            await self.nav(router, .paymentAndroidPay(checkoutSession: session))
            orderId = (try? await ApiClient.payAndroidPay(session).optString("order_id")) ?? ""
        }

        if willPaymentFail {
            ScreenLogger.logError("payment_failed", ["payment_method": paymentMethod, "checkout_session": session, "variant": self.activeVariant.label])
            await self.nav(router, .paymentFailed(paymentMethod: paymentMethod, checkoutSession: session))
            try? await Task.sleep(nanoseconds: 200_000_000)

            if Double.random(in: 0 ..< 1) < 0.50 {
                let retryChoice = [0, 1, 2, 3].filter { $0 != paymentChoice }.randomElement()!
                let retryMethod: String
                var retryOrderId = ""
                switch retryChoice {
                case 0:
                    await self.nav(router, .paymentCard(checkoutSession: session))
                    retryOrderId = (try? await ApiClient.payCard(session).optString("order_id")) ?? ""
                    retryMethod = "card"
                case 1:
                    await self.nav(router, .paymentApplePay(checkoutSession: session))
                    retryOrderId = (try? await ApiClient.payApplePay(session).optString("order_id")) ?? ""
                    retryMethod = "apple_pay"
                case 2:
                    await self.nav(router, .paymentPayPal(checkoutSession: session))
                    retryOrderId = (try? await ApiClient.payPayPal(session).optString("order_id")) ?? ""
                    retryMethod = "paypal"
                default:
                    await self.nav(router, .paymentAndroidPay(checkoutSession: session))
                    retryOrderId = (try? await ApiClient.payAndroidPay(session).optString("order_id")) ?? ""
                    retryMethod = "android_pay"
                }
                ScreenLogger.logInfo("payment_retry", ["original_method": paymentMethod, "retry_method": retryMethod, "variant": self.activeVariant.label])

                self.setVariant(self.activeVariant)
                try? await Task.sleep(nanoseconds: 100_000_000)
                await self.nav(router, .confirmation(orderId: retryOrderId))
                Capture.Logger.shared?.logInfo(
                    "confirmation_reached",
                    fields: ["_screen_name": "Confirmation", "payment_retried": "true", "retry_method": retryMethod]
                )
                _ = try? await ApiClient.getConfirmation(retryOrderId)
                try? await Task.sleep(nanoseconds: 200_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            return
        }

        // -- Step 7: Confirmation --
        self.setVariant(self.activeVariant)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await self.nav(router, .confirmation(orderId: orderId))
        let checkoutFlow = switch self.activeVariant {
        case .control: "random"
        case .variantA: "guest"
        case .variantB: "signin"
        }
        Capture.Logger.shared?.logInfo("confirmation_reached", fields: ["_screen_name": "Confirmation", "checkout_flow": checkoutFlow])
        _ = try? await ApiClient.getConfirmation(orderId)
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}
