export type ProductCard = {
  id: string;
  name: string;
  price: number;
  image_url: string;
  category?: string;
  brand?: string;
};

export type Category = {
  name: string;
  product_count: number;
  icon?: string;
};

export type Review = {
  rating: number;
  title: string;
  body: string;
  author: string;
};

export type CartItem = {
  product_id: string;
  name: string;
  quantity: number;
  unit_price: number;
  line_total: number;
};

export type WelcomeResponse = {
  store_name: string;
  tagline: string;
  promotions: Array<{title: string; discount?: string; code?: string}>;
  featured_category: string;
};

export type BrowseResponse = {
  products: ProductCard[];
  total_products: number;
};

export type SearchResponse = {
  query: string;
  products: ProductCard[];
  result_count: number;
};

export type FeaturedResponse = {
  featured_products: ProductCard[];
  banner: {text: string; color: string};
};

export type CategoriesResponse = {
  categories: Category[];
};

export type CategoryProductsResponse = {
  category: string;
  products: ProductCard[];
  total: number;
};

export type ProductDetailResponse = {
  id: string;
  name: string;
  brand: string;
  description: string;
  price: number;
  stock_count: number;
  images: string[];
  category: string;
};

export type ReviewsResponse = {
  product_id: string;
  average_rating: number;
  total_reviews: number;
  reviews: Review[];
};

export type CartResponse = {
  cart_id: string;
  items: CartItem[];
  total: number;
  tax: number;
};

export type WishlistResponse = {
  wishlist_id: string;
  item_count: number;
  items: Array<{product_id: string; name: string; price: number}>;
};

export type CheckoutResponse = {
  checkout_session: string;
  email?: string;
  shipping_address?: {city?: string};
  user?: {name?: string; email?: string; loyalty_points?: number};
  order_preview: {total: number};
};

export type PaymentResponse = {
  order_id: string;
  transaction_id: string;
  payment_method: string;
  amount_charged: number;
  paypal_reference?: string;
};

export type ConfirmationResponse = {
  order_id: string;
  transaction_id: string;
  total: number;
  shipping?: {estimated_delivery?: string; tracking_number?: string};
};
