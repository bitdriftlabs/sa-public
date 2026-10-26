import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import {getDeviceID, getSessionURL} from '@bitdrift/react-native';
import {BITDRIFT_SDK_KEY, BITDRIFT_API_HOST} from '../config';
import {ApiClient} from '../api/ApiClient';
import {Colors} from '../utils/colors';
import {useSimulation} from '../context/SimulationContext';
import {ScreenLogger} from '../utils/logger';
import {SimVariant, VARIANT_LABELS} from '../sim/variants';
import {scoreProducts} from '../sim/recommendations';
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
  ReviewsResponse,
  SearchResponse,
  WelcomeResponse,
  WishlistResponse,
} from '../types/models';
import {SpecEvents, SpecFields, SpecScreens, SpecSpans} from '../generated/spec';

const fallbackProduct = 'prod_a1b2c3';

const money = (value: number | undefined) => `$${(value ?? 0).toFixed(2)}`;

export const WelcomeScreen: React.FC<ScreenProps<'Welcome'>> = ({navigation}) => {
  const {
    isSimulating,
    startSimulation,
    startInfiniteSimulation,
    crashLoopEnabled,
    nextCrashName,
    stopCrashLoop,
  } = useSimulation();
  const [data, setData] = React.useState<WelcomeResponse | null>(null);

  React.useEffect(() => {
    ApiClient.getWelcome().then(setData).catch(() => undefined);
  }, []);

  // Workshop 6 — Device Code
  // Note: we call getDeviceID() + fetch directly rather than generateDeviceCode()
  // because the SDK builds the URL as host:443 which iOS rejects.
  const onDeviceCode = React.useCallback(async () => {
    try {
      const deviceId: string = await getDeviceID();
      const apiUrl = BITDRIFT_API_HOST ?? 'https://api.bitdrift.io';
      const res = await fetch(`${apiUrl}/v1/device/code`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-bitdrift-api-key': BITDRIFT_SDK_KEY,
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
      screenName={SpecScreens.welcome.screenName}
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

      {crashLoopEnabled ? (
        <View style={styles.crashLoopBox}>
          <Text style={styles.crashLoopText}>Crash loop ACTIVE — next: {nextCrashName()}</Text>
          <SecondaryButton title="Stop crash loop" icon="■" onPress={stopCrashLoop} />
        </View>
      ) : null}

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

      <View style={styles.divider} />

      <SecondaryButton
        title="Advanced (variants, chaos)"
        icon="⚙"
        disabled={isSimulating}
        onPress={() => navigation.navigate('Advanced')}
      />
    </ScreenContainer>
  );
};

export const BrowseScreen: React.FC<ScreenProps<'Browse'>> = ({navigation}) => {
  const [data, setData] = React.useState<BrowseResponse | null>(null);
  const {slowModeEnabled} = useSimulation();

  React.useEffect(() => {
    ApiClient.getBrowse().then(setData).catch(() => undefined);
  }, []);

  // useMemo, not a bare `data?.products ?? []`: the array is a dependency of the scoring
  // effect below, and a fresh identity each render would re-run the ~800ms similarity
  // pass on every re-render rather than only when the catalog actually changes.
  const products = React.useMemo(() => data?.products ?? [], [data]);

  // Recommendations v2: the expensive on-thread scoring pass, gated on the same flag as
  // Android's SimulationManager.recommendationsV2Enabled. trackSpanNested hands the span
  // down so parse_catalog / similarity_pass nest under score_products instead of
  // rendering as unrelated flat spans.
  const firstProductId = String(products[0]?.id ?? '');
  React.useEffect(() => {
    if (!slowModeEnabled || !firstProductId) {
      return;
    }
    // Score against the products already on screen rather than re-fetching /browse: the
    // demo backend randomises its catalog per request, so a separate fetch often would
    // not contain firstProductId, and the similarity pass would be skipped entirely.
    ScreenLogger.trackSpanNested(
      SpecSpans.scoreProducts,
      {[SpecFields.productId]: firstProductId, [SpecFields.screenName]: SpecScreens.browse.screenName},
      span => scoreProducts(JSON.stringify(products), firstProductId, span.id),
    );
  }, [slowModeEnabled, firstProductId, products]);
  const subtitle = data
    ? `Showing ${products.length} of ${data.total_products} products`
    : 'Explore our product catalog';

  return (
    <ScreenContainer
      screenName={SpecScreens.browse.screenName}
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
      screenName={SpecScreens.search.screenName}
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
      screenName={SpecScreens.featured.screenName}
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
      screenName={SpecScreens.categories.screenName}
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
      screenName={SpecScreens.categoryBrowse.screenName}
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
  const {productId, source} = route.params;
  const [data, setData] = React.useState<ProductDetailResponse | null>(null);
  const {slowModeEnabled} = useSimulation();

  React.useEffect(() => {
    ApiClient.getProduct(productId).then(setData).catch(() => undefined);
  }, [productId]);

  // Same scoring pass as Browse — Android runs it on both screens so the span appears
  // with two different screen_name values. Fetches the full catalog to score against,
  // matching Android's ApiClient.getFullCatalogJson() call on this screen.
  React.useEffect(() => {
    // Wait for `data`: without it this fires once while the product is still loading,
    // issuing a second catalog request when getProduct resolves — and if that first
    // randomised catalog lacks productId there is no reference to prepend, producing
    // exactly the parse-only score_products span this gating exists to avoid.
    if (!slowModeEnabled || !productId || !data) {
      return;
    }
    let cancelled = false;
    ApiClient.getFullCatalogJson().then(catalogJson => {
      if (cancelled) {
        return;
      }
      // The backend randomises /browse per request, so the fetched catalog may not
      // contain this product. Prepend the one we already loaded, otherwise scoreProducts
      // finds no reference and skips the similarity pass.
      let catalog: unknown[];
      try {
        const parsed = JSON.parse(catalogJson);
        catalog = Array.isArray(parsed) ? parsed : [];
      } catch {
        catalog = [];
      }
      const hasReference = catalog.some(
        p => (p as {id?: string} | null)?.id === productId,
      );
      const withReference = hasReference ? catalog : [data, ...catalog];

      ScreenLogger.trackSpanNested(
        SpecSpans.scoreProducts,
        {[SpecFields.productId]: productId, [SpecFields.screenName]: SpecScreens.productDetail.screenName},
        span => scoreProducts(JSON.stringify(withReference), productId, span.id),
      );
    });
    return () => {
      cancelled = true;
    };
  }, [slowModeEnabled, productId, data]);

  const subtitle = data
    ? `${data.brand} — ${money(data.price)} — ${data.stock_count} in stock`
    : 'Loading product details...';

  return (
    <ScreenContainer
      screenName={SpecScreens.productDetail.screenName}
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
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.addToCart, {[SpecFields.productId]: productId, [SpecFields.sourceScreen]: source});
          navigation.navigate('Cart', {productId});
        }}
      />
      <SecondaryButton
        title="Save to Wishlist"
        icon="♡"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.addToWishlist, {[SpecFields.productId]: productId, [SpecFields.sourceScreen]: source});
          navigation.navigate('Wishlist', {productId});
        }}
      />
    </ScreenContainer>
  );
};

