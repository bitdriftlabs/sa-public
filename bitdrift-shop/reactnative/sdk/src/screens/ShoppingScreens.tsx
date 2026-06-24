import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import {getSessionURL} from '@bitdrift/react-native';
import {BITDRIFT_API_KEY, BITDRIFT_API_HOST} from '../config';
import {ApiClient} from '../api/ApiClient';
import {Colors} from '../utils/colors';
import {useSimulation} from '../context/SimulationContext';
import {CategoryRowList, PrimaryButton, ProductRowList, ScreenContainer, SecondaryButton, SimButton} from '../components';
import type {ScreenProps} from '../navigation/types';
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
  ProductCard,
  ReviewsResponse,
  SearchResponse,
  WelcomeResponse,
  WishlistResponse,
} from '../types/models';

const fallbackProduct = 'prod_a1b2c3';

const money = (value: number | undefined) => `$${(value ?? 0).toFixed(2)}`;

export const WelcomeScreen: React.FC<ScreenProps<'Welcome'>> = ({navigation}) => {
  const {isSimulating, startSimulation, startInfiniteSimulation} = useSimulation();
  const [data, setData] = React.useState<WelcomeResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getWelcome().then(setData).catch(() => undefined);
  }, []);

  // Workshop 6 — Device Code
  // Note: we call getDeviceID() + fetch directly rather than generateDeviceCode()
  // because the SDK builds the URL as host:443 which iOS rejects.
  const onDeviceCode = React.useCallback(async () => {
    try {
      const {getDeviceID} = require('@bitdrift/react-native');
      const deviceId: string = await getDeviceID();
      const apiUrl = BITDRIFT_API_HOST ?? 'https://api.bitdrift.io';
      const res = await fetch(`${apiUrl}/v1/device/code`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-bitdrift-api-key': BITDRIFT_API_KEY,
        },
        body: JSON.stringify({device_id: deviceId}),
      });
      const data = await res.json();
      Alert.alert('Device Code', data?.code ?? `Error: status ${res.status}`, [{text: 'OK'}]);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      Alert.alert('Device Code', `Failed: ${msg}`, [{text: 'OK'}]);
    }
  }, []);

  // Workshop 7 — Support Log (session URL)
  const onSupportLog = React.useCallback(async () => {
    try {
      const url = await getSessionURL();
      Alert.alert('Support Log URL', url ?? 'No session URL available.', [{text: 'OK'}]);
    } catch {
      Alert.alert('Support Log', 'Failed to retrieve session URL.');
    }
  }, []);

  const subtitle = data
    ? `${data.tagline}\n${data.promotions?.[0]?.title ?? ''}`
    : 'Experience different shopping journeys';

  return (
    <ScreenContainer
      screenName="Welcome"
      title={data?.store_name ?? 'bitdrift shop'}
      subtitle={subtitle}
      step={1}
      icon="🛍️"
      color={Colors.welcome}
      logoSource={require('../assets/bitdrift_logo.png')}>
      <PrimaryButton
        title="Browse Products"
        icon="☰"
        disabled={isSimulating}
        onPress={() => navigation.navigate('Browse')}
      />
      <SecondaryButton
        title="Search for Items"
        icon="⌕"
        disabled={isSimulating}
        onPress={() => navigation.navigate('Search')}
      />

      <View style={styles.divider} />

      {isSimulating ? (
        <Text style={styles.simHint}>Simulation in progress...</Text>
      ) : (
        <View style={styles.simButtonsRow}>
          <SimButton title="Sim 10" color={Colors.search} onPress={() => startSimulation(10)} />
          <SimButton title="Sim 100" color="#D32F2F" onPress={() => startSimulation(100)} />
          <SimButton title="∞ Sim" color={Colors.browse} onPress={startInfiniteSimulation} />
        </View>
      )}

      <View style={styles.divider} />

      <View style={styles.simButtonsRow}>
        <SimButton title="Device Code" color={Colors.categories} onPress={onDeviceCode} />
        <SimButton title="Support Log" color={Colors.wishlist} onPress={onSupportLog} />
      </View>
    </ScreenContainer>
  );
};

export const BrowseScreen: React.FC<ScreenProps<'Browse'>> = ({navigation}) => {
  const [data, setData] = React.useState<BrowseResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getBrowse().then(setData).catch(() => undefined);
  }, []);

  const products = data?.products ?? [];
  const subtitle = data
    ? `Showing ${products.length} of ${data.total_products} products`
    : 'Explore our product catalog';

  return (
    <ScreenContainer
      screenName="Browse"
      title="Browse"
      subtitle={subtitle}
      step={2}
      icon="🧺"
      color={Colors.browse}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <ProductRowList
        products={products}
        onPress={productId => navigation.navigate('ProductDetail', {source: 'browse', productId})}
      />
      <PrimaryButton title="View Featured" icon="★" onPress={() => navigation.navigate('Featured')} />
      <SecondaryButton title="Shop by Category" icon="☷" onPress={() => navigation.navigate('Categories')} />
    </ScreenContainer>
  );
};

