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

// HTTP Instrumentation
// Every API call is timed and logged with path, method, status, and duration so the
// bitdrift dashboard can surface slow or failing endpoints in session timelines.
//
// Path templates: routes with dynamic segments (product id, category, order id) send
// the `x-capture-path-template` header AND log under the canonical template, so high-
// cardinality URLs collapse to one dashboard entry — matching the Android ApiClient.
// The cardinality-demo endpoint (inventoryLookup) deliberately omits the template to
// show the explosion the template prevents.
async function request<T>(
  path: string,
  method: 'GET' | 'POST' | 'DELETE' = 'GET',
  body?: unknown,
  pathTemplate?: string,
): Promise<T> {
  const startMs = Date.now();
  let status = 0;
  // The value logged + grouped on. Use the template for dynamic routes so metrics
  // aggregate; fall back to the concrete path otherwise.
  const loggedPath = pathTemplate ?? path;
  try {
    const headers: Record<string, string> = {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    };
    if (pathTemplate) {
      // `/api` prefix matches the Android header values exactly.
      headers['x-capture-path-template'] = `/api${pathTemplate}`;
    }

    const response = await fetch(`${BASE_URL}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });

    status = response.status;
    const durationMs = Date.now() - startMs;

    const text = await response.text();
    const data = text ? (JSON.parse(text) as T) : ({} as T);

    if (response.ok) {
      ScreenLogger.logDebug('api_response', {
        method,
        path: loggedPath,
        status: String(status),
        duration_ms: String(durationMs),
      });
    } else {
      ScreenLogger.logWarning('api_response_error', {
        method,
        path: loggedPath,
        status: String(status),
        duration_ms: String(durationMs),
      });
    }

    return data;
  } catch (err) {
    const durationMs = Date.now() - startMs;
    ScreenLogger.logError(
      'api_request_failed',
      {
        method,
        path: loggedPath,
        duration_ms: String(durationMs),
      },
      err,
    );
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
    request<CategoryProductsResponse>(
      `/categories/${encodeURIComponent(category)}`,
      'GET',
      undefined,
      '/categories/<category>',
    ),
  getProduct: (productId: string) =>
    request<ProductDetailResponse>(`/product/${productId}`, 'GET', undefined, '/product/<id>'),
  getReviews: (productId: string) =>
    request<ReviewsResponse>(
      `/product/${productId}/reviews`,
      'GET',
      undefined,
      '/product/<id>/reviews',
    ),
  addToCart: (productId: string, quantity = 1) =>
    request<CartResponse>('/cart', 'POST', {product_id: productId, quantity}),
  getCart: () => request<CartResponse>('/cart'),
  deleteCartItem: (productId: string) =>
    request<CartResponse>(`/cart/${productId}`, 'DELETE', undefined, '/cart/<id>'),
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
  payAndroidPay: (checkoutSession = '') =>
    request<PaymentResponse>('/payment/androidpay', 'POST', {checkout_session: checkoutSession}),
  getConfirmation: (orderId = '') =>
    request<ConfirmationResponse>(`/confirmation/${orderId}`, 'GET', undefined, '/confirmation/<id>'),

  // Full catalog as JSON array — feeds the slow-mode recommendation scoring.
  getFullCatalogJson: async (): Promise<string> => {
    try {
      const data = await request<BrowseResponse>('/browse');
      return JSON.stringify(data.products ?? []);
    } catch {
      return '[]';
    }
  },

  // Cardinality demo — fresh random session segment every call, deliberately WITHOUT
  // a path template, so each request lands as a unique URL in the dashboard. This is
  // the explosion that path templates (above) prevent.
  inventoryLookup: (item: string) => {
    const hex = '0123456789abcdef';
    let session = '';
    for (let i = 0; i < 16; i++) {
      session += hex[Math.floor(Math.random() * hex.length)];
    }
    return request<Record<string, unknown>>(
      `/inventory/lookup/${encodeURIComponent(item)}/${session}`,
    );
  },
};
