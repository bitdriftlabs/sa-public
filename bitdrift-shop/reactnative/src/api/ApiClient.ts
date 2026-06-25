import type {
  BrowseResponse,
  CartResponse,
  CategoriesResponse,
  CategoryProductsResponse,
  CheckoutResponse,
  ConfirmationResponse,
  FeaturedResponse,
  PaymentResponse,
  ProductDetailResponse,
  ReviewsResponse,
  SearchResponse,
  WelcomeResponse,
  WishlistResponse,
} from '../types/models';
import {ScreenLogger} from '../utils/logger';
import {BACKEND_BASE_URL as BASE_URL} from '../config';

// Workshop 4b — HTTP Instrumentation
// Every API call is timed and logged with path, method, status, and duration so
// the bitdrift dashboard can surface slow or failing endpoints in session timelines.
async function request<T>(path: string, method: 'GET' | 'POST' | 'DELETE' = 'GET', body?: unknown): Promise<T> {
  const startMs = Date.now();
  let status = 0;
  try {
    const response = await fetch(`${BASE_URL}${path}`, {
      method,
      headers: {Accept: 'application/json', 'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined,
    });

    status = response.status;
    const durationMs = Date.now() - startMs;

    const text = await response.text();
    const data = text ? (JSON.parse(text) as T) : ({} as T);

    if (response.ok) {
      ScreenLogger.logDebug('api_response', {
        method,
        path,
        status: String(status),
        duration_ms: String(durationMs),
      });
    } else {
      ScreenLogger.logWarning('api_response_error', {
        method,
        path,
        status: String(status),
        duration_ms: String(durationMs),
      });
    }

    return data;
  } catch (err) {
    const durationMs = Date.now() - startMs;
    ScreenLogger.logError('api_request_failed', {
      method,
      path,
      error: err instanceof Error ? err.message : String(err),
      duration_ms: String(durationMs),
    });
    throw err;
  }
}

export const ApiClient = {
  baseUrl: BASE_URL,

  getWelcome: () => request<WelcomeResponse>('/welcome'),
  getBrowse: () => request<BrowseResponse>('/browse'),
  search: (query = '') => request<SearchResponse>(`/search?q=${encodeURIComponent(query)}`),
  getFeatured: () => request<FeaturedResponse>('/featured'),
  getCategories: () => request<CategoriesResponse>('/categories'),
  getCategoryProducts: (category: string) =>
    request<CategoryProductsResponse>(`/categories/${encodeURIComponent(category)}`),
  getProduct: (productId: string) => request<ProductDetailResponse>(`/product/${productId}`),
  getReviews: (productId: string) => request<ReviewsResponse>(`/product/${productId}/reviews`),
  addToCart: (productId: string, quantity = 1) =>
    request<CartResponse>('/cart', 'POST', {product_id: productId, quantity}),
  getCart: () => request<CartResponse>('/cart'),
  deleteCartItem: (productId: string) => request<CartResponse>(`/cart/${productId}`, 'DELETE'),
  addToWishlist: (productId: string) =>
    request<WishlistResponse>('/wishlist', 'POST', {product_id: productId}),
  checkoutGuest: (email = '') => request<CheckoutResponse>('/checkout/guest', 'POST', {email}),
  checkoutSignIn: (email = '') => request<CheckoutResponse>('/checkout/signin', 'POST', {email}),
  payCard: (checkoutSession = '', cardLast4 = '4242') =>
    request<PaymentResponse>('/payment/card', 'POST', {
      checkout_session: checkoutSession,
      card_last4: cardLast4,
    }),
  payApplePay: (checkoutSession = '') =>
    request<PaymentResponse>('/payment/applepay', 'POST', {checkout_session: checkoutSession}),
  payPayPal: (checkoutSession = '') =>
    request<PaymentResponse>('/payment/paypal', 'POST', {checkout_session: checkoutSession}),
  getConfirmation: (orderId = '') => request<ConfirmationResponse>(`/confirmation/${orderId}`),
};