export const ReviewsScreen: React.FC<ScreenProps<'Reviews'>> = ({navigation, route}) => {
  const {productId, source} = route.params;
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
      screenName={SpecScreens.reviews.screenName}
      title="Customer Reviews"
      subtitle={subtitle}
      step={4}
      icon="✎"
      color={Colors.reviews}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Add to Cart"
        icon="＋"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.addToCart, {[SpecFields.productId]: productId, [SpecFields.sourceScreen]: source});
          navigation.navigate('Cart', {productId});
        }}
      />
      <SecondaryButton
        title="Save to Wishlist"
        icon="♡"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.addToWishlist, {[SpecFields.productId]: productId, [SpecFields.sourceScreen]: source});
          navigation.navigate('Wishlist', {productId});
        }}
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
      ScreenLogger.logInfo(SpecEvents.cartItemRemoved, {[SpecFields.productId]: id});
      setData(response);
    } catch (e) {
      ScreenLogger.logError(SpecEvents.cartFailed, {[SpecFields.productId]: id}, e);
    }
  };

  const count = data?.items?.length ?? 0;
  const subtitle = data
    ? count === 0
      ? 'Your cart is empty'
      : `${count} item${count > 1 ? 's' : ''} — Total: ${money(data.total)} (incl. ${money(data.tax)} tax)`
    : 'Loading cart...';

  return (
    <ScreenContainer
      screenName={SpecScreens.cart.screenName}
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
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.checkoutStarted, {[SpecFields.checkoutType]: 'guest'});
          navigation.navigate('CheckoutGuest', {productId});
        }}
      />
      <SecondaryButton
        title="Sign In to Checkout"
        icon="🔐"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.checkoutStarted, {[SpecFields.checkoutType]: 'signin'});
          navigation.navigate('CheckoutSignIn', {productId});
        }}
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
      screenName={SpecScreens.wishlist.screenName}
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
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.checkoutStarted, {[SpecFields.checkoutType]: 'guest'});
          navigation.navigate('CheckoutGuest', {productId});
        }}
      />
      <SecondaryButton
        title="Sign In to Checkout"
        icon="🔐"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.checkoutStarted, {[SpecFields.checkoutType]: 'signin'});
          navigation.navigate('CheckoutSignIn', {productId});
        }}
      />
    </ScreenContainer>
  );
};