export const SearchScreen: React.FC<ScreenProps<'Search'>> = ({navigation}) => {
  const [data, setData] = React.useState<SearchResponse | null>(null);

  React.useEffect(() => {
    ApiClient.search('headphones').then(setData).catch(() => undefined);
  }, []);

  const products = data?.products ?? [];
  const subtitle = data
    ? `Found ${data.result_count} results for "${data.query}"`
    : 'Find exactly what you are looking for';

  return (
    <ScreenContainer
      screenName="Search"
      title="Search"
      subtitle={subtitle}
      step={2}
      icon="⌕"
      color={Colors.search}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <ProductRowList
        products={products}
        onPress={productId => navigation.navigate('ProductDetail', {source: 'search', productId})}
      />
      <PrimaryButton title="View Featured" icon="★" onPress={() => navigation.navigate('Featured')} />
      <SecondaryButton title="Shop by Category" icon="☷" onPress={() => navigation.navigate('Categories')} />
    </ScreenContainer>
  );
};

export const FeaturedScreen: React.FC<ScreenProps<'Featured'>> = ({navigation}) => {
  const [data, setData] = React.useState<FeaturedResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getFeatured().then(setData).catch(() => undefined);
  }, []);

  const products = data?.featured_products ?? [];
  const first = products[0]?.id ?? fallbackProduct;
  const subtitle = data
    ? `${data.banner?.text ?? 'Featured'} — ${products.length} picks`
    : 'Our top picks for you';

  return (
    <ScreenContainer
      screenName="Featured"
      title="Featured Products"
      subtitle={subtitle}
      step={3}
      icon="★"
      color={Colors.featured}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <ProductRowList
        products={products}
        onPress={productId => navigation.navigate('ProductDetail', {source: 'featured', productId})}
      />
      <PrimaryButton
        title="View Product Details"
        icon="i"
        onPress={() => navigation.navigate('ProductDetail', {source: 'featured', productId: first})}
      />
      <SecondaryButton
        title="Read Reviews First"
        icon="✎"
        onPress={() => navigation.navigate('Reviews', {source: 'featured', productId: first})}
      />
    </ScreenContainer>
  );
};

export const CategoriesScreen: React.FC<ScreenProps<'Categories'>> = ({navigation}) => {
  const [data, setData] = React.useState<CategoriesResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getCategories().then(setData).catch(() => undefined);
  }, []);

  const categories = data?.categories ?? [];
  const subtitle = categories.length > 0
    ? categories.map(item => item.name).join(', ')
    : 'Browse by product type';

  return (
    <ScreenContainer
      screenName="Categories"
      title="Categories"
      subtitle={subtitle}
      step={3}
      icon="☷"
      color={Colors.categories}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <CategoryRowList
        categories={categories}
        onPress={category => navigation.navigate('CategoryBrowse', {category})}
      />
      <PrimaryButton
        title="View Product Details"
        icon="i"
        onPress={() => navigation.navigate('ProductDetail', {source: 'categories', productId: fallbackProduct})}
      />
      <SecondaryButton
        title="Read Reviews First"
        icon="✎"
        onPress={() => navigation.navigate('Reviews', {source: 'categories', productId: fallbackProduct})}
      />
    </ScreenContainer>
  );
};

export const CategoryBrowseScreen: React.FC<ScreenProps<'CategoryBrowse'>> = ({navigation, route}) => {
  const category = route.params.category;
  const [data, setData] = React.useState<CategoryProductsResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getCategoryProducts(category).then(setData).catch(() => undefined);
  }, [category]);

  const products = data?.products ?? [];
  const first = products[0]?.id ?? fallbackProduct;

  return (
    <ScreenContainer
      screenName="CategoryBrowse"
      title={category}
      subtitle={products.length > 0 ? `${products.length} products in ${category}` : `Loading ${category}...`}
      step={3}
      icon="☷"
      color={Colors.categories}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <ProductRowList
        products={products}
        onPress={productId => navigation.navigate('ProductDetail', {source: 'categories', productId})}
      />
      <PrimaryButton
        title="View Product Details"
        icon="i"
        onPress={() => navigation.navigate('ProductDetail', {source: 'categories', productId: first})}
      />
      <SecondaryButton
        title="Read Reviews First"
        icon="✎"
        onPress={() => navigation.navigate('Reviews', {source: 'categories', productId: first})}
      />
    </ScreenContainer>
  );
};

