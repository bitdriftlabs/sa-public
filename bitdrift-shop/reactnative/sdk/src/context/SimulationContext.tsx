import React, {createContext, useContext, useState, useRef, useCallback} from 'react';
import type {NavigationContainerRef} from '@react-navigation/native';
import type {RootStackParamList} from '../navigation/types';
import {ScreenLogger} from '../utils/logger';
import {ApiClient} from '../api/ApiClient';

type SimulationState = {
  isSimulating: boolean;
  currentRun: number;
  totalRuns: number;
  isInfinite: boolean;
};

type SimulationContextType = SimulationState & {
  startSimulation: (runs: number) => void;
  startInfiniteSimulation: () => void;
  cancelSimulation: () => void;
  setNavigationRef: (ref: NavigationContainerRef<RootStackParamList>) => void;
};

const SimulationContext = createContext<SimulationContextType | null>(null);

export const useSimulation = () => {
  const context = useContext(SimulationContext);
  if (!context) {
    throw new Error('useSimulation must be used within SimulationProvider');
  }
  return context;
};

export const SimulationProvider: React.FC<{children: React.ReactNode}> = ({
  children,
}) => {
  const [state, setState] = useState<SimulationState>({
    isSimulating: false,
    currentRun: 0,
    totalRuns: 0,
    isInfinite: false,
  });

  const navigationRef = useRef<NavigationContainerRef<RootStackParamList> | null>(null);
  const cancelledRef = useRef(false);
  const progressRef = useRef({currentRun: 0, totalRuns: 0});

  const setNavigationRef = useCallback(
    (ref: NavigationContainerRef<RootStackParamList>) => {
      navigationRef.current = ref;
    },
    [],
  );

  const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
  const stepDelay = 50;

  const randomChoice = <T,>(options: T[]): T =>
    options[Math.floor(Math.random() * options.length)];

  const navigate = async <T extends keyof RootStackParamList>(
    route: T,
    params?: RootStackParamList[T],
  ) => {
    const nav = navigationRef.current;
    if (!nav || cancelledRef.current) {
      return;
    }
    if (params) {
      nav.navigate(route as never, params as never);
    } else {
      nav.navigate(route as never);
    }
    await delay(stepDelay);
  };

  // ─── API Fetch Helpers ───────────────────────────────────────────────

  const searchTerms = [
    'headphones', 'jacket', 'running shoes', 'laptop', 'watch',
    'camera', 'speaker', 'backpack', 'tablet', 'sneakers',
  ];

  const fetchBrowseIds = async (): Promise<string[]> => {
    try {
      const data = await ApiClient.getBrowse();
      return data.products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };

  const fetchSearchIds = async (): Promise<string[]> => {
    try {
      const data = await ApiClient.search(randomChoice(searchTerms));
      return data.products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };

  const fetchFeaturedIds = async (): Promise<string[]> => {
    try {
      const data = await ApiClient.getFeatured();
      return data.featured_products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };

  const fetchCategories = async (): Promise<string[]> => {
    try {
      const data = await ApiClient.getCategories();
      return data.categories.map(c => c.name);
    } catch {
      return ['Electronics'];
    }
  };

  const fetchCategoryIds = async (category: string): Promise<string[]> => {
    try {
      const data = await ApiClient.getCategoryProducts(category);
      return data.products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };

  // ─── Fully Random Journey Simulator ──────────────────────────────────
  //
  // Each journey walks through every major step of the shopping funnel,
  // randomly choosing a branch at each decision point.
  // Every journey always completes to Confirmation.
  //
  //  Welcome
  //    → discovery: Browse | Search | Categories→CategoryBrowse (random)
  //    → maybe Featured (coin flip)
  //    → ProductDetail
  //    → maybe Reviews (coin flip)
  //    → maybe Wishlist (coin flip)
  //    → Cart (add multiple, remove, empty, re-add)
  //    → checkout: CheckoutGuest | CheckoutSignIn (random)
  //    → payment: PaymentCard | PaymentApplePay | PaymentPayPal (random)
  //    → Confirmation

  const runSingleJourney = async () => {
    const nav = navigationRef.current;
    if (!nav || cancelledRef.current) {
      return;
    }

    // Step 1: Welcome
    nav.navigate('Welcome');
    try { await ApiClient.getWelcome(); } catch {}
    await delay(stepDelay);

    // Step 2: Discovery — randomly pick Browse, Search, or Categories
    let productIds: string[];
    let source: string;
    const discoveryChoice = Math.floor(Math.random() * 3);
    switch (discoveryChoice) {
      case 0:
        await navigate('Browse');
        productIds = await fetchBrowseIds();
        source = 'browse';
        break;
      case 1:
        await navigate('Search');
        productIds = await fetchSearchIds();
        source = 'search';
        break;
      default:
        await navigate('Categories');
        const categories = await fetchCategories();
        const category = randomChoice(categories) ?? 'Electronics';
        await navigate('CategoryBrowse', {category});
        productIds = await fetchCategoryIds(category);
        source = 'categories';
        break;
    }

    // Maybe visit Featured (50% chance)
    if (Math.random() < 0.5) {
      await navigate('Featured');
      productIds = await fetchFeaturedIds();
      source = 'featured';
    }

    const pid = randomChoice(productIds) ?? 'prod_a1b2c3';

    // Step 3: ProductDetail
    await navigate('ProductDetail', {source, productId: pid});
    try { await ApiClient.getProduct(pid); } catch {}

    // Maybe visit Reviews (50% chance)
    if (Math.random() < 0.5) {
      await navigate('Reviews', {source, productId: pid});
      try { await ApiClient.getReviews(pid); } catch {}
    }

    // Maybe visit Wishlist (40% chance)
    if (Math.random() < 0.4) {
      await navigate('Wishlist', {productId: pid});
      try { await ApiClient.addToWishlist(pid); } catch {}
    }

    // Step 4: Cart — add multiple items, remove some, view cart
    const cartItemsList: string[] = [pid];
    await navigate('Cart', {productId: pid});
    try { await ApiClient.addToCart(pid); } catch {}

    // Add 1-3 more random products
    const extraCount = 1 + Math.floor(Math.random() * 3);
    for (let i = 0; i < extraCount; i++) {
      const extraPid = randomChoice(productIds) ?? 'prod_a1b2c3';
      cartItemsList.push(extraPid);
      try { await ApiClient.addToCart(extraPid, 1 + Math.floor(Math.random() * 3)); } catch {}
      await delay(stepDelay);
    }

    // View the cart
    try { await ApiClient.getCart(); } catch {}
    await delay(stepDelay);

    // Maybe remove an item (60% chance)
    if (Math.random() < 0.6 && cartItemsList.length > 1) {
      const removeIdx = Math.floor(Math.random() * cartItemsList.length);
      const removePid = cartItemsList.splice(removeIdx, 1)[0];
      try { await ApiClient.deleteCartItem(removePid); } catch {}
      await delay(stepDelay);
    }

    // Maybe empty cart and re-add (20% chance)
    if (Math.random() < 0.2) {
      for (const item of cartItemsList) {
        try { await ApiClient.deleteCartItem(item); } catch {}
        await delay(stepDelay);
      }
      cartItemsList.length = 0;
      const rePid = randomChoice(productIds) ?? 'prod_a1b2c3';
      cartItemsList.push(rePid);
      try { await ApiClient.addToCart(rePid); } catch {}
      await delay(stepDelay);
    }

    // Maybe remove and re-add same item (30% chance)
    if (Math.random() < 0.3 && cartItemsList.length > 0) {
      const flippedPid = randomChoice(cartItemsList);
      try { await ApiClient.deleteCartItem(flippedPid); } catch {}
      await delay(stepDelay);
      try { await ApiClient.addToCart(flippedPid, 1 + Math.floor(Math.random() * 5)); } catch {}
      await delay(stepDelay);
    }

    // View cart one more time before checkout
    try { await ApiClient.getCart(); } catch {}
    await delay(stepDelay);

    const checkoutPid = cartItemsList[cartItemsList.length - 1] ?? pid;

    // Step 5: Checkout — randomly pick Guest or SignIn
    let checkoutSession = '';
    if (Math.random() < 0.5) {
      await navigate('CheckoutGuest', {productId: checkoutPid});
      try { checkoutSession = (await ApiClient.checkoutGuest()).checkout_session; } catch {}
    } else {
      await navigate('CheckoutSignIn', {productId: checkoutPid});
      try { checkoutSession = (await ApiClient.checkoutSignIn()).checkout_session; } catch {}
    }

    // Step 6: Payment — randomly pick Card, ApplePay, or PayPal
    let orderId = '';
    const paymentChoice = Math.floor(Math.random() * 3);
    switch (paymentChoice) {
      case 0:
        await navigate('PaymentCard', {checkoutSession});
        try { orderId = (await ApiClient.payCard(checkoutSession)).order_id; } catch {}
        break;
      case 1:
        await navigate('PaymentApplePay', {checkoutSession});
        try { orderId = (await ApiClient.payApplePay(checkoutSession)).order_id; } catch {}
        break;
      default:
        await navigate('PaymentPayPal', {checkoutSession});
        try { orderId = (await ApiClient.payPayPal(checkoutSession)).order_id; } catch {}
        break;
    }

    // Step 7: Confirmation
    await navigate('Confirmation', {orderId});
    try { await ApiClient.getConfirmation(orderId); } catch {}
  };

  const runSimulation = async (runs: number, infinite: boolean) => {
    cancelledRef.current = false;
    setState({
      isSimulating: true,
      currentRun: 0,
      totalRuns: runs,
      isInfinite: infinite,
    });
    progressRef.current = {currentRun: 0, totalRuns: runs};

    ScreenLogger.logSimulationStart(runs);

    let currentRun = 0;
    while ((infinite || currentRun < runs) && !cancelledRef.current) {
      currentRun++;
      setState(prev => ({...prev, currentRun}));
      progressRef.current = {...progressRef.current, currentRun};
      ScreenLogger.logDebug('journey_start', {
        run: String(currentRun),
        total: infinite ? 'infinite' : String(runs),
      });
      await runSingleJourney();
      if (!cancelledRef.current) {
        ScreenLogger.logDebug('journey_complete', {run: String(currentRun)});
      }
    }

    ScreenLogger.logSimulationEnd(currentRun);

    if (navigationRef.current) {
      navigationRef.current.navigate('Welcome');
    }

    setState({
      isSimulating: false,
      currentRun: 0,
      totalRuns: 0,
      isInfinite: false,
    });
    progressRef.current = {currentRun: 0, totalRuns: 0};
  };

  const startSimulation = useCallback((runs: number) => {
    runSimulation(runs, false);
  }, []);

  const startInfiniteSimulation = useCallback(() => {
    runSimulation(Infinity, true);
  }, []);

  const cancelSimulation = useCallback(() => {
    cancelledRef.current = true;
    ScreenLogger.logWarning('simulation_cancelled', {
      completed_runs: String(progressRef.current.currentRun),
      total_runs: String(progressRef.current.totalRuns),
    });
  }, []);

  return (
    <SimulationContext.Provider
      value={{
        ...state,
        startSimulation,
        startInfiniteSimulation,
        cancelSimulation,
        setNavigationRef,
      }}>
      {children}
    </SimulationContext.Provider>
  );
};
