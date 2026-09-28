import Capture
import SwiftUI

// MARK: - Step 1: Welcome

struct WelcomeScreen: View {
    @EnvironmentObject var router: Router
    @ObservedObject var simulationManager: SimulationManager
    @State private var apiData: JSONObject?
    @State private var latestSdkVersion: String?
    @State private var deviceCode: String?

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let tagline = data.optString("tagline")
            let promoText = data.optJSONArray("promotions")?.first?.optString("title") ?? ""
            return "\(tagline)\n\(promoText)"
        } ?? "Experience different shopping journeys"

        ScreenContainer(
            screenName: "Welcome",
            title: apiData?.optString("store_name", "Welcome to ShopDemo") ?? "Welcome to ShopDemo",
            subtitle: subtitle,
            step: 1,
            systemIcon: "cart.fill",
            color: Color(red: 0x21 / 255, green: 0x96 / 255, blue: 0xF3 / 255),
            imageURL: "AppLogo",
            imageIsLogo: true,
            showSdkVersion: true,
            latestSdkVersion: latestSdkVersion
        ) {
            PrimaryButton(title: "Browse Products", systemIcon: "list.bullet", enabled: !simulationManager.isSimulating) {
                router.navigate(to: .browse)
            }
            SecondaryButton(title: "Search for Items", systemIcon: "magnifyingglass", enabled: !simulationManager.isSimulating) {
                router.navigate(to: .search)
            }
            Divider().padding(.vertical, 8)

            if simulationManager.isSimulating {
                Text("Simulation in progress...").font(.subheadline).foregroundStyle(.secondary).padding(16)
            } else {
                SimButton(title: "Sim 5", color: .orange) { simulationManager.simulate(5, router: router) }
                SimButton(title: "Sim 10", color: .orange) { simulationManager.simulate(10, router: router) }

                // Workshop 7 -- Device Identification & Debugging (basic sdk)
                Button(action: {
                    Capture.Logger.shared?.createTemporaryDeviceCode { result in
                        switch result {
                        case let .success(code):
                            deviceCode = code
                            UIPasteboard.general.string = code
                        case .failure:
                            deviceCode = "\u{26A0} needs_sdk_key"
                        }
                    }
                }) {
                    Text(deviceCode ?? "Device Code")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(deviceCode != nil ? Color(red: 0x21 / 255, green: 0x96 / 255, blue: 0xF3 / 255) : Color(.systemGray4))
            }
        }
        .task {
            apiData = try? await ApiClient.getWelcome()
            latestSdkVersion = await ApiClient.fetchLatestSdkVersion()
        }
    }
}

// MARK: - Step 2: Browse / Search

struct BrowseScreen: View {
    @EnvironmentObject var router: Router
    @ObservedObject var simulationManager: SimulationManager
    @State private var apiData: JSONObject?
    @State private var products: [JSONObject] = []
    @State private var catalogJson = "[]"

    var body: some View {
        let recommendations: [(JSONObject, Double)] = (simulationManager.slowModeEnabled && !products.isEmpty)
            ? RecommendationEngine.scoreProducts(catalogJson: catalogJson, referenceProductId: products[0].optString("id"))
            : []
        let subtitle = apiData.map { "Showing \(products.count) of \($0.optInt("total_products")) products" } ?? "Explore our product catalog"

        ScreenContainer(
            screenName: "Browse", title: "Browse", subtitle: subtitle, step: 2,
            systemIcon: "list.bullet", color: Color(red: 0x9C / 255, green: 0x27 / 255, blue: 0xB0 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            RecommendedSection(recommendations: recommendations) { router.navigate(to: .productDetail(source: "browse", productId: $0)) }
            ProductImageRow(products: products) { router.navigate(to: .productDetail(source: "browse", productId: $0)) }
            PrimaryButton(title: "View Featured", systemIcon: "star.fill") { router.navigate(to: .featuredProducts) }
            SecondaryButton(title: "Shop by Category", systemIcon: "list.bullet") { router.navigate(to: .categories) }
        }
        .task {
            if let data = try? await ApiClient.getBrowse() {
                apiData = data
                catalogJson = (try? await ApiClient.getFullCatalogJson()) ?? "[]"
                products = data.optJSONArray("products") ?? []
            }
        }
    }
}

struct SearchScreen: View {
    @EnvironmentObject var router: Router
    @State private var apiData: JSONObject?
    @State private var products: [JSONObject] = []

