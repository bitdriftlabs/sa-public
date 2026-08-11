import Foundation

/// Navigation destinations. Route strings are byte-identical to the Android
/// app's so both platforms emit the same `_screen_name` values and share the
/// `bd-shop-*` workflows and dashboards.
///
///     Step 1: Welcome, Advanced
///     Step 2: Browse, Search
///     Step 3: Featured, Categories, CategoryBrowse
///     Step 4: ProductDetail, Reviews
///     Step 5: Cart, Wishlist
///     Step 6: CheckoutGuest, CheckoutSignIn, Payment*, PaymentFailed
///     Step 7: Confirmation
enum Screen: Hashable {
    case welcome
    case advanced

    case browse
    case search

    case featured
    case categories
    case categoryBrowse(category: String)

    case productDetail(source: String, productID: String)
    case reviews(source: String, productID: String)

    case cart(productID: String)
    case wishlist(productID: String)

    case checkoutGuest(productID: String)
    case checkoutSignIn(productID: String)

    case paymentCard(checkoutSession: String)
    case paymentApplePay(checkoutSession: String)
    case paymentPayPal(checkoutSession: String)
    case paymentAndroidPay(checkoutSession: String)

    case paymentFailed(paymentMethod: String, checkoutSession: String)

    case confirmation(orderID: String)

    /// The route string, matching Android's `Screen.route`.
    var route: String {
        switch self {
        case .welcome: return "welcome"
        case .advanced: return "advanced"
        case .browse: return "browse"
        case .search: return "search"
        case .featured: return "featured"
        case .categories: return "categories"
        case .categoryBrowse(let category): return "categoryBrowse/\(esc(category))"
        case .productDetail(let source, let pid): return "productDetail/\(esc(source))/\(esc(pid))"
        case .reviews(let source, let pid): return "reviews/\(esc(source))/\(esc(pid))"
        case .cart(let pid): return "cart/\(esc(pid))"
        case .wishlist(let pid): return "wishlist/\(esc(pid))"
        case .checkoutGuest(let pid): return "checkoutGuest/\(esc(pid))"
        case .checkoutSignIn(let pid): return "checkoutSignIn/\(esc(pid))"
        case .paymentCard(let s): return "paymentCard/\(esc(s))"
        case .paymentApplePay(let s): return "paymentApplePay/\(esc(s))"
        case .paymentPayPal(let s): return "paymentPayPal/\(esc(s))"
        case .paymentAndroidPay(let s): return "paymentAndroidPay/\(esc(s))"
        case .paymentFailed(let m, let s): return "paymentFailed/\(esc(m))/\(esc(s))"
        case .confirmation(let oid): return "confirmation/\(esc(oid))"
        }
    }

    /// The name reported to `Logger.logScreenView`. Matches Android's
    /// `destinationToScreenName()` exactly — these values are what the Sankey
    /// and per-screen crash analytics group on.
    var screenName: String {
        switch self {
        case .welcome: return "Welcome"
        case .advanced: return "Advanced"
        case .browse: return "Browse"
        case .search: return "Search"
        case .featured: return "Featured"
        case .categories: return "Categories"
        case .categoryBrowse: return "CategoryBrowse"
        case .productDetail: return "ProductDetail"
        case .reviews: return "Reviews"
        case .cart: return "Cart"
        case .wishlist: return "Wishlist"
        case .checkoutGuest: return "CheckoutGuest"
        case .checkoutSignIn: return "CheckoutSignIn"
        case .paymentCard: return "PaymentCard"
        case .paymentApplePay: return "PaymentApplePay"
        case .paymentPayPal: return "PaymentPayPal"
        case .paymentAndroidPay: return "PaymentAndroidPay"
        case .paymentFailed: return "PaymentFailed"
        case .confirmation: return "Confirmation"
        }
    }

    /// A path segment may legitimately be empty (e.g. `cart/` when the cart is
    /// opened from the toolbar with no product) or contain a space (category
    /// names like "Home & Garden"), so segments are percent-encoded on the way
    /// in and decoded on the way out — the same job Android's NavType.StringType
    /// argument handling does.
    private func esc(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
