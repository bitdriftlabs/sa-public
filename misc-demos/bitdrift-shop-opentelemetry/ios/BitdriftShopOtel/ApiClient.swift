import Foundation

/// Compatibility adapter that keeps the app's existing JSON contract while sourcing data from the
/// OpenTelemetry Demo frontend proxy. Direct port of `ApiClient.kt` — same endpoints, same
/// legacy-shape mapping, same persistence keys, so behavior (including the wishlist self-healing
/// logic) matches the Android app exactly.
///
/// Uses `URLSession.shared`, which is automatically instrumented once
/// `LoggerIntegrator.enableIntegrations([.urlSession()])` is called in `ShoppingDemoApp.swift` —
/// the iOS equivalent of Android's `automaticOkHttpInstrumentation = true`.
enum ApiClient {
    private static let host = AppConfig.otelDemoHost
    private static let port = AppConfig.otelDemoPort
    private static let baseURL = "http://\(host):\(port)/api"
    private static let imageBaseURL = "http://\(host):\(port)/images/products"
    private static let defaultCurrency = "USD"
    private static let taxRate = 0.08
    private static let userIdKey = "otel_demo_adapter.user_id"
    private static let wishlistKey = "otel_demo_adapter.wishlist_ids"

    /// Distinct from a generic error so callers that need to tell a definitive "not found" apart
    /// from other HTTP failures (5xx, etc.) can catch it specifically -- see `addToWishlist()`.
    struct HttpStatusError: Error {
        let code: Int
        let message: String
    }

    private static var prefs: UserDefaults { .standard }

    private static func currentUserId() -> String {
        if let existing = prefs.string(forKey: userIdKey) { return existing }
        let userId = "ios-\(UUID().uuidString)"
        prefs.set(userId, forKey: userIdKey)
        return userId
    }

    private static func checkoutKey(_ sessionId: String) -> String { "checkout_\(sessionId)" }
    private static func confirmationKey(_ orderId: String) -> String { "confirmation_\(orderId)" }