export const ProductDetailScreen: React.FC<ScreenProps<'ProductDetail'>> = ({navigation, route}) => {
  const {productId} = route.params;
  const [data, setData] = React.useState<ProductDetailResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getProduct(productId).then(setData).catch(() => undefined);
  }, [productId]);

  const subtitle = data
    ? `${data.brand} — ${money(data.price)} — ${data.stock_count} in stock`
    : 'Loading product details...';

  return (
    <ScreenContainer
      screenName="ProductDetail"
      title={data?.name ?? 'Product Detail'}
      subtitle={subtitle}
      step={4}
      icon="◉"
      color={Colors.productDetail}
      imageUrl={data?.images?.[0]}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Add to Cart"
        icon="＋"
        onPress={() => navigation.navigate('Cart', {productId})}
      />
      <SecondaryButton
        title="Save to Wishlist"
        icon="♡"
        onPress={() => navigation.navigate('Wishlist', {productId})}
      />
    </ScreenContainer>
  );
};

export const ReviewsScreen: React.FC<ScreenProps<'Reviews'>> = ({navigation, route}) => {
  const {productId} = route.params;
  const [data, setData] = React.useState<ReviewsResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getReviews(productId).then(setData).catch(() => undefined);
  }, [productId]);

  const top = data?.reviews?.[0];
  const subtitle = data
    ? `${data.average_rating} stars from ${data.total_reviews} reviews\n"${top?.title ?? ''}"`
    : 'Loading reviews...';

  return (
    <ScreenContainer
      screenName="Reviews"
      title="Customer Reviews"
      subtitle={subtitle}
      step={4}
      icon="✎"
      color={Colors.reviews}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton title="Add to Cart" icon="＋" onPress={() => navigation.navigate('Cart', {productId})} />
      <SecondaryButton
        title="Save to Wishlist"
        icon="♡"
        onPress={() => navigation.navigate('Wishlist', {productId})}
      />
    </ScreenContainer>
  );
};

const CartItems: React.FC<{
  data: CartResponse;
  onDelete: (productId: string) => void;
}> = ({data, onDelete}) => {
  if (!data.items?.length) {
    return null;
  }

  return (
    <ScrollView style={styles.cartList} contentContainerStyle={styles.cartListContent}>
      {data.items.map(item => (
        <View key={item.product_id} style={styles.cartRow}>
          <View style={styles.cartDetails}>
            <Text style={styles.cartTitle} numberOfLines={1}>
              {item.name}
            </Text>
            <Text style={styles.cartMeta}>Qty: {item.quantity}</Text>
          </View>
          <Text style={styles.cartPrice}>{money(item.line_total)}</Text>
          <TouchableOpacity onPress={() => onDelete(item.product_id)} style={styles.deleteButton}>
            <Text style={styles.deleteText}>Del</Text>
          </TouchableOpacity>
        </View>
      ))}
    </ScrollView>
  );
};

export const CartScreen: React.FC<ScreenProps<'Cart'>> = ({navigation, route}) => {
  const productId = route.params?.productId ?? '';
  const [data, setData] = React.useState<CartResponse | null>(null);

  React.useEffect(() => {
    const load = async () => {
      try {
        const response = productId ? await ApiClient.addToCart(productId) : await ApiClient.getCart();
        setData(response);
      } catch {}
    };
    load();
  }, [productId]);

  const removeItem = async (id: string) => {
    try {
      const response = await ApiClient.deleteCartItem(id);
      setData(response);
    } catch {}
  };

  const count = data?.items?.length ?? 0;
  const subtitle = data
    ? count === 0
      ? 'Your cart is empty'
      : `${count} item${count > 1 ? 's' : ''} — Total: ${money(data.total)} (incl. ${money(data.tax)} tax)`
    : 'Loading cart...';

  return (
    <ScreenContainer
      screenName="Cart"
      title="Shopping Cart"
      subtitle={subtitle}
      step={5}
      icon="🛒"
      color={Colors.cart}
      onBack={() => navigation.goBack()}>
      {data ? <CartItems data={data} onDelete={removeItem} /> : null}
      <PrimaryButton
        title="Checkout as Guest"
        icon="👤"
        onPress={() => navigation.navigate('CheckoutGuest', {productId})}
      />
      <SecondaryButton
        title="Sign In to Checkout"
        icon="🔐"
        onPress={() => navigation.navigate('CheckoutSignIn', {productId})}
      />
      <SecondaryButton
        title="Keep Shopping"
        icon="↺"
        onPress={() => navigation.reset({index: 0, routes: [{name: 'Welcome'}]})}
      />
    </ScreenContainer>
  );
};