export const CheckoutGuestScreen: React.FC<ScreenProps<'CheckoutGuest'>> = ({navigation, route}) => {
  const productId = route.params?.productId ?? '';
  const [data, setData] = React.useState<CheckoutResponse | null>(null);

  React.useEffect(() => {
    // logError with the caught exception records checkout failures in the session
    // timeline, matching Android/iOS. Previously this catch swallowed the error.
    ApiClient.checkoutGuest()
      .then(setData)
      .catch(err => ScreenLogger.logError(SpecEvents.checkoutFailed, {[SpecFields.checkoutType]: 'guest'}, err));
  }, []);

  const session = data?.checkout_session ?? '';
  const subtitle = data
    ? `Shipping to ${data.shipping_address?.city ?? ''} — ${money(data.order_preview?.total)}\n${data.email ?? ''}`
    : 'Loading checkout...';

  return (
    <ScreenContainer
      screenName={SpecScreens.checkoutGuest.screenName}
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
    ApiClient.checkoutSignIn()
      .then(setData)
      .catch(err => ScreenLogger.logError(SpecEvents.checkoutFailed, {[SpecFields.checkoutType]: 'signin'}, err));
  }, []);

  const session = data?.checkout_session ?? '';
  const subtitle = data
    ? `Welcome back, ${data.user?.name ?? ''}\n${data.user?.email ?? ''} — ${data.user?.loyalty_points ?? 0} pts — ${money(data.order_preview?.total)}`
    : 'Loading checkout...';

  return (
    <ScreenContainer
      screenName={SpecScreens.checkoutSignin.screenName}
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
      screenName={SpecScreens.paymentCard.screenName}
      title="Card Payment"
      subtitle={data ? `${data.payment_method}\n${money(data.amount_charged)} — ${txn}...` : 'Processing payment...'}
      step={6}
      icon="💳"
      color={Colors.paymentCard}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Visa ending 4242"
        icon="✓"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.paymentCompleted, {[SpecFields.paymentMethod]: 'visa', [SpecFields.cardLast4]: '4242', [SpecFields.orderId]: orderId});
          navigation.navigate('Confirmation', {orderId});
        }}
      />
      <SecondaryButton
        title="Mastercard ending 8888"
        icon="✓"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.paymentCompleted, {[SpecFields.paymentMethod]: 'mastercard', [SpecFields.cardLast4]: '8888', [SpecFields.orderId]: orderId});
          navigation.navigate('Confirmation', {orderId});
        }}
      />
      <SecondaryButton
        title="Amex ending 1001"
        icon="✓"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.paymentCompleted, {[SpecFields.paymentMethod]: 'amex', [SpecFields.cardLast4]: '1001', [SpecFields.orderId]: orderId});
          navigation.navigate('Confirmation', {orderId});
        }}
      />
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
      screenName={SpecScreens.paymentApplePay.screenName}
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
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.paymentCompleted, {[SpecFields.paymentMethod]: 'apple_pay', [SpecFields.orderId]: orderId});
          navigation.navigate('Confirmation', {orderId});
        }}
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
      screenName={SpecScreens.paymentPaypal.screenName}
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
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.paymentCompleted, {[SpecFields.paymentMethod]: 'paypal', [SpecFields.orderId]: orderId});
          navigation.navigate('Confirmation', {orderId});
        }}
      />
    </ScreenContainer>
  );
};

export const PaymentAndroidPayScreen: React.FC<ScreenProps<'PaymentAndroidPay'>> = ({navigation, route}) => {
  const checkoutSession = route.params?.checkoutSession ?? '';
  const [data, setData] = React.useState<PaymentResponse | null>(null);

  React.useEffect(() => {
    ApiClient.payAndroidPay(checkoutSession).then(setData).catch(() => undefined);
  }, [checkoutSession]);

  const orderId = data?.order_id ?? '';

  return (
    <ScreenContainer
      screenName={SpecScreens.paymentAndroidPay.screenName}
      title="Google Pay"
      subtitle={data ? `Google Pay — ${money(data.amount_charged)}` : 'Authenticating...'}
      step={6}
      icon="◈"
      color={Colors.paymentApplePay}
      onBack={() => navigation.goBack()}
      onCart={() => navigation.navigate('Cart')}>
      <PrimaryButton
        title="Complete Purchase"
        icon="✓"
        onPress={() => {
          ScreenLogger.logInfo(SpecEvents.paymentCompleted, {[SpecFields.paymentMethod]: 'android_pay', [SpecFields.orderId]: orderId});
          navigation.navigate('Confirmation', {orderId});
        }}
      />
    </ScreenContainer>
  );
};

