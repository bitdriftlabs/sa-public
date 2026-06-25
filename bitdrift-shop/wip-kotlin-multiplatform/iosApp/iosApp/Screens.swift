import SwiftUI
import Shared
import Capture
import Foundation

// MARK: - API Helper

/// Calls a Kotlin suspend function via the callback-based launchAsync helper,
/// avoiding the ObjCExportCoroutines bridge that can crash with Ktor.
private func callApi<T: AnyObject>(_ block: @escaping (@escaping (T) -> Void, @escaping (String) -> Void) -> Void) async -> T? {
    await withCheckedContinuation { continuation in
        block(
            { result in continuation.resume(returning: result) },
            { _ in continuation.resume(returning: nil) }
        )
    }
}

// MARK: - Step 1: Welcome

struct WelcomeScreenView: View {
    @ObservedObject var simulationState: SimulationState
    @State private var storeName = "Welcome to Bitdrift Shop"
    @State private var subtitle = "Experience different shopping journeys"
    @State private var deviceCode: String? = nil
    @State private var supportLogEnabled = false

    var body: some View {
        ScreenContainer(
            screenName: "Welcome",
            title: storeName,
            subtitle: subtitle,
            step: 1,
            systemImage: "cart",
            color: .blue,
            logoImageName: "BitdriftLogo"
        ) {
            NavigationLink(value: ScreenRoute(route: "browse")) {
                HStack {
                    Image(systemName: "line.3.horizontal")
                    Text("Browse Products").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(simulationState.isSimulating)

            NavigationLink(value: ScreenRoute(route: "search")) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search for Items").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(simulationState.isSimulating)

            NavigationLink(value: ScreenRoute(route: "advanced")) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Advanced").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(simulationState.isSimulating)

            Divider().padding(.vertical, 8)

            if simulationState.isSimulating {
                Text("Simulation in progress...")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                HStack(spacing: 8) {
                    SimButtonView(title: "Sim 10", color: .orange) {
                        simulationState.simulate(runs: 10)
                    }
                    SimButtonView(title: "Sim 100", color: .red) {
                        simulationState.simulate(runs: 100)
                    }
                    SimButtonView(title: "∞ Sim", color: .purple) {
                        simulationState.infiniteSimulate()
                    }
                }
                HStack(spacing: 8) {
                    SimButtonView(title: "A/B Sim", color: Color(red: 0.38, green: 0.49, blue: 0.55)) {
                        simulationState.startAbSimulation()
                    }
                    SimButtonView(title: "Cardinality", color: Color(red: 0.47, green: 0.33, blue: 0.28)) {
                        simulationState.startCardinalitySimulation()
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: {
                    Logger.createTemporaryDeviceCode { result in
                        switch result {
                        case .success(let code):
                            deviceCode = code
                            UIPasteboard.general.string = code
                        case .failure:
                            deviceCode = "⚠ needs_sdk_key"
                        }
                    }
                }) {
                    Text(deviceCode ?? "Device Code")
                        .font(.system(size: deviceCode != nil ? 11 : 14, weight: .bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(deviceCode != nil ? Color(red: 0.13, green: 0.59, blue: 0.95) : Color(.systemGray5))
                .foregroundStyle(deviceCode != nil ? .white : .primary)

                Button(action: {
                    supportLogEnabled.toggle()
                    Logger.addField(withKey: "supportlog", value: supportLogEnabled.description)
                }) {
                    Text(supportLogEnabled ? "Support Log: ON" : "Support Log: OFF")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(supportLogEnabled ? Color(red: 0.30, green: 0.69, blue: 0.31) : Color(.systemGray5))
                .foregroundStyle(supportLogEnabled ? .white : .primary)
            }
            .padding(.top, 4)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchWelcome(onSuccess: s, onError: e) }) {
                storeName = data.storeName
                let promo = data.promotions.first?.title ?? ""
                subtitle = "\(data.tagline)\n\(promo)"
            }
        }
    }
}

// MARK: - Step 2: Browse / Search

struct BrowseScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var products: [ProductCardData] = []
    @State private var subtitle = "Explore our product catalog"

    var body: some View {
        ScreenContainer(
            screenName: "Browse", title: "Browse", subtitle: subtitle,
            step: 2, systemImage: "line.3.horizontal", color: .purple,
            onBack: { dismiss() }
        ) {
            ProductRowView(products: products) { pid in }
            NavigationLink(value: ScreenRoute(route: "featured")) {
                buttonContent("View Featured", systemImage: "star")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "categories")) {
                buttonContent("Shop by Category", systemImage: "list.bullet")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchBrowse(onSuccess: s, onError: e) }) {
                products = data.products.map { mapProduct($0) }
                subtitle = "Showing \(products.count) of \(data.totalProducts) products"
            }
        }
    }
}

struct SearchScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var products: [ProductCardData] = []
    @State private var subtitle = "Find exactly what you're looking for"

    var body: some View {
        ScreenContainer(
            screenName: "Search", title: "Search", subtitle: subtitle,
            step: 2, systemImage: "magnifyingglass", color: .orange,
            onBack: { dismiss() }
        ) {
            ProductRowView(products: products) { pid in }
            NavigationLink(value: ScreenRoute(route: "featured")) {
                buttonContent("View Featured", systemImage: "star")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "categories")) {
                buttonContent("Shop by Category", systemImage: "list.bullet")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchSearch(query: "headphones", onSuccess: s, onError: e) }) {
                products = data.products.map { mapProduct($0) }
                subtitle = "Found \(data.resultCount) results for \"\(data.query)\""
            }
        }
    }
}