export const WishlistScreen: React.FC<ScreenProps<'Wishlist'>> = ({navigation, route}) => {
  const productId = route.params?.productId ?? fallbackProduct;
  const [data, setData] = React.useState<WishlistResponse | null>(null);

  React.useEffect(() => {
    ApiClient.addToWishlist(productId).then(setData).catch(() => undefined);
  }, [productId]);

  const subtitle = data
    ? `${data.item_count} items saved — ${data.items?.[0]?.name ?? ''}`
    : 'Loading wishlist...';

  return (
    <ScreenContainer
      screenName="Wishlist"
      title="Wishlist"
      subtitle={subtitle}
      step={5}
      icon="♡"
      color={Colors.wishlist}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Checkout as Guest"
        icon="👤"
        onPress={() => navigation.navigate('CheckoutGuest', {productId})}
      />
      <SecondaryButton
        title="Sign In to Checkout"
        icon="🔐"
        onPress={() => navigation.navigate('CheckoutSignIn', {productId})}
      />
    </ScreenContainer>
  );
};

export const CheckoutGuestScreen: React.FC<ScreenProps<'CheckoutGuest'>> = ({navigation, route}) => {
  const productId = route.params?.productId ?? '';
  const [data, setData] = React.useState<CheckoutResponse | null>(null);

  React.useEffect(() => {
    ApiClient.checkoutGuest().then(setData).catch(() => undefined);
  }, []);

  const session = data?.checkout_session ?? '';
  const subtitle = data
    ? `Shipping to ${data.shipping_address?.city ?? ''} — ${money(data.order_preview?.total)}\n${data.email ?? ''}`
    : 'Loading checkout...';

  return (
    <ScreenContainer
      screenName="CheckoutGuest"
      title="Guest Checkout"
      subtitle={subtitle}
      step={6}
      icon="👤"
      color={Colors.checkoutGuest}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart', {productId})}>
      <PrimaryButton
        title="Pay with Card"
        icon="✓"
        onPress={() => navigation.navigate('PaymentCard', {checkoutSession: session})}
      />
      <SecondaryButton
        title="Apple Pay"
        icon="◉"
        onPress={() => navigation.navigate('PaymentApplePay', {checkoutSession: session})}
      />
    </ScreenContainer>
  );
};

export const CheckoutSignInScreen: React.FC<ScreenProps<'CheckoutSignIn'>> = ({navigation, route}) => {
  const productId = route.params?.productId ?? '';
  const [data, setData] = React.useState<CheckoutResponse | null>(null);

  React.useEffect(() => {
    ApiClient.checkoutSignIn().then(setData).catch(() => undefined);
  }, []);

  const session = data?.checkout_session ?? '';
  const subtitle = data
    ? `Welcome back, ${data.user?.name ?? ''}\n${data.user?.email ?? ''} — ${data.user?.loyalty_points ?? 0} pts — ${money(data.order_preview?.total)}`
    : 'Loading checkout...';

  return (
    <ScreenContainer
      screenName="CheckoutSignIn"
      title="Member Checkout"
      subtitle={subtitle}
      step={6}
      icon="🔐"
      color={Colors.checkoutSignIn}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart', {productId})}>
      <PrimaryButton
        title="Pay with Card"
        icon="✓"
        onPress={() => navigation.navigate('PaymentCard', {checkoutSession: session})}
      />
      <SecondaryButton
        title="PayPal"
        icon="⇄"
        onPress={() => navigation.navigate('PaymentPayPal', {checkoutSession: session})}
      />
    </ScreenContainer>
  );
};

export const PaymentCardScreen: React.FC<ScreenProps<'PaymentCard'>> = ({navigation, route}) => {
  const checkoutSession = route.params?.checkoutSession ?? '';
  const [data, setData] = React.useState<PaymentResponse | null>(null);

  React.useEffect(() => {
    ApiClient.payCard(checkoutSession).then(setData).catch(() => undefined);
  }, [checkoutSession]);

  const orderId = data?.order_id ?? '';
  const txn = data?.transaction_id?.slice(0, 20) ?? '';

  return (
    <ScreenContainer
      screenName="PaymentCard"
      title="Card Payment"
      subtitle={data ? `${data.payment_method}\n${money(data.amount_charged)} — ${txn}...` : 'Processing payment...'}
      step={6}
      icon="💳"
      color={Colors.paymentCard}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton title="Visa ending 4242" icon="✓" onPress={() => navigation.navigate('Confirmation', {orderId})} />
      <SecondaryButton title="Mastercard ending 8888" icon="✓" onPress={() => navigation.navigate('Confirmation', {orderId})} />
      <SecondaryButton title="Amex ending 1001" icon="✓" onPress={() => navigation.navigate('Confirmation', {orderId})} />
    </ScreenContainer>
  );
};