    var body: some View {
        let subtitle = apiData.map { "Found \($0.optJSONArray("products")?.count ?? 0) results for \"\($0.optString("query"))\"" } ?? "Find exactly what you're looking for"

        ScreenContainer(
            screenName: "Search", title: "Search", subtitle: subtitle, step: 2,
            systemIcon: "magnifyingglass", color: .orange,
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            ProductImageRow(products: products) { router.navigate(to: .productDetail(source: "search", productId: $0)) }
            PrimaryButton(title: "View Featured", systemIcon: "star.fill") { router.navigate(to: .featuredProducts) }
            SecondaryButton(title: "Shop by Category", systemIcon: "list.bullet") { router.navigate(to: .categories) }
        }
        .task {
            if let data = try? await ApiClient.search("headphones") {
                apiData = data
                products = data.optJSONArray("products") ?? []
            }
        }
    }
}

// MARK: - Step 3: Featured Products / Categories

struct FeaturedProductsScreen: View {
    @EnvironmentObject var router: Router
    @State private var apiData: JSONObject?
    @State private var firstProductId: String?
    @State private var products: [JSONObject] = []

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let banner = data.optJSONObject("banner")?.optString("text") ?? ""
            let count = data.optJSONArray("featured_products")?.count ?? 0
            return "\(banner) \u{2014} \(count) picks"
        } ?? "Our top picks for you"

        ScreenContainer(
            screenName: "Featured", title: "Featured Products", subtitle: subtitle, step: 3,
            systemIcon: "star.fill", color: Color(red: 0xFF / 255, green: 0xEB / 255, blue: 0x3B / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            ProductImageRow(products: products) { router.navigate(to: .productDetail(source: "featured", productId: $0)) }
            PrimaryButton(title: "View Product Details", systemIcon: "info.circle", enabled: firstProductId != nil) {
                if let id = firstProductId { router.navigate(to: .productDetail(source: "featured", productId: id)) }
            }
            SecondaryButton(title: "Read Reviews First", systemIcon: "envelope", enabled: firstProductId != nil) {
                if let id = firstProductId { router.navigate(to: .reviews(source: "featured", productId: id)) }
            }
        }
        .task {
            if let data = try? await ApiClient.getFeatured() {
                apiData = data
                let arr = data.optJSONArray("featured_products") ?? []
                products = arr
                firstProductId = arr.first?.optString("id")
            }
        }
    }
}

struct CategoriesScreen: View {
    @EnvironmentObject var router: Router
    @State private var categories: [JSONObject] = []

    var body: some View {
        let subtitle = categories.isEmpty ? "Browse by product type" : categories.map { $0.optString("name") }.joined(separator: ", ")

        ScreenContainer(
            screenName: "Categories", title: "Categories", subtitle: subtitle, step: 3,
            systemIcon: "list.bullet", color: Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            // No "View Product Details"/"Read Reviews First" shortcut here -- this screen only
            // ever fetches category names, never a specific product.
            CategoryRow(categories: categories) { router.navigate(to: .categoryBrowse(category: $0)) }
        }
        .task {
            categories = (try? await ApiClient.getCategories().optJSONArray("categories")) ?? []
        }
    }
}

// MARK: - Step 3b: Category Browse

struct CategoryBrowseScreen: View {
    @EnvironmentObject var router: Router
    let category: String?
    @State private var products: [JSONObject] = []
    @State private var firstProductId: String?

    private var cat: String { category ?? "Electronics" }