// MARK: - Step 3: Featured / Categories

struct FeaturedProductsScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var products: [ProductCardData] = []
    @State private var subtitle = "Our top picks for you"
    @State private var firstPid = "prod_a1b2c3"

    var body: some View {
        ScreenContainer(
            screenName: "Featured", title: "Featured Products", subtitle: subtitle,
            step: 3, systemImage: "star", color: .yellow,
            onBack: { dismiss() }
        ) {
            ProductRowView(products: products) { pid in }
            NavigationLink(value: ScreenRoute(route: "productDetail/featured/\(firstPid)")) {
                buttonContent("View Product Details", systemImage: "info.circle")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "reviews/featured/\(firstPid)")) {
                buttonContent("Read Reviews First", systemImage: "envelope")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchFeatured(onSuccess: s, onError: e) }) {
                products = data.featuredProducts.map { mapProduct($0) }
                firstPid = products.first?.id ?? "prod_a1b2c3"
                let banner = data.banner?.text ?? ""
                subtitle = "\(banner) — \(products.count) picks"
            }
        }
    }
}

struct CategoriesScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [CategoryData] = []
    @State private var subtitle = "Browse by product type"

    var body: some View {
        ScreenContainer(
            screenName: "Categories", title: "Categories", subtitle: subtitle,
            step: 3, systemImage: "list.bullet", color: .green,
            onBack: { dismiss() }
        ) {
            CategoryRowView(categories: categories) { catName in }
            NavigationLink(value: ScreenRoute(route: "productDetail/categories/prod_a1b2c3")) {
                buttonContent("View Product Details", systemImage: "info.circle")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "reviews/categories/prod_a1b2c3")) {
                buttonContent("Read Reviews First", systemImage: "envelope")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchCategories(onSuccess: s, onError: e) }) {
                categories = data.categories.map { CategoryData(name: $0.name, productCount: Int($0.productCount)) }
                subtitle = categories.map(\.name).joined(separator: ", ")
            }
        }
    }
}

// MARK: - Step 3b: Category Browse

struct CategoryBrowseScreenView: View {
    let category: String
    @Environment(\.dismiss) private var dismiss
    @State private var products: [ProductCardData] = []
    @State private var subtitle = ""
    @State private var firstPid = "prod_a1b2c3"