export const PaymentApplePayScreen: React.FC<ScreenProps<'PaymentApplePay'>> = ({navigation, route}) => {
  const checkoutSession = route.params?.checkoutSession ?? '';
  const [data, setData] = React.useState<PaymentResponse | null>(null);

  React.useEffect(() => {
    ApiClient.payApplePay(checkoutSession).then(setData).catch(() => undefined);
  }, [checkoutSession]);

  const orderId = data?.order_id ?? '';
  const txn = data?.transaction_id?.slice(0, 20) ?? '';

  return (
    <ScreenContainer
      screenName="PaymentApplePay"
      title="Apple Pay"
      subtitle={data ? `Apple Pay — ${money(data.amount_charged)}\n${txn}...` : 'Authenticating...'}
      step={6}
      icon="◉"
      color={Colors.paymentApplePay}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Complete Purchase"
        icon="✓"
        onPress={() => navigation.navigate('Confirmation', {orderId})}
      />
    </ScreenContainer>
  );
};

export const PaymentPayPalScreen: React.FC<ScreenProps<'PaymentPayPal'>> = ({navigation, route}) => {
  const checkoutSession = route.params?.checkoutSession ?? '';
  const [data, setData] = React.useState<PaymentResponse | null>(null);

  React.useEffect(() => {
    ApiClient.payPayPal(checkoutSession).then(setData).catch(() => undefined);
  }, [checkoutSession]);

  const orderId = data?.order_id ?? '';

  return (
    <ScreenContainer
      screenName="PaymentPayPal"
      title="PayPal"
      subtitle={data ? `PayPal — ${money(data.amount_charged)}\nRef: ${data.paypal_reference ?? ''}` : 'Connecting to PayPal...'}
      step={6}
      icon="⇄"
      color={Colors.paymentPayPal}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Complete Purchase"
        icon="✓"
        onPress={() => navigation.navigate('Confirmation', {orderId})}
      />
    </ScreenContainer>
  );
};

export const ConfirmationScreen: React.FC<ScreenProps<'Confirmation'>> = ({navigation, route}) => {
  const orderId = route.params?.orderId ?? '';
  const [data, setData] = React.useState<ConfirmationResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getConfirmation(orderId).then(setData).catch(() => undefined);
  }, [orderId]);

  const subtitle = data
    ? `Order ${data.order_id}\nTotal: ${money(data.total)}\nDelivery: ${data.shipping?.estimated_delivery ?? ''}\nTracking: ${data.shipping?.tracking_number ?? ''}\nTxn: ${data.transaction_id.slice(0, 24)}...`
    : `Order ${orderId}\nThank you for your purchase!`;

  return (
    <ScreenContainer
      screenName="Confirmation"
      title="Order Confirmed!"
      subtitle={subtitle}
      step={7}
      icon="✓"
      color={Colors.confirmation}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Start New Journey"
        icon="↺"
        onPress={() => navigation.reset({index: 0, routes: [{name: 'Welcome'}]})}
      />
    </ScreenContainer>
  );
};

const styles = StyleSheet.create({
  divider: {
    width: '100%',
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.24)',
    marginVertical: 8,
  },
  simButtonsRow: {
    width: '100%',
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 8,
  },
  simHint: {
    color: Colors.muted,
    textAlign: 'center',
    marginVertical: 8,
  },
  cartList: {
    width: '100%',
    maxHeight: 220,
    marginBottom: 12,
  },
  cartListContent: {
    gap: 8,
  },
  cartRow: {
    backgroundColor: 'rgba(255,255,255,0.14)',
    borderColor: Colors.border,
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
  },
  cartDetails: {
    flex: 1,
  },
  cartTitle: {
    color: Colors.white,
    fontSize: 14,
    fontWeight: '700',
  },
  cartMeta: {
    color: Colors.muted,
    fontSize: 12,
    marginTop: 3,
  },
  cartPrice: {
    color: Colors.white,
    fontSize: 13,
    fontWeight: '700',
    marginHorizontal: 8,
  },
  deleteButton: {
    backgroundColor: 'rgba(255,255,255,0.2)',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  deleteText: {
    color: Colors.white,
    fontSize: 11,
    fontWeight: '700',
  },
});
