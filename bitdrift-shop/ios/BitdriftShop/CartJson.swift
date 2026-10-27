import Foundation

/// Remembers each product's category from the catalog responses the app has already seen
/// (browse, search, featured, category, product), because the backend's cart lines only carry a
/// product id. Used to put a category on every line of `cart_json`.
enum ProductCatalog {
    private static let lock = NSLock()
    private static var categories: [String: String] = [:]

    /// Learns from any response shaped like a product list (`products[]`) or a single product.
    static func learn(_ response: JSON?) {
        guard let response, response.exists else { return }
        let list = response["products"].exists ? response["products"].array : response["featured_products"].array
        if !list.isEmpty { list.forEach(learnOne) } else { learnOne(response) }
    }

    private static func learnOne(_ p: JSON) {
        let id = p.str("id"), category = p.str("category")
        guard !id.isEmpty, !category.isEmpty else { return }
        lock.lock(); categories[id] = category; lock.unlock()
    }

    static func categoryOf(_ productID: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return categories[productID] ?? "unknown"
    }
}

/// `cart_json`: the cart as one JSON string field, {"items":[{"id","category","price","quantity"}],"total"}.
/// A workflow metric uses JSON paths on it to chart revenue by category (`items[].category`,
/// `items[].price`) without a separate field per line.
enum CartJson {
    static func from(_ cart: JSON?) -> String {
        let items: [[String: Any]] = (cart?["items"].array ?? []).map { l in
            let id = l.str("product_id")
            return [
                "id": id,
                "category": ProductCatalog.categoryOf(id),
                "price": l.num("unit_price"),
                "quantity": l.int("quantity", 1),
            ]
        }
        let obj: [String: Any] = ["items": items, "total": cart?.num("total") ?? 0]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func lines(_ cart: JSON?) -> [CartPricing.Line] {
        (cart?["items"].array ?? []).map {
            CartPricing.Line(productId: $0.str("product_id"), unitPrice: $0.num("unit_price"), quantity: $0.int("quantity", 1))
        }
    }
}