    var body: some View {
        ScreenContainer(
            screenName: "CategoryBrowse", title: category,
            subtitle: subtitle.isEmpty ? "Loading \(category)..." : subtitle,
            step: 3, systemImage: "list.bullet", color: .green,
            onBack: { dismiss() }
        ) {
            ProductRowView(products: products) { pid in }
            NavigationLink(value: ScreenRoute(route: "productDetail/categories/\(firstPid)")) {
                buttonContent("View Product Details", systemImage: "info.circle")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "reviews/categories/\(firstPid)")) {
                buttonContent("Read Reviews First", systemImage: "envelope")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchCategoryProducts(category: category, onSuccess: s, onError: e) }) {
                products = data.products.map { mapProduct($0) }
                firstPid = products.first?.id ?? "prod_a1b2c3"
                subtitle = "\(products.count) products in \(category)"
            }
        }
    }
}

// MARK: - Step 4: Product Detail / Reviews

struct ProductDetailScreenView: View {
    let source: String
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Product Details"
    @State private var subtitle = "Loading..."
    @State private var imageUrl: String? = nil

    var body: some View {
        ScreenContainer(
            screenName: "ProductDetail", title: title, subtitle: subtitle,
            step: 4, systemImage: "tag", color: .cyan,
            imageUrl: imageUrl,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "cart/\(productId)")) {
                buttonContent("Add to Cart", systemImage: "plus")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("add_to_cart", fields: ["product_id": productId, "source": source])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "wishlist/\(productId)")) {
                buttonContent("Save to Wishlist", systemImage: "heart")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchProduct(productId: productId, onSuccess: s, onError: e) }) {
                title = data.name
                imageUrl = data.images.first as? String
                subtitle = "\(data.brand) — $\(String(format: "%.2f", data.price)) — \(data.stockCount) in stock"
            }
        }
    }
}

struct ReviewsScreenView: View {
    let source: String
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Loading reviews..."

    var body: some View {
        ScreenContainer(
            screenName: "Reviews", title: "Customer Reviews", subtitle: subtitle,
            step: 4, systemImage: "envelope", color: Color(red: 0, green: 0.9, blue: 0.74),
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "cart/\(productId)")) {
                buttonContent("Add to Cart", systemImage: "plus")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("add_to_cart", fields: ["product_id": productId, "source": source])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "wishlist/\(productId)")) {
                buttonContent("Save to Wishlist", systemImage: "heart")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchReviews(productId: productId, onSuccess: s, onError: e) }) {
                let topTitle = (data.reviews.first as? Shared.Review)?.title ?? ""
                subtitle = "\(data.averageRating) stars from \(data.totalReviews) reviews\n\"\(topTitle)\""
            }
        }
    }
}

// MARK: - Step 5: Cart / Wishlist

struct CartScreenView: View {
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Loading cart..."
    @State private var items: [CartItemData] = []

    var body: some View {
        ScreenContainer(
            screenName: "Cart", title: "Shopping Cart", subtitle: subtitle,
            step: 5, systemImage: "cart", color: .blue,
            onBack: { dismiss() }
        ) {
            if !items.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items, id: \.productId) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.subheadline.bold()).lineLimit(1)
                                    Text("Qty: \(item.quantity)").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "$%.2f", item.lineTotal)).font(.subheadline.bold())
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            NavigationLink(value: ScreenRoute(route: "checkoutGuest/\(productId)")) {
                buttonContent("Checkout as Guest", systemImage: "person")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("checkout_started", fields: ["type": "guest"])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "checkoutSignIn/\(productId)")) {
                buttonContent("Sign In to Checkout", systemImage: "lock")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("checkout_started", fields: ["type": "signin"])
            })
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            let data: Shared.CartResponse?
            if !productId.isEmpty {
                data = await callApi({ s, e in IosAsyncHelperKt.fetchAddToCart(productId: productId, quantity: 1, onSuccess: s, onError: e) })
            } else {
                data = await callApi({ s, e in IosAsyncHelperKt.fetchCart(onSuccess: s, onError: e) })
            }
            if let data = data {
                items = data.items.map { CartItemData(productId: $0.productId, name: $0.name, quantity: Int($0.quantity), lineTotal: $0.lineTotal) }
                let count = items.count
                if count == 0 {
                    subtitle = "Your cart is empty"
                } else {
                    subtitle = "\(count) item\(count > 1 ? "s" : "") — Total: $\(String(format: "%.2f", data.total)) (incl. $\(String(format: "%.2f", data.tax)) tax)"
                }
            }
        }
    }
}

