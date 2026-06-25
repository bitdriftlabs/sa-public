package ai.bitdrift.shop.shared

import kotlinx.coroutines.*

/**
 * Non-suspend wrapper functions for iOS that launch coroutines on the Kotlin side
 * and deliver results via callbacks. This avoids the ObjCExportCoroutines
 * suspend-to-async bridge which can crash with Ktor's dispatchers.
 */
private val iosScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

fun fetchWelcome(onSuccess: (WelcomeResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getWelcome()) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchBrowse(onSuccess: (BrowseResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getBrowse()) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchSearch(query: String, onSuccess: (SearchResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.search(query)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchFeatured(onSuccess: (FeaturedResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getFeatured()) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchCategories(onSuccess: (CategoriesResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getCategories()) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchCategoryProducts(category: String, onSuccess: (CategoryProductsResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getCategoryProducts(category)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchProduct(productId: String, onSuccess: (ProductDetailResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getProduct(productId)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchReviews(productId: String, onSuccess: (ReviewsResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getReviews(productId)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchAddToCart(productId: String, quantity: Int, onSuccess: (CartResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.addToCart(productId, quantity)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchCart(onSuccess: (CartResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getCart()) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchAddToWishlist(productId: String, onSuccess: (WishlistResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.addToWishlist(productId)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchCheckoutGuest(email: String, onSuccess: (CheckoutResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.checkoutGuest(email)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchCheckoutSignIn(email: String, onSuccess: (CheckoutResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.checkoutSignIn(email)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchPayCard(checkoutSession: String, cardLast4: String, onSuccess: (PaymentResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.payCard(checkoutSession, cardLast4)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchPayApplePay(checkoutSession: String, onSuccess: (PaymentResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.payApplePay(checkoutSession)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchPayPayPal(checkoutSession: String, onSuccess: (PaymentResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.payPayPal(checkoutSession)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchPayAndroidPay(checkoutSession: String, onSuccess: (PaymentResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.payAndroidPay(checkoutSession)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

fun fetchInventoryLookup(item: String, sessionId: String, onSuccess: (String) -> Unit, onError: (String) -> Unit) {
    iosScope.launch {
        try { onSuccess(ApiClient.inventoryLookup(item, sessionId).toString()) }
        catch (e: Exception) { onError(e.message ?: "error") }
    }
}

fun fetchConfirmation(orderId: String, onSuccess: (ConfirmationResponse) -> Unit, onError: (String) -> Unit) {
    iosScope.launch { try { onSuccess(ApiClient.getConfirmation(orderId)) } catch (e: Exception) { onError(e.message ?: "error") } }
}