    var body: some View {
        let subtitle = products.isEmpty ? "Loading \(cat)..." : "\(products.count) products in \(cat)"

        ScreenContainer(
            screenName: "CategoryBrowse", title: cat, subtitle: subtitle, step: 3,
            systemIcon: "list.bullet", color: Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            ProductImageRow(products: products) { router.navigate(to: .productDetail(source: "categories", productId: $0)) }
            PrimaryButton(title: "View Product Details", systemIcon: "info.circle", enabled: firstProductId != nil) {
                if let id = firstProductId { router.navigate(to: .productDetail(source: "categories", productId: id)) }
            }
            SecondaryButton(title: "Read Reviews First", systemIcon: "envelope", enabled: firstProductId != nil) {
                if let id = firstProductId { router.navigate(to: .reviews(source: "categories", productId: id)) }
            }
        }
        .task(id: cat) {
            if let arr = try? await ApiClient.getCategoryProducts(cat).optJSONArray("products"), !arr.isEmpty {
                products = arr
                firstProductId = arr[0].optString("id")
            }
        }
    }
}

// MARK: - Step 4: Product Detail / Reviews

struct ProductDetailScreen: View {
    @EnvironmentObject var router: Router
    let source: String?
    let productId: String?
    @ObservedObject var simulationManager: SimulationManager
    @State private var apiData: JSONObject?
    @State private var catalogJson = "[]"

    var body: some View {
        let recommendations: [(JSONObject, Double)] = (simulationManager.slowModeEnabled && productId != nil)
            ? RecommendationEngine.scoreProducts(catalogJson: catalogJson, referenceProductId: productId!)
            : []
        let title = apiData?.optString("name", "Product Details") ?? "Product Details"
        let imageURL = apiData?.optStringArray("images")?.first
        let subtitle = apiData.map { data -> String in
            "\(data.optString("brand")) \u{2014} $\(String(format: "%.2f", data.optDouble("price"))) \u{2014} \(data.optInt("stock_count")) in stock"
        } ?? "Loading..."

        ScreenContainer(
            screenName: "ProductDetail", title: title, subtitle: subtitle, step: 4,
            systemIcon: "bell.fill", color: Color(red: 0x00 / 255, green: 0xBC / 255, blue: 0xD4 / 255),
            imageURL: imageURL,
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            RecommendedSection(recommendations: recommendations) { router.navigate(to: .productDetail(source: "browse", productId: $0)) }
            PrimaryButton(title: "Add to Cart", systemIcon: "plus", enabled: productId != nil) {
                guard let id = productId else { return }
                Capture.Logger.shared?.logInfo("add_to_cart", fields: ["product_id": id, "source_screen": source ?? "unknown"])
                router.navigate(to: .cart(productId: id))
            }
            SecondaryButton(title: "Save to Wishlist", systemIcon: "heart", enabled: productId != nil) {
                guard let id = productId else { return }
                Capture.Logger.shared?.logInfo("add_to_wishlist", fields: ["product_id": id, "source_screen": source ?? "unknown"])
                router.navigate(to: .wishlist(productId: id))
            }
        }
        .task(id: productId) {
            guard let pid = productId else { return }
            apiData = try? await ApiClient.getProduct(pid)
            if simulationManager.slowModeEnabled {
                catalogJson = (try? await ApiClient.getFullCatalogJson()) ?? "[]"
            }
        }
    }
}