export const PaymentFailedScreen: React.FC<ScreenProps<'PaymentFailed'>> = ({navigation, route}) => {
  const method = route.params?.paymentMethod ?? 'card';

  React.useEffect(() => {
    ScreenLogger.logError(SpecEvents.paymentFailed, {[SpecFields.paymentMethod]: method});
  }, [method]);

  return (
    <ScreenContainer
      screenName={SpecScreens.paymentFailed.screenName}
      title="Payment Failed"
      subtitle={`We couldn't process your ${method} payment.\nPlease try a different method.`}
      step={6}
      icon="⚠"
      color="#B71C1C"
      onBack={() => navigation.goBack()}>
      <PrimaryButton
        title="Try Another Method"
        icon="↺"
        onPress={() => navigation.goBack()}
      />
      <SecondaryButton
        title="Back to Cart"
        icon="🛒"
        onPress={() => navigation.navigate('Cart')}
      />
    </ScreenContainer>
  );
};

const VariantButton: React.FC<{
  label: string;
  active: boolean;
  color: string;
  onPress: () => void;
}> = ({label, active, color, onPress}) => (
  <TouchableOpacity
    style={[styles.variantButton, {backgroundColor: active ? color : Colors.panelStrong}]}
    onPress={onPress}
    activeOpacity={0.85}>
    <Text style={[styles.variantButtonText, active && styles.onAccentText]}>{label}</Text>
  </TouchableOpacity>
);

const ToggleButton: React.FC<{
  label: string;
  on: boolean;
  disabled?: boolean;
  onColor: string;
  onPress: () => void;
}> = ({label, on, disabled, onColor, onPress}) => (
  <TouchableOpacity
    style={[
      styles.toggleButton,
      {backgroundColor: on ? onColor : Colors.panelStrong},
      disabled && styles.toggleDisabled,
    ]}
    onPress={onPress}
    disabled={disabled}
    activeOpacity={0.85}>
    <Text style={[styles.toggleButtonText, on && styles.onAccentText]}>{on ? `${label}: ON` : label}</Text>
  </TouchableOpacity>
);

