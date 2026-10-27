import Foundation

// Host-run checks for the Phase 6 app types (the pure parts; the trapping crash sites themselves
// cannot run in-process). Built and run by scripts/test-realism.sh: Foundation only, no app code
// beyond the files that script compiles.

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("FAIL  \(what)") }
}

// CartPricing
let lines = [
    CartPricing.Line(productId: "a", unitPrice: 10, quantity: 2),
    CartPricing.Line(productId: "b", unitPrice: 50, quantity: 1),
]
check(CartPricing.applyCoupon(lines, code: "SUMMER20") == 10, "coupon is 20% of the most valuable line")
check(CartPricing.applyCoupon(lines, code: "NOPE") == 0, "unknown coupon gives no discount")
check((try? CartPricing.applyCouponChecked(lines, code: "WELCOME10")) == 5, "checked path matches")
check((try? CartPricing.applyCouponChecked([], code: "SUMMER20")) == nil, "checked path throws on an empty cart")

// PromoBannerParser
let good = #"{"title":"Sale","discount_percent":20,"ends_at_ms":1793000000000}"#
check((try? PromoBannerParser.tryParse(good))?.discountPercent == 20, "valid banner parses")
check((try? PromoBannerParser.tryParse(PromoBannerParser.malformedPayload)) == nil, "malformed banner fails to decode")

// CartJson / ProductCatalog
ProductCatalog.learn(JSON.parse(string: #"{"products":[{"id":"p1","category":"audio"}]}"#))
ProductCatalog.learn(JSON.parse(string: #"{"id":"p2","category":"home"}"#))
let cart = JSON.parse(string: #"{"items":[{"product_id":"p1","unit_price":19.5,"quantity":2},{"product_id":"zz","unit_price":3,"quantity":1}],"total":42}"#)
let obj = (try? JSONSerialization.jsonObject(with: Data(CartJson.from(cart).utf8))) as? [String: Any]
let items = obj?["items"] as? [[String: Any]] ?? []
check(items.count == 2, "cart_json has both lines")
check(items.first?["category"] as? String == "audio", "category learned from a product list")
check(items.last?["category"] as? String == "unknown", "unseen product is unknown")
check(obj?["total"] as? Double == 42, "cart_json carries the total")
check(CartJson.lines(cart).map(\.quantity) == [2, 1], "lines() reads quantities")
check(ProductCatalog.categoryOf("p2") == "home", "single-product response is learned")

if failures > 0 { print("\(failures) realism check(s) failed"); exit(1) }
print("realism: all checks passed")