struct ReviewsScreen: View {
    @EnvironmentObject var router: Router
    let source: String?
    let productId: String?
    @State private var apiData: JSONObject?

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let avg = data.optDouble("average_rating")
            let total = data.optInt("total_reviews")
            let topTitle = data.optJSONArray("reviews")?.first?.optString("title") ?? ""
            return "\(avg) stars from \(total) reviews\n\"\(topTitle)\""
        } ?? "Loading reviews..."

        ScreenContainer(
            screenName: "Reviews", title: "Customer Reviews", subtitle: subtitle, step: 4,
            systemIcon: "envelope.fill", color: Color(red: 0x00 / 255, green: 0xE5 / 255, blue: 0xBD / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Add to Cart", systemIcon: "plus", enabled: productId != nil) {
                guard let id = productId else { return }
                Capture.Logger.shared?.logInfo("add_to_cart", fields: ["product_id": id, "source_screen": source ?? "unknown"])
                router.navigate(to: .cart(productId: id))
            }
            SecondaryButton(title: "Save to Wishlist", systemIcon: "heart", enabled: productId != nil) {
                guard let id = productId else { return }
                Capture.Logger.shared?.logInfo("add_to_wishlist", fields: ["product_id": id, "source_screen": source ?? "unknown"])
                router.navigate(to: .wishlist(productId: id))
            }
        }
        .task(id: productId) {
            guard let pid = productId else { return }
            apiData = try? await ApiClient.getReviews(pid)
        }
    }
}

// MARK: - Step 5: Cart / Wishlist

struct CartScreen: View {
    @EnvironmentObject var router: Router
    let productId: String?
    @State private var apiData: JSONObject?

    private var pid: String { productId ?? "" }

    var body: some View {
        let items = apiData?.optJSONArray("items") ?? []
        let subtitle = apiData.map { data -> String in
            let count = items.count
            if count == 0 { return "Your cart is empty" }
            let total = data.optDouble("total")
            let tax = data.optDouble("tax")
            return "\(count) item\(count > 1 ? "s" : "") \u{2014} Total: $\(String(format: "%.2f", total)) (incl. $\(String(format: "%.2f", tax)) tax)"
        } ?? "Loading cart..."

        ScreenContainer(
            screenName: "Cart", title: "Shopping Cart", subtitle: subtitle, step: 5,
            systemIcon: "cart.fill", color: Color(red: 0x21 / 255, green: 0x96 / 255, blue: 0xF3 / 255),
            onBack: { router.popBackStack() }
        ) {
            if !items.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.optString("name")).fontWeight(.bold).lineLimit(1)
                                    Text("Qty: \(item.optInt("quantity", 1))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("$\(String(format: "%.2f", item.optDouble("line_total")))").fontWeight(.bold)
                                Button(action: {
                                    let itemProductId = item.optString("product_id")
                                    Capture.Logger.shared?.logInfo("cart_item_removed", fields: ["product_id": itemProductId])
                                    Task { apiData = try? await ApiClient.deleteCartItem(itemProductId) }
                                }) {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            PrimaryButton(title: "Checkout as Guest", systemIcon: "person.fill") {
                Capture.Logger.shared?.logInfo("checkout_started", fields: ["checkout_type": "guest"])
                router.navigate(to: .checkoutGuest(productId: pid))
            }
            SecondaryButton(title: "Sign In to Checkout", systemIcon: "lock.fill") {
                Capture.Logger.shared?.logInfo("checkout_started", fields: ["checkout_type": "signin"])
                router.navigate(to: .checkoutSignIn(productId: pid))
            }
            SecondaryButton(title: "Keep Shopping", systemIcon: "cart.fill") { router.popToWelcome() }
        }
        .task(id: pid) {
            do {
                apiData = pid.isEmpty ? try await ApiClient.getCart() : try await ApiClient.addToCart(pid)
            } catch {
                Capture.Logger.shared?.logError("cart_failed", fields: ["product_id": pid], error: error)
            }
        }
    }

}

struct WishlistScreen: View {
    @EnvironmentObject var router: Router
    let productId: String?
    @State private var apiData: JSONObject?

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let count = data.optInt("item_count")
            let firstName = data.optJSONArray("items")?.first?.optString("name") ?? ""
            return "\(count) items saved \u{2014} \(firstName)"
        } ?? "Loading wishlist..."

        ScreenContainer(
            screenName: "Wishlist", title: "Wishlist", subtitle: subtitle, step: 5,
            systemIcon: "heart.fill", color: Color(red: 0xE9 / 255, green: 0x1E / 255, blue: 0x63 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Checkout as Guest", systemIcon: "person.fill") {
                router.navigate(to: .checkoutGuest(productId: productId ?? ""))
            }
            SecondaryButton(title: "Sign In to Checkout", systemIcon: "lock.fill") {
                router.navigate(to: .checkoutSignIn(productId: productId ?? ""))
            }
        }
        .task(id: productId) {
            guard let pid = productId else { return }
            apiData = try? await ApiClient.addToWishlist(pid)
        }
    }
}