    private static func buildURL(_ path: String, _ queryParams: [String: String] = [:]) -> URL {
        var components = URLComponents(string: "\(baseURL)\(path)")!
        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private static func execute(_ request: URLRequest, allowHttpError: Bool = false) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200 ..< 300).contains(statusCode), !allowHttpError {
            throw HttpStatusError(code: statusCode, message: "HTTP \(statusCode): \(body)")
        }
        return body
    }

    private static func get(_ path: String, _ queryParams: [String: String] = [:]) async throws -> JSONObject {
        let body = try await execute(URLRequest(url: buildURL(path, queryParams)))
        return body.isEmpty ? JSONObject() : JSONObject(string: body)
    }

    private static func getArray(_ path: String, _ queryParams: [String: String] = [:]) async throws -> [JSONObject] {
        let body = try await execute(URLRequest(url: buildURL(path, queryParams)))
        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return array.map(JSONObject.init)
    }

    private static func post(_ path: String, _ bodyJson: JSONObject = JSONObject(), _ queryParams: [String: String] = [:]) async throws -> JSONObject {
        var request = URLRequest(url: buildURL(path, queryParams))
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyJson.toData()
        let body = try await execute(request)
        return body.isEmpty ? JSONObject() : JSONObject(string: body)
    }

    private static func delete(_ path: String, _ bodyJson: JSONObject? = nil, _ queryParams: [String: String] = [:]) async throws -> JSONObject {
        var request = URLRequest(url: buildURL(path, queryParams))
        request.httpMethod = "DELETE"
        if let bodyJson {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyJson.toData()
        }
        let body = try await execute(request)
        return body.isEmpty ? JSONObject() : JSONObject(string: body)
    }

    private static func requestInventoryLookup(_ path: String) async throws -> JSONObject {
        var components = URLComponents(string: "\(baseURL)\(path)")!
        let request = URLRequest(url: components.url!)
        let body = try await execute(request, allowHttpError: true)
        _ = components // silence unused-var warning if path has no query needs
        return JSONObject()
            .put("path", path)
            .put("status", body.isEmpty ? "empty" : "ok")
    }

    private static func readStoredJson(_ key: String) -> JSONObject? {
        guard let string = prefs.string(forKey: key) else { return nil }
        return JSONObject(string: string)
    }

    private static func writeStoredJson(_ key: String, _ value: JSONObject) {
        prefs.set(String(data: value.toData(), encoding: .utf8), forKey: key)
    }

    private static func imageURL(_ picture: String) -> String { "\(imageBaseURL)/\(picture)" }

    private static func formatCategory(_ raw: String) -> String {
        let tokens = raw.components(separatedBy: CharacterSet(charactersIn: "_ -")).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "Products" }
        return tokens
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func moneyToDouble(_ money: JSONObject?) -> Double {
        guard let money else { return 0.0 }
        let units = Double(money.optLong("units"))
        let nanos = Double(money.optLong("nanos")) / 1_000_000_000.0
        return units + nanos
    }

    private static func cents(_ value: Double) -> Double { (value * 100.0).rounded() / 100.0 }

    private static func productToLegacy(_ product: JSONObject) -> JSONObject {
        let picture = product.optString("picture")
        let categories = product.optStringArray("categories") ?? []
        let primaryCategory = formatCategory(categories.first ?? "Products")
        let price = cents(moneyToDouble(product.optJSONObject("priceUsd")))
        let description = product.optString("description", product.optString("name"))

        return JSONObject()
            .put("id", product.optString("id"))
            .put("name", product.optString("name", "Unnamed Product"))
            .put("description", description)
            .put("brand", "OpenTelemetry Demo")
            .put("category", primaryCategory)
            .put("price", price)
            .put("image_url", imageURL(picture))
            .put("images", [imageURL(picture)])
            .put("picture", picture)
    }

    private static func listOtelProducts() async throws -> [JSONObject] {
        try await getArray("/products", ["currencyCode": defaultCurrency])
    }

    private static func getOtelProduct(_ productId: String) async throws -> JSONObject {
        try await get("/products/\(productId)", ["currencyCode": defaultCurrency])
    }

    private static func listLegacyProducts() async throws -> [JSONObject] {
        try await listOtelProducts().map(productToLegacy)
    }

    private static func currentWishlistIds() -> Set<String> {
        Set(prefs.stringArray(forKey: wishlistKey) ?? [])
    }

    private static func memberProfile() -> JSONObject {
        JSONObject()
            .put("id", currentUserId())
            .put("name", "Taylor Shopper")
            .put("email", "taylor.shopper@example.com")
            .put("loyalty_points", 240)
    }

    private static func guestEmail() -> String {
        "guest.\(currentUserId().suffix(8))@example.com"
    }

    private static func shippingAddress() -> JSONObject {
        JSONObject()
            .put("street", "123 Telescope Way")
            .put("city", "Mountain View")
            .put("state", "CA")
            .put("country", "US")
            .put("zip", "94043")
    }

    private static func shippingAddressForOtel() -> JSONObject {
        JSONObject()
            .put("streetAddress", "123 Telescope Way")
            .put("city", "Mountain View")
            .put("state", "CA")
            .put("country", "US")
            .put("zipCode", "94043")
    }

    private static func creditCardForOtel() -> JSONObject {
        JSONObject()
            .put("creditCardNumber", "4242424242424242")
            .put("creditCardCvv", 123)
            .put("creditCardExpirationYear", 2030)
            .put("creditCardExpirationMonth", 12)
    }

    private static func cartFromOtel() async throws -> JSONObject {
        let cart = try await get("/cart", ["sessionId": currentUserId(), "currencyCode": defaultCurrency])

        let items = cart.optJSONArray("items") ?? []
        var mappedItems: [JSONObject] = []
        var subtotal = 0.0

        for item in items {
            guard let product = item.optJSONObject("product") else { continue }
            let productId = item.optString("productId")
            let quantity = item.optInt("quantity")
            let unitPrice = cents(moneyToDouble(product.optJSONObject("priceUsd")))
            let lineTotal = cents(unitPrice * Double(quantity))
            subtotal += lineTotal

            mappedItems.append(
                JSONObject()
                    .put("product_id", productId)
                    .put("name", product.optString("name"))
                    .put("quantity", quantity)
                    .put("unit_price", unitPrice)
                    .put("line_total", lineTotal)
                    .put("image_url", imageURL(product.optString("picture")))
            )
        }

        let tax = cents(subtotal * taxRate)
        let total = cents(subtotal + tax)

        return JSONObject()
            .put("user_id", cart.optString("userId", currentUserId()))
            .put("subtotal", cents(subtotal))
            .put("tax", tax)
            .put("total", total)
            .put("items", mappedItems)
    }

    private static func orderPreview(fromCart cart: JSONObject) -> JSONObject {
        JSONObject()
            .put("subtotal", cart.optDouble("subtotal"))
            .put("tax", cart.optDouble("tax"))
            .put("total", cart.optDouble("total"))
            .put("item_count", cart.optJSONArray("items")?.count ?? 0)
    }

    private static func createCheckout(mode: String) async throws -> JSONObject {
        let cart = try await cartFromOtel()
        let sessionId = UUID().uuidString
        let email = mode == "signin" ? memberProfile().optString("email") : guestEmail()
        let snapshot = JSONObject()
            .put("checkout_session", sessionId)
            .put("user_id", currentUserId())
            .put("email", email)
            .put("mode", mode)
            .put("shipping_address", shippingAddress())
            .put("order_preview", orderPreview(fromCart: cart))

        if mode == "signin" {
            snapshot.put("user", memberProfile())
        }

        writeStoredJson(checkoutKey(sessionId), snapshot)
        return snapshot
    }

    private static func total(fromCheckout order: JSONObject) -> Double {
        let items = order.optJSONArray("items") ?? []
        var itemsTotal = 0.0
        for item in items {
            itemsTotal += moneyToDouble(item.optJSONObject("cost"))
        }
        return cents(itemsTotal + moneyToDouble(order.optJSONObject("shippingCost")))
    }

    private static func flattenOrderItems(_ items: [JSONObject]) -> [JSONObject] {
        items.compactMap { entry -> JSONObject? in
            guard let item = entry.optJSONObject("item"), let product = item.optJSONObject("product") else { return nil }
            let quantity = item.optInt("quantity")
            let unitPrice = cents(moneyToDouble(entry.optJSONObject("cost")) / Double(max(quantity, 1)))
            return JSONObject()
                .put("product_id", item.optString("productId"))
                .put("name", product.optString("name"))
                .put("quantity", quantity)
                .put("unit_price", unitPrice)
                .put("line_total", cents(moneyToDouble(entry.optJSONObject("cost"))))
                .put("image_url", imageURL(product.optString("picture")))
        }
    }

    private static func buildConfirmation(order: JSONObject, paymentMethod: String, transactionId: String, email: String) -> JSONObject {
        let trackingId = order.optString("shippingTrackingId")
        let delivery = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 5, to: Date())!)
            .prefix(10) // yyyy-MM-dd, matching Kotlin's DateTimeFormatter.ISO_DATE
        return JSONObject()
            .put("order_id", order.optString("orderId"))
            .put("transaction_id", transactionId)
            .put("payment_method", paymentMethod)
            .put("email", email)
            .put("total", total(fromCheckout: order))
            .put("items", flattenOrderItems(order.optJSONArray("items") ?? []))
            .put("shipping_address", shippingAddress())
            .put(
                "shipping",
                JSONObject()
                    .put("estimated_delivery", String(delivery))
                    .put("tracking_number", trackingId)
            )
    }

    private static func pay(checkoutSession: String, paymentMethod: String, extraFields: JSONObject = JSONObject()) async throws -> JSONObject {
        guard let snapshot = readStoredJson(checkoutKey(checkoutSession)) else {
            throw HttpStatusError(code: 0, message: "Unknown checkout session: \(checkoutSession)")
        }

        let order = try await post(
            "/checkout",
            JSONObject()
                .put("userId", snapshot.optString("user_id"))
                .put("userCurrency", defaultCurrency)
                .put("address", shippingAddressForOtel())
                .put("email", snapshot.optString("email"))
                .put("creditCard", creditCardForOtel()),
            ["currencyCode": defaultCurrency]
        )

        let orderId = order.optString("orderId")
        let transactionId = "txn-\(UUID().uuidString)"
        let confirmation = buildConfirmation(order: order, paymentMethod: paymentMethod, transactionId: transactionId, email: snapshot.optString("email"))
        writeStoredJson(confirmationKey(orderId), confirmation)

        let payment = JSONObject()
            .put("order_id", orderId)
            .put("transaction_id", transactionId)
            .put("payment_method", paymentMethod)
            .put("amount_charged", total(fromCheckout: order))

        for key in extraFields.keys {
            payment.put(key, extraFields.storage[key])
        }
        return payment
    }

    // MARK: - Public API (all async, mirroring Kotlin's suspend fun)

    static func fetchLatestSdkVersion() async -> String? {
        do {
            let request = URLRequest(url: URL(string: "https://api.github.com/repos/bitdriftlabs/capture-sdk/releases/latest")!)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let json = try JSONObject(data: data)
            let tag = json.optString("tag_name")
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return version.isEmpty ? nil : version
        } catch {
            return nil
        }
    }

    static func getWelcome() async throws -> JSONObject {
        JSONObject()
            .put("store_name", "Telescope Store")
            .put("tagline", "Explore the OpenTelemetry Demo catalog with your existing Bitdrift instrumentation")
            .put("promotions", [JSONObject().put("title", "Now backed by the OpenTelemetry Demo services")])
    }

    static func getBrowse() async throws -> JSONObject {
        let products = try await listLegacyProducts()
        return JSONObject().put("products", products).put("total_products", products.count)
    }

    static func search(_ query: String) async throws -> JSONObject {
        let lowered = query.trimmingCharacters(in: .whitespaces).lowercased()
        let products = try await listLegacyProducts()
        let filtered = products.filter { product in
            let haystack = [
                product.optString("name"), product.optString("description"), product.optString("category"),
            ].joined(separator: " ").lowercased()
            return lowered.isEmpty || haystack.contains(lowered)
        }
        return JSONObject().put("query", query).put("products", filtered)
    }

    static func getFeatured() async throws -> JSONObject {
        let products = try await listLegacyProducts()
        let featured = Array(products.prefix(4))
        return JSONObject()
            .put("banner", JSONObject().put("text", "Featured picks from the Telescope Store"))
            .put("featured_products", featured)
    }

    static func getCategories() async throws -> JSONObject {
        let products = try await listLegacyProducts()
        var seen = Set<String>()
        var categories: [JSONObject] = []
        for product in products {
            let name = product.optString("category", "Products")
            if seen.insert(name).inserted {
                categories.append(JSONObject().put("name", name))
            }
        }
        return JSONObject().put("categories", categories)
    }

    static func getCategoryProducts(_ category: String) async throws -> JSONObject {
        let products = try await listLegacyProducts()
        let filtered = products.filter { $0.optString("category").caseInsensitiveCompare(category) == .orderedSame }
        return JSONObject().put("category", category).put("products", filtered)
    }

    static func getProduct(_ productId: String) async throws -> JSONObject {
        productToLegacy(try await getOtelProduct(productId))
    }

    static func getReviews(_ productId: String) async throws -> JSONObject {
        let reviews = try await getArray("/product-reviews/\(productId)")
        let mapped = reviews.map { review -> JSONObject in
            let author = review.optString("username", "Anonymous")
            return JSONObject()
                .put("title", "Review by \(author)")
                .put("author", author)
                .put("rating", Int(review.optString("score", "0")) ?? 0)
                .put("content", review.optString("description"))
        }
        return JSONObject().put("reviews", mapped)
    }

    static func addToCart(_ productId: String, quantity: Int = 1) async throws -> JSONObject {
        _ = try await post(
            "/cart",
            JSONObject().put("userId", currentUserId()).put("item", JSONObject().put("productId", productId).put("quantity", quantity)),
            ["currencyCode": defaultCurrency]
        )
        return try await cartFromOtel()
    }

    static func getCart() async throws -> JSONObject {
        try await cartFromOtel()
    }

    static func deleteCartItem(_ productId: String) async throws -> JSONObject {
        let cart = try await get("/cart", ["sessionId": currentUserId(), "currencyCode": defaultCurrency])
        let items = cart.optJSONArray("items") ?? []
        _ = try await delete("/cart", JSONObject().put("userId", currentUserId()))
        for item in items where item.optString("productId") != productId {
            _ = try await post(
                "/cart",
                JSONObject().put("userId", currentUserId()).put("item", JSONObject().put("productId", item.optString("productId")).put("quantity", item.optInt("quantity", 1))),
                ["currencyCode": defaultCurrency]
            )
        }
        return try await cartFromOtel()
    }

    static func addToWishlist(_ productId: String) async throws -> JSONObject {
        var wishlistIds = currentWishlistIds()
        wishlistIds.insert(productId)

        // Wishlist IDs persist in UserDefaults across app runs/reinstalls. Fetch each one
        // independently rather than letting a single bad ID (stale/invalid, e.g. from an earlier
        // bug) throw and abort the whole call -- that both loses the other items and, since it's
        // swallowed by the caller's try/catch, silently never self-heals. Only a definitive 404
        // means the ID itself is invalid; a timeout, DNS failure, or 5xx is transient and must
        // not permanently drop the ID from the persisted set.
        var items: [JSONObject] = []
        var invalidIds: Set<String> = []
        for itemId in wishlistIds {
            do {
                items.append(productToLegacy(try await getOtelProduct(itemId)))
            } catch let error as HttpStatusError {
                if error.code == 404 { invalidIds.insert(itemId) }
            } catch {
                // Network-level failure (timeout, DNS, etc.) -- transient, retain the ID.
            }
        }
        if !invalidIds.isEmpty {
            wishlistIds.subtract(invalidIds)
        }
        prefs.set(Array(wishlistIds), forKey: wishlistKey)

        return JSONObject().put("item_count", items.count).put("items", items)
    }

    static func checkoutGuest(_ email: String = "") async throws -> JSONObject {
        let snapshot = try await createCheckout(mode: "guest")
        if !email.isEmpty {
            snapshot.put("email", email)
            writeStoredJson(checkoutKey(snapshot.optString("checkout_session")), snapshot)
        }
        return snapshot
    }

    static func checkoutSignIn(_ email: String = "") async throws -> JSONObject {
        let snapshot = try await createCheckout(mode: "signin")
        if !email.isEmpty {
            let user = snapshot.optJSONObject("user") ?? JSONObject()
            user.put("email", email)
            snapshot.put("email", email)
            snapshot.put("user", user)
            writeStoredJson(checkoutKey(snapshot.optString("checkout_session")), snapshot)
        }
        return snapshot
    }

    static func payCard(_ checkoutSession: String, cardLast4: String = "4242") async throws -> JSONObject {
        try await pay(checkoutSession: checkoutSession, paymentMethod: "Card", extraFields: JSONObject().put("card_last4", cardLast4))
    }

    static func payApplePay(_ checkoutSession: String) async throws -> JSONObject {
        try await pay(checkoutSession: checkoutSession, paymentMethod: "Apple Pay")
    }

    static func payPayPal(_ checkoutSession: String) async throws -> JSONObject {
        let ref = "PP-\(UUID().uuidString.prefix(10).uppercased())"
        return try await pay(checkoutSession: checkoutSession, paymentMethod: "PayPal", extraFields: JSONObject().put("paypal_reference", ref))
    }

    static func payAndroidPay(_ checkoutSession: String) async throws -> JSONObject {
        try await pay(checkoutSession: checkoutSession, paymentMethod: "Android Pay")
    }

    static func getConfirmation(_ orderId: String) async throws -> JSONObject {
        readStoredJson(confirmationKey(orderId)) ?? JSONObject().put("order_id", orderId)
    }

    static func getFullCatalogJson() async throws -> String {
        let result = try await getBrowse()
        guard let products = result.optJSONArray("products") else { return "[]" }
        return String(data: (try? JSONSerialization.data(withJSONObject: products.map(\.storage))) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    // Cardinality demo: hammers /api/inventory/lookup/{item}/{session} with a fresh random
    // session path segment on every request, flooding the Bitdrift dashboard with
    // infinite-cardinality URLs.
    static func inventoryLookup(_ item: String) async throws -> JSONObject {
        let hex = Array("0123456789abcdef")
        let session = String((0 ..< 16).map { _ in hex.randomElement()! })
        return try await requestInventoryLookup("/inventory/lookup/\(item)/\(session)")
    }
}