export const AdvancedScreen: React.FC<ScreenProps<'Advanced'>> = ({navigation}) => {
  const {
    activeVariant,
    setVariant,
    crashLoopEnabled,
    anrAEnabled,
    forceQuitEnabled,
    slowModeEnabled,
    supportLogEnabled,
    setCrashLoop,
    setAnrA,
    setForceQuit,
    setSlowMode,
    setSupportLog,
    nextCrashName,
    startAbSimulation,
    startCardinalitySimulation,
    isSimulating,
  } = useSimulation();

  const isVariantA = activeVariant === SimVariant.VariantA;
  const anrStatus = !isVariantA
    ? 'unavailable (select Variant A)'
    : anrAEnabled
    ? 'enabled'
    : 'disabled';
  const crashStatus = crashLoopEnabled ? `enabled (next: ${nextCrashName()})` : 'disabled';

  return (
    <ScreenContainer
      screenName={SpecScreens.advanced.screenName}
      title="Advanced"
      subtitle="Personas, simulation modes, and fault injection"
      step={1}
      icon="⚙"
      color={Colors.welcome}
      onBack={() => navigation.goBack()}>
      <ScrollView style={styles.advancedScroll} contentContainerStyle={styles.advancedContent}>
        <Text style={styles.advancedLabel}>Simulation Variant</Text>
        <View style={styles.variantRow}>
          <VariantButton
            label="Control"
            active={activeVariant === SimVariant.Control}
            color="#607D8B"
            onPress={() => setVariant(SimVariant.Control)}
          />
          <VariantButton
            label="Variant A"
            active={activeVariant === SimVariant.VariantA}
            color="#00BCD4"
            onPress={() => setVariant(SimVariant.VariantA)}
          />
          <VariantButton
            label="Variant B"
            active={activeVariant === SimVariant.VariantB}
            color="#FF9800"
            onPress={() => setVariant(SimVariant.VariantB)}
          />
        </View>
        <Text style={styles.advancedHint}>Active: {VARIANT_LABELS[activeVariant]}</Text>

        <Text style={styles.advancedLabel}>Simulation Modes</Text>
        <View style={styles.variantRow}>
          <SimButton title="Sim A/B (5 each)" color={Colors.browse} onPress={() => startAbSimulation(5)} />
          <SimButton title="Cardinality" color="#9C27B0" onPress={startCardinalitySimulation} />
        </View>

        <Text style={styles.advancedLabel}>Fault Injection</Text>
        <View style={styles.toggleRow}>
          <ToggleButton label="Slow" on={slowModeEnabled} onColor="#FF5722" onPress={() => setSlowMode(!slowModeEnabled)} />
          <ToggleButton label="Crash" on={crashLoopEnabled} onColor="#D32F2F" onPress={() => setCrashLoop(!crashLoopEnabled)} />
        </View>
        <View style={styles.toggleRow}>
          <ToggleButton
            label="ANR-A"
            on={anrAEnabled}
            disabled={!isVariantA}
            onColor="#F44336"
            onPress={() => setAnrA(!anrAEnabled)}
          />
          <ToggleButton label="Quit" on={forceQuitEnabled} onColor="#FF6F00" onPress={() => setForceQuit(!forceQuitEnabled)} />
        </View>

        <View style={styles.statusChip}>
          <Text style={styles.statusChipText}>
            Crash: {crashStatus} | ANR-A: {anrStatus} | Quit: {forceQuitEnabled ? 'enabled' : 'disabled'}
          </Text>
        </View>

        {isVariantA && anrAEnabled ? (
          <Text style={styles.advancedHint}>
            ANR Watchdog Required — run scripts/watchdog.sh to auto-dismiss the ANR and relaunch.
          </Text>
        ) : null}
        {forceQuitEnabled ? (
          <Text style={styles.advancedHint}>
            Force-quit kills the process — run scripts/watchdog.sh to detect and relaunch.
          </Text>
        ) : null}

        <Text style={styles.advancedLabel}>Debug Tools</Text>
        <ToggleButton
          label="Support Log"
          on={supportLogEnabled}
          onColor="#4CAF50"
          onPress={() => setSupportLog(!supportLogEnabled)}
        />
        {isSimulating ? <Text style={styles.simHint}>Simulation in progress...</Text> : null}
      </ScrollView>
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
      screenName={SpecScreens.confirmation.screenName}
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
    backgroundColor: Colors.panelBorder,
    marginVertical: 8,
  },
  simButtonsRow: {
    width: '100%',
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 8,
  },
  simHint: {
    color: Colors.textMuted,
    textAlign: 'center',
    marginVertical: 8,
  },
  crashLoopBox: {
    width: '100%',
    backgroundColor: 'rgba(211,47,47,0.25)',
    borderColor: '#D32F2F',
    borderWidth: 1,
    borderRadius: 12,
    padding: 10,
    marginVertical: 6,
    gap: 8,
  },
  crashLoopText: {
    color: Colors.text,
    fontSize: 13,
    fontWeight: '700',
    textAlign: 'center',
  },
  advancedScroll: {
    width: '100%',
  },
  advancedContent: {
    paddingBottom: 16,
    gap: 4,
  },
  advancedLabel: {
    color: Colors.text,
    fontSize: 14,
    fontWeight: '700',
    marginTop: 14,
    marginBottom: 6,
  },
  advancedHint: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
  },
  variantRow: {
    flexDirection: 'row',
    gap: 8,
  },
  variantButton: {
    flex: 1,
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
  },
  variantButtonText: {
    color: Colors.text,
    fontSize: 13,
    fontWeight: '700',
  },
  toggleRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
  },
  toggleButton: {
    flex: 1,
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
  },
  toggleButtonText: {
    color: Colors.text,
    fontSize: 13,
    fontWeight: '700',
  },
  onAccentText: {
    color: Colors.white,
  },
  toggleDisabled: {
    opacity: 0.4,
  },
  statusChip: {
    width: '100%',
    backgroundColor: Colors.panel,
    borderRadius: 10,
    padding: 10,
    marginTop: 10,
  },
  statusChipText: {
    color: Colors.text,
    fontSize: 12,
    textAlign: 'center',
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
    backgroundColor: 'rgba(17,24,39,0.05)',
    borderColor: Colors.panelBorder,
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
    color: Colors.text,
    fontSize: 14,
    fontWeight: '700',
  },
  cartMeta: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 3,
  },
  cartPrice: {
    color: Colors.text,
    fontSize: 13,
    fontWeight: '700',
    marginHorizontal: 8,
  },
  deleteButton: {
    backgroundColor: 'rgba(17,24,39,0.10)',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  deleteText: {
    color: Colors.text,
    fontSize: 11,
    fontWeight: '700',
  },
});