struct WishlistScreenView: View {
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Loading wishlist..."

    var body: some View {
        ScreenContainer(
            screenName: "Wishlist", title: "Wishlist", subtitle: subtitle,
            step: 5, systemImage: "heart", color: .pink,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "checkoutGuest/\(productId)")) {
                buttonContent("Checkout as Guest", systemImage: "person")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("checkout_started", fields: ["type": "guest", "source": "wishlist"])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "checkoutSignIn/\(productId)")) {
                buttonContent("Sign In to Checkout", systemImage: "lock")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("checkout_started", fields: ["type": "signin", "source": "wishlist"])
            })
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchAddToWishlist(productId: productId, onSuccess: s, onError: e) }) {
                let firstName = (data.items.first as? Shared.WishlistItem)?.name ?? ""
                subtitle = "\(data.itemCount) items saved — \(firstName)"
            }
        }
    }
}

// MARK: - Step 6: Checkout

struct CheckoutGuestScreenView: View {
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Loading checkout..."
    @State private var checkoutSession = ""

    var body: some View {
        ScreenContainer(
            screenName: "CheckoutGuest", title: "Guest Checkout", subtitle: subtitle,
            step: 6, systemImage: "person", color: .indigo,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "paymentCard/\(checkoutSession)")) {
                buttonContent("Pay with Card", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "paymentApplePay/\(checkoutSession)")) {
                buttonContent("Apple Pay", systemImage: "iphone")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchCheckoutGuest(email: "", onSuccess: s, onError: e) }) {
                checkoutSession = data.checkoutSession
                let city = data.shippingAddress?.city ?? ""
                let total = data.orderPreview?.total ?? 0.0
                subtitle = "Shipping to \(city) — $\(String(format: "%.2f", total))\n\(data.email)"
            }
        }
    }
}

struct CheckoutSignInScreenView: View {
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Loading checkout..."
    @State private var checkoutSession = ""

    var body: some View {
        ScreenContainer(
            screenName: "CheckoutSignIn", title: "Member Checkout", subtitle: subtitle,
            step: 6, systemImage: "lock", color: .teal,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "paymentCard/\(checkoutSession)")) {
                buttonContent("Pay with Card", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "paymentPayPal/\(checkoutSession)")) {
                buttonContent("PayPal", systemImage: "paperplane")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchCheckoutSignIn(email: "", onSuccess: s, onError: e) }) {
                checkoutSession = data.checkoutSession
                let name = data.user?.name ?? ""
                let email = data.user?.email ?? ""
                let points = data.user?.loyaltyPoints ?? 0
                let total = data.orderPreview?.total ?? 0.0
                subtitle = "Welcome back, \(name)\n\(email) — \(points) pts — $\(String(format: "%.2f", total))"
            }
        }
    }
}

// MARK: - Step 6b: Payment

struct PaymentCardScreenView: View {
    let checkoutSession: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Processing payment..."
    @State private var orderId = ""

    var body: some View {
        ScreenContainer(
            screenName: "PaymentCard", title: "Card Payment", subtitle: subtitle,
            step: 6, systemImage: "checkmark", color: .blue,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "confirmation/\(orderId)")) {
                buttonContent("Visa ending 4242", systemImage: "checkmark")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("payment_completed", fields: ["method": "card", "card": "visa_4242", "order_id": orderId])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "confirmation/\(orderId)")) {
                buttonContent("Mastercard ending 8888", systemImage: "checkmark")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("payment_completed", fields: ["method": "card", "card": "mc_8888", "order_id": orderId])
            })
            .buttonStyle(.bordered).controlSize(.large)
            NavigationLink(value: ScreenRoute(route: "confirmation/\(orderId)")) {
                buttonContent("Amex ending 1001", systemImage: "checkmark")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("payment_completed", fields: ["method": "card", "card": "amex_1001", "order_id": orderId])
            })
            .buttonStyle(.bordered).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchPayCard(checkoutSession: checkoutSession, cardLast4: "4242", onSuccess: s, onError: e) }) {
                orderId = data.orderId
                let txn = String(data.transactionId.prefix(20))
                subtitle = "\(data.paymentMethod)\n$\(String(format: "%.2f", data.amountCharged)) — \(txn)…"
            }
        }
    }
}