// MARK: - Step 6: Checkout Options

struct CheckoutGuestScreen: View {
    @EnvironmentObject var router: Router
    let productId: String?
    @State private var apiData: JSONObject?
    @State private var checkoutSession = ""

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let email = data.optString("email")
            let city = data.optJSONObject("shipping_address")?.optString("city") ?? ""
            let total = data.optJSONObject("order_preview")?.optDouble("total") ?? 0.0
            return "Shipping to \(city) \u{2014} $\(String(format: "%.2f", total))\n\(email)"
        } ?? "Loading checkout..."

        ScreenContainer(
            screenName: "CheckoutGuest", title: "Guest Checkout", subtitle: subtitle, step: 6,
            systemIcon: "person.fill", color: Color(red: 0x3F / 255, green: 0x51 / 255, blue: 0xB5 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Pay with Card", systemIcon: "checkmark", enabled: !checkoutSession.isEmpty) { router.navigate(to: .paymentCard(checkoutSession: checkoutSession)) }
            SecondaryButton(title: "Apple Pay", systemIcon: "phone.fill", enabled: !checkoutSession.isEmpty) { router.navigate(to: .paymentApplePay(checkoutSession: checkoutSession)) }
        }
        .task {
            do {
                let data = try await ApiClient.checkoutGuest()
                apiData = data
                checkoutSession = data.optString("checkout_session")
            } catch {
                Capture.Logger.shared?.logError("checkout_failed", fields: ["checkout_type": "guest"], error: error)
            }
        }
    }
}

struct CheckoutSignInScreen: View {
    @EnvironmentObject var router: Router
    let productId: String?
    @State private var apiData: JSONObject?
    @State private var checkoutSession = ""

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let user = data.optJSONObject("user")
            let name = user?.optString("name") ?? ""
            let email = user?.optString("email") ?? ""
            let points = user?.optInt("loyalty_points") ?? 0
            let total = data.optJSONObject("order_preview")?.optDouble("total") ?? 0.0
            return "Welcome back, \(name)\n\(email) \u{2014} \(points) pts \u{2014} $\(String(format: "%.2f", total))"
        } ?? "Loading checkout..."

        ScreenContainer(
            screenName: "CheckoutSignIn", title: "Member Checkout", subtitle: subtitle, step: 6,
            systemIcon: "lock.fill", color: Color(red: 0x00 / 255, green: 0x96 / 255, blue: 0x88 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Pay with Card", systemIcon: "checkmark", enabled: !checkoutSession.isEmpty) { router.navigate(to: .paymentCard(checkoutSession: checkoutSession)) }
            SecondaryButton(title: "PayPal", systemIcon: "paperplane.fill", enabled: !checkoutSession.isEmpty) { router.navigate(to: .paymentPayPal(checkoutSession: checkoutSession)) }
        }
        .task {
            do {
                let data = try await ApiClient.checkoutSignIn()
                apiData = data
                checkoutSession = data.optString("checkout_session")
                // Workshop 5 -- Global Fields: add user_id on sign-in so every subsequent log is tagged.
                let userId = data.optJSONObject("user")?.optString("id") ?? ""
                if !userId.isEmpty { Capture.Logger.shared?.addField(withKey: "user_id", value: userId) }
            } catch {
                Capture.Logger.shared?.logError("checkout_failed", fields: ["checkout_type": "signin"], error: error)
            }
        }
    }
}

// MARK: - Step 6b: Payment Methods (all lead to confirmation)

