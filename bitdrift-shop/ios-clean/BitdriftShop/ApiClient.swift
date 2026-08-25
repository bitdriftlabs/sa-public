import Foundation

/// HTTP client for the bitdrift-shop backend.
///
enum ApiClient {

    private static let port = 5173

    /// Host running the bitdrift-shop backend.
    ///
    /// Use the IPv4 loopback explicitly. The iOS Simulator shares the Mac's
    /// network stack, while many local FastAPI servers bind only to IPv4 — using
    /// `127.0.0.1` avoids URLSession resolving `localhost` to an unreachable
    /// IPv6 loopback first. Android uses its `10.0.2.2` emulator alias.
    ///
    /// **On a physical device this will not work**: `127.0.0.1` there means the
    /// phone, which has no route to your Mac's loopback. Set `SHOP_BACKEND_URL`
    /// in `.local.xcconfig` to your Mac's LAN address instead:
    ///
    ///     SHOP_BACKEND_URL = http:/$()/192.168.1.20:5173
    ///
    /// (`ipconfig getifaddr en0` prints it. The `$()` is required — `//` starts a
    /// comment in xcconfig.) A physical *Android* device has exactly this problem
    /// too; the emulator alias is what hides it.
    private static let host = "127.0.0.1"

    /// `SHOP_BACKEND_URL` wins when set; otherwise the per-environment default
    /// above. The override exists because the device default is a LAN IP, which
    /// changes with the network — editing source for that is a poor trade.
    private static let baseURL: String = {
        if let override = AppConfig.shopBackendURL {
            return override.trimmingCharacters(in: .init(charactersIn: "/")) + "/api"
        }
        return "http://\(host):\(port)/api"
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        // The demo backend rewrites its catalog on every request; a cached
        // response would flatten the traffic the demo exists to generate.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    struct HTTPError: LocalizedError {
        let status: Int
        let path: String
        var errorDescription: String? { "HTTP \(status) for \(path)" }
    }

    // MARK: - Verbs

    private static func request(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> JSON {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError(status: http.statusCode, path: path)
        }
        return JSON.parse(data)
    }

    private static func get(_ path: String) async throws -> JSON {
        try await request("GET", path)
    }

    private static func post(_ path: String, _ body: [String: Any] = [:]) async throws -> JSON {
        try await request("POST", path, body: body)
    }

    private static func delete(_ path: String) async throws -> JSON {
        try await request("DELETE", path)
    }

    // MARK: - Public API

    static func getWelcome() async throws -> JSON { try await get("/welcome") }

    static func getBrowse() async throws -> JSON { try await get("/browse") }

    static func search(_ query: String = "") async throws -> JSON {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get("/search?q=\(escaped)")
    }

    static func getFeatured() async throws -> JSON { try await get("/featured") }

    static func getCategories() async throws -> JSON { try await get("/categories") }

    static func getCategoryProducts(_ category: String) async throws -> JSON {
        let escaped = category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category
        return try await get("/categories/\(escaped)")
    }

    static func getProduct(_ productID: String) async throws -> JSON {
        try await get("/product/\(productID)")
    }

    static func getReviews(_ productID: String) async throws -> JSON {
        try await get("/product/\(productID)/reviews")
    }

    static func addToCart(_ productID: String, quantity: Int = 1) async throws -> JSON {
        try await post("/cart", ["product_id": productID, "quantity": quantity])
    }

    static func getCart() async throws -> JSON { try await get("/cart") }

    static func deleteCartItem(_ productID: String) async throws -> JSON {
        try await delete("/cart/\(productID)")
    }

    static func addToWishlist(_ productID: String) async throws -> JSON {
        try await post("/wishlist", ["product_id": productID])
    }

    static func checkoutGuest(email: String = "") async throws -> JSON {
        try await post("/checkout/guest", ["email": email])
    }

    static func checkoutSignIn(email: String = "") async throws -> JSON {
        try await post("/checkout/signin", ["email": email])
    }

    static func payCard(_ checkoutSession: String, cardLast4: String = "4242") async throws -> JSON {
        try await post("/payment/card", ["checkout_session": checkoutSession, "card_last4": cardLast4])
    }

    static func payApplePay(_ checkoutSession: String) async throws -> JSON {
        try await post("/payment/applepay", ["checkout_session": checkoutSession])
    }

    static func payPayPal(_ checkoutSession: String) async throws -> JSON {
        try await post("/payment/paypal", ["checkout_session": checkoutSession])
    }

    static func payAndroidPay(_ checkoutSession: String) async throws -> JSON {
        try await post("/payment/androidpay", ["checkout_session": checkoutSession])
    }

    static func getConfirmation(_ orderID: String) async throws -> JSON {
        try await get("/confirmation/\(orderID)")
    }

    /// Raw JSON array of products from `/browse`, used for recommendation scoring.
    static func getFullCatalogJSON() async throws -> String {
        try await getBrowse()["products"].serialized
    }

    // MARK: - Cardinality demo

    /// Generates a fresh random hex `session` on every call so each request
    /// produces a unique URL, creating unbounded cardinality in HTTP traffic
    /// analytics. Demonstrates why path templates exist.
    static func inventoryLookup(_ item: String) async throws -> JSON {
        let hex = "0123456789abcdef"
        let session = String((0..<16).compactMap { _ in hex.randomElement() })
        let escapedItem = item.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item

        // Every request lands as a unique URL (e.g.
        // /api/inventory/lookup/headphones/a3f92b1e4d7c0e85), which is what makes
        // this a cardinality demo.
        return try await get("/inventory/lookup/\(escapedItem)/\(session)")
    }
}