struct PaymentApplePayScreenView: View {
    let checkoutSession: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Authenticating..."
    @State private var orderId = ""

    var body: some View {
        ScreenContainer(
            screenName: "PaymentApplePay", title: "Apple Pay", subtitle: subtitle,
            step: 6, systemImage: "iphone", color: .black,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "confirmation/\(orderId)")) {
                buttonContent("Complete Purchase", systemImage: "checkmark.circle")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("payment_completed", fields: ["method": "apple_pay", "order_id": orderId])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchPayApplePay(checkoutSession: checkoutSession, onSuccess: s, onError: e) }) {
                orderId = data.orderId
                let txn = String(data.transactionId.prefix(20))
                subtitle = "Apple Pay — $\(String(format: "%.2f", data.amountCharged))\n\(txn)…"
            }
        }
    }
}

struct PaymentPayPalScreenView: View {
    let checkoutSession: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Connecting to PayPal..."
    @State private var orderId = ""

    var body: some View {
        ScreenContainer(
            screenName: "PaymentPayPal", title: "PayPal", subtitle: subtitle,
            step: 6, systemImage: "paperplane", color: .blue,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "confirmation/\(orderId)")) {
                buttonContent("Complete Purchase", systemImage: "checkmark.circle")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("payment_completed", fields: ["method": "paypal", "order_id": orderId])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchPayPayPal(checkoutSession: checkoutSession, onSuccess: s, onError: e) }) {
                orderId = data.orderId
                subtitle = "PayPal — $\(String(format: "%.2f", data.amountCharged))\nRef: \(data.paypalReference)"
            }
        }
    }
}

// MARK: - Step 7: Confirmation

struct ConfirmationScreenView: View {
    let orderId: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle: String

    init(orderId: String) {
        self.orderId = orderId
        self._subtitle = State(initialValue: "Order \(orderId)\nThank you for your purchase!")
    }

    var body: some View {
        ScreenContainer(
            screenName: "Confirmation", title: "Order Confirmed!", subtitle: subtitle,
            step: 7, systemImage: "checkmark.circle", color: .green,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "welcome")) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Start New Journey").font(.headline)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchConfirmation(orderId: orderId, onSuccess: s, onError: e) }) {
                let delivery = data.shipping?.estimatedDelivery ?? ""
                let tracking = data.shipping?.trackingNumber ?? ""
                let txn = String(data.transactionId.prefix(24))
                subtitle = "Order \(data.orderId)\nTotal: $\(String(format: "%.2f", data.total))\nDelivery: \(delivery)\nTracking: \(tracking)\nTxn: \(txn)…"
            }
        }
    }
}

// MARK: - Button Content Helper