struct PaymentCardScreen: View {
    @EnvironmentObject var router: Router
    let checkoutSession: String?
    @State private var apiData: JSONObject?
    @State private var orderId = ""

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let txn = data.optString("transaction_id")
            return "\(data.optString("payment_method"))\n$\(String(format: "%.2f", data.optDouble("amount_charged"))) \u{2014} \(txn.prefix(20))\u{2026}"
        } ?? "Processing payment..."

        ScreenContainer(
            screenName: "PaymentCard", title: "Card Payment", subtitle: subtitle, step: 6,
            systemIcon: "checkmark", color: Color(red: 0x21 / 255, green: 0x96 / 255, blue: 0xF3 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Visa ending 4242", systemIcon: "checkmark", enabled: !orderId.isEmpty) {
                Capture.Logger.shared?.logInfo("payment_completed", fields: ["payment_method": "visa", "card_last4": "4242", "order_id": orderId])
                router.navigate(to: .confirmation(orderId: orderId))
            }
            SecondaryButton(title: "Mastercard ending 8888", systemIcon: "checkmark", enabled: !orderId.isEmpty) {
                Capture.Logger.shared?.logInfo("payment_completed", fields: ["payment_method": "mastercard", "card_last4": "8888", "order_id": orderId])
                router.navigate(to: .confirmation(orderId: orderId))
            }
            SecondaryButton(title: "Amex ending 1001", systemIcon: "checkmark", enabled: !orderId.isEmpty) {
                Capture.Logger.shared?.logInfo("payment_completed", fields: ["payment_method": "amex", "card_last4": "1001", "order_id": orderId])
                router.navigate(to: .confirmation(orderId: orderId))
            }
        }
        .task(id: checkoutSession) {
            guard let session = checkoutSession else { return }
            do {
                let data = try await ApiClient.payCard(session)
                apiData = data
                orderId = data.optString("order_id")
            } catch {
                Capture.Logger.shared?.logError("payment_failed", fields: ["payment_method": "card"], error: error)
            }
        }
    }
}

struct PaymentApplePayScreen: View {
    @EnvironmentObject var router: Router
    let checkoutSession: String?
    @State private var apiData: JSONObject?
    @State private var orderId = ""

    var body: some View {
        let subtitle = apiData.map { "Apple Pay \u{2014} $\(String(format: "%.2f", $0.optDouble("amount_charged")))\n\($0.optString("transaction_id").prefix(20))\u{2026}" } ?? "Authenticating..."
        ScreenContainer(
            screenName: "PaymentApplePay", title: "Apple Pay", subtitle: subtitle, step: 6,
            systemIcon: "phone.fill", color: .black,
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Complete Purchase", systemIcon: "checkmark.circle.fill", enabled: !orderId.isEmpty) { router.navigate(to: .confirmation(orderId: orderId)) }
        }
        .task(id: checkoutSession) {
            guard let session = checkoutSession else { return }
            do {
                let data = try await ApiClient.payApplePay(session)
                apiData = data
                orderId = data.optString("order_id")
            } catch {
                Capture.Logger.shared?.logError("payment_failed", fields: ["payment_method": "apple_pay"], error: error)
            }
        }
    }
}

struct PaymentPayPalScreen: View {
    @EnvironmentObject var router: Router
    let checkoutSession: String?
    @State private var apiData: JSONObject?
    @State private var orderId = ""

    var body: some View {
        let subtitle = apiData.map { "PayPal \u{2014} $\(String(format: "%.2f", $0.optDouble("amount_charged")))\nRef: \($0.optString("paypal_reference"))" } ?? "Connecting to PayPal..."
        ScreenContainer(
            screenName: "PaymentPayPal", title: "PayPal", subtitle: subtitle, step: 6,
            systemIcon: "paperplane.fill", color: Color(red: 0x21 / 255, green: 0x96 / 255, blue: 0xF3 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Complete Purchase", systemIcon: "checkmark.circle.fill", enabled: !orderId.isEmpty) { router.navigate(to: .confirmation(orderId: orderId)) }
        }
        .task(id: checkoutSession) {
            guard let session = checkoutSession else { return }
            do {
                let data = try await ApiClient.payPayPal(session)
                apiData = data
                orderId = data.optString("order_id")
            } catch {
                Capture.Logger.shared?.logError("payment_failed", fields: ["payment_method": "paypal"], error: error)
            }
        }
    }
}

struct PaymentAndroidPayScreen: View {
    @EnvironmentObject var router: Router
    let checkoutSession: String?
    @State private var apiData: JSONObject?
    @State private var orderId = ""