private func buttonContent(_ title: String, systemImage: String) -> some View {
    HStack {
        Image(systemName: systemImage)
        Text(title).font(.headline)
        Spacer()
        Image(systemName: "chevron.right")
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
}

// MARK: - Mapping Helpers

private func mapProduct(_ p: Shared.ProductCard) -> ProductCardData {
    ProductCardData(
        id: p.id,
        name: p.name,
        price: p.price,
        imageUrl: p.imageUrl,
        category: p.category,
        brand: p.brand
    )
}

// Cart item data model
struct CartItemData {
    let productId: String
    let name: String
    let quantity: Int
    let lineTotal: Double
}

// MARK: - New: Payment Android Pay

struct PaymentAndroidPayScreenView: View {
    let checkoutSession: String
    @Environment(\.dismiss) private var dismiss
    @State private var subtitle = "Authenticating with Google Pay..."
    @State private var orderId = ""

    var body: some View {
        ScreenContainer(
            screenName: "PaymentAndroidPay", title: "Google Pay", subtitle: subtitle,
            step: 6, systemImage: "iphone", color: Color(red: 0.26, green: 0.52, blue: 0.96),
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "confirmation/\(orderId)")) {
                buttonContent("Complete with Google Pay", systemImage: "checkmark.circle")
            }
            .simultaneousGesture(TapGesture().onEnded {
                ScreenLogger.logInfo("payment_completed", fields: ["method": "android_pay", "order_id": orderId])
            })
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .task {
            if let data = await callApi({ s, e in IosAsyncHelperKt.fetchPayAndroidPay(checkoutSession: checkoutSession, onSuccess: s, onError: e) }) {
                orderId = data.orderId
                let txn = String(data.transactionId.prefix(20))
                subtitle = "Google Pay — $\(String(format: "%.2f", data.amountCharged))\n\(txn)…"
            }
        }
    }
}

// MARK: - New: Payment Failed

struct PaymentFailedScreenView: View {
    let paymentMethod: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenContainer(
            screenName: "PaymentFailed", title: "Payment Failed",
            subtitle: "Your \(paymentMethod) payment could not be processed.\nPlease try a different method.",
            step: 6, systemImage: "exclamationmark.triangle", color: .red,
            onBack: { dismiss() }
        ) {
            NavigationLink(value: ScreenRoute(route: "paymentCard/")) {
                buttonContent("Try Card Instead", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)

            Button {
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "cart")
                    Text("Return to Cart").font(.headline)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }
}

// MARK: - New: Advanced

struct AdvancedScreenView: View {
    @EnvironmentObject var simulationState: SimulationState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenContainer(
            screenName: "Advanced", title: "Advanced",
            subtitle: "Simulation variant & chaos controls",
            step: 0, systemImage: "gearshape", color: Color(red: 0.38, green: 0.49, blue: 0.55),
            onBack: { dismiss() }
        ) {
            Text("Simulation Variant")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach([SimVariant.control, SimVariant.variantA, SimVariant.variantB], id: \.self) { variant in
                    let selected = simulationState.activeVariant == variant
                    Button {
                        simulationState.setVariant(variant)
                    } label: {
                        Text(variantLabel(variant))
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected ? .blue : Color(.systemGray5))
                    .foregroundStyle(selected ? .white : .primary)
                }
            }

            Divider().padding(.vertical, 4)
            Text("Chaos Injection")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            chaosButton(
                label: simulationState.crashLoopEnabled ? "Crash Loop: ON" : "Crash Loop: OFF",
                active: simulationState.crashLoopEnabled
            ) { simulationState.toggleCrashLoop() }

            chaosButton(
                label: simulationState.anrAEnabled ? "ANR Injection: ON" : "ANR Injection: OFF",
                active: simulationState.anrAEnabled
            ) { simulationState.toggleAnrA() }

            chaosButton(
                label: simulationState.forceQuitEnabled ? "Force Quit: ON" : "Force Quit: OFF",
                active: simulationState.forceQuitEnabled
            ) { simulationState.toggleForceQuit() }

            Divider().padding(.vertical, 4)

            Button {
                dismiss()
                simulationState.startAbSimulation()
            } label: {
                buttonContent("A/B Simulation (3×5 journeys)", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)

            Button {
                dismiss()
                simulationState.startCardinalitySimulation()
            } label: {
                buttonContent("Cardinality Simulation", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }

    @ViewBuilder
    private func chaosButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? .red : Color(.systemGray5))
        .foregroundStyle(active ? .white : .primary)
    }

    private func variantLabel(_ v: SimVariant) -> String {
        switch v {
        case .control: return "Control"
        case .variantA: return "Variant A"
        case .variantB: return "Variant B"
        default: return "?"
        }
    }
}