    var body: some View {
        let subtitle = apiData.map { "Android Pay \u{2014} $\(String(format: "%.2f", $0.optDouble("amount_charged")))\n\($0.optString("transaction_id").prefix(20))\u{2026}" } ?? "Authenticating..."
        ScreenContainer(
            screenName: "PaymentAndroidPay", title: "Android Pay", subtitle: subtitle, step: 6,
            systemIcon: "phone.fill", color: Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Complete Purchase", systemIcon: "checkmark.circle.fill", enabled: !orderId.isEmpty) { router.navigate(to: .confirmation(orderId: orderId)) }
        }
        .task(id: checkoutSession) {
            guard let session = checkoutSession else { return }
            do {
                let data = try await ApiClient.payAndroidPay(session)
                apiData = data
                orderId = data.optString("order_id")
            } catch {
                Capture.Logger.shared?.logError("payment_failed", fields: ["payment_method": "android_pay"], error: error)
            }
        }
    }
}

// MARK: - Payment Failed

struct PaymentFailedScreen: View {
    @EnvironmentObject var router: Router
    let paymentMethod: String?
    let checkoutSession: String?

    var body: some View {
        let method = paymentMethod ?? "unknown"
        let methodLabel: String = switch method {
        case "card": "Credit Card"
        case "apple_pay": "Apple Pay"
        case "paypal": "PayPal"
        case "android_pay": "Android Pay"
        default: method.prefix(1).uppercased() + method.dropFirst()
        }

        ScreenContainer(
            screenName: "PaymentFailed", title: "Payment Failed",
            subtitle: "Your \(methodLabel) payment could not be processed.\nPlease try again or use a different payment method.",
            step: 6, systemIcon: "exclamationmark.triangle.fill", color: Color(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            PrimaryButton(title: "Try Again", systemIcon: "arrow.clockwise") { router.popBackStack() }
        }
    }
}

// MARK: - Step 7: Confirmation (Final - All Paths Converge)

struct ConfirmationScreen: View {
    @EnvironmentObject var router: Router
    let orderId: String?
    @State private var apiData: JSONObject?

    private var oid: String { orderId ?? "" }

    var body: some View {
        let subtitle = apiData.map { data -> String in
            let txn = data.optString("transaction_id")
            let total = data.optDouble("total")
            let shipping = data.optJSONObject("shipping")
            let delivery = shipping?.optString("estimated_delivery") ?? ""
            let tracking = shipping?.optString("tracking_number") ?? ""
            return "Order \(data.optString("order_id", oid))\nTotal: $\(String(format: "%.2f", total))\nDelivery: \(delivery)\nTracking: \(tracking)\nTxn: \(txn.prefix(24))\u{2026}"
        } ?? "Order \(oid)\nThank you for your purchase!"

        ScreenContainer(
            screenName: "Confirmation", title: "Order Confirmed!", subtitle: subtitle, step: 7,
            systemIcon: "checkmark.circle.fill", color: Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255),
            onBack: { router.popBackStack() }, onCart: { router.navigate(to: .cart(productId: nil)) }
        ) {
            Button(action: {
                // Workshop 3 (Initialization & Session Strategy): start a new session when the
                // user begins a new shopping journey -- keeps each purchase flow in its own session.
                Capture.Logger.startNewSession()
                // Workshop 5 -- Global Fields: remove user_id when starting a new journey (logout).
                Capture.Logger.shared?.removeField(withKey: "user_id")
                router.popToWelcome()
            }) {
                Label("Start New Journey", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255))
        }
        .task(id: oid) {
            apiData = try? await ApiClient.getConfirmation(oid)
        }
    }
}
