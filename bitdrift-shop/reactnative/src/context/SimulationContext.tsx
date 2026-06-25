import React, {createContext, useContext, useState, useRef, useCallback} from 'react';
import type {NavigationContainerRef} from '@react-navigation/native';
import type {RootStackParamList} from '../navigation/types';
import {ScreenLogger, type Span} from '../utils/logger';
import {ApiClient} from '../api/ApiClient';
import {
  SimVariant,
  VARIANT_LABELS,
  VARIANT_PROFILES,
  DEMO_ENTITIES,
  applyVariant,
  type ChaosState,
} from '../sim/variants';
import {CRASHES, triggerAnr, triggerForceQuit} from '../sim/crashes';

// ─── Chaos / ANR / Force-quit constants (ported from SimulationManager.kt) ──────
const ANR_PROBABILITY = 0.25;
const ANR_FORCE_AFTER_ELIGIBLE_GUEST_JOURNEYS = 6;
const ANR_BLOCK_DURATION_MS = 15000;
const ANR_TARGET_SCREEN_NAME = 'CheckoutGuest';

const FORCE_QUIT_PROBABILITY = 0.6;
const FORCE_QUIT_FORCE_AFTER_JOURNEYS = 3;
const FORCE_QUIT_TARGET_SCREEN = 'ProductDetail';

const PAYMENT_RETRY_PROBABILITY = 0.5;
const STEP_DELAY_MS = 50;

type PaymentMethod = 'card' | 'applePay' | 'payPal' | 'androidPay';

// payment_method values logged on success, matching the Android event values.
const PAYMENT_METHOD_EVENT: Record<PaymentMethod, string> = {
  card: 'visa',
  applePay: 'apple_pay',
  payPal: 'paypal',
  androidPay: 'android_pay',
};

type SimulationState = {
  isSimulating: boolean;
  currentRun: number;
  totalRuns: number;
  isInfinite: boolean;
};

type SimulationContextType = SimulationState & {
  // Variant
  activeVariant: SimVariant;
  setVariant: (variant: SimVariant) => void;
  // Chaos toggles
  crashLoopEnabled: boolean;
  anrAEnabled: boolean;
  forceQuitEnabled: boolean;
  slowModeEnabled: boolean;
  supportLogEnabled: boolean;
  setCrashLoop: (enabled: boolean) => void;
  setAnrA: (enabled: boolean) => void;
  setForceQuit: (enabled: boolean) => void;
  setSlowMode: (enabled: boolean) => void;
  setSupportLog: (enabled: boolean) => void;
  stopCrashLoop: () => void;
  nextCrashName: () => string;
  // Actions
  startSimulation: (runs: number) => void;
  startInfiniteSimulation: () => void;
  startAbSimulation: (runsEach: number) => void;
  startCardinalitySimulation: () => void;
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

const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
const rand = () => Math.random();
const randInt = (min: number, max: number) => min + Math.floor(Math.random() * (max - min + 1));
const randomChoice = <T,>(options: T[]): T => options[Math.floor(Math.random() * options.length)];

const SEARCH_TERMS = [
  'headphones', 'jacket', 'running shoes', 'laptop', 'watch',
  'camera', 'speaker', 'backpack', 'tablet', 'sneakers',
];

export const SimulationProvider: React.FC<{children: React.ReactNode}> = ({children}) => {
  const [state, setState] = useState<SimulationState>({
    isSimulating: false,
    currentRun: 0,
    totalRuns: 0,
    isInfinite: false,
  });

  // Variant + chaos as React state (drives Advanced screen UI) mirrored into refs
  // (read by the async simulation loop so it always sees the latest values).
  const [activeVariant, setActiveVariantState] = useState<SimVariant>(SimVariant.Control);
  const [crashLoopEnabled, setCrashLoopState] = useState(false);
  const [anrAEnabled, setAnrAState] = useState(false);
  const [forceQuitEnabled, setForceQuitState] = useState(false);
  const [slowModeEnabled, setSlowModeState] = useState(false);
  const [supportLogEnabled, setSupportLogState] = useState(false);

  const variantRef = useRef(activeVariant);
  const chaosRef = useRef<ChaosState>({crashLoopEnabled, anrAEnabled, forceQuitEnabled});

  const navigationRef = useRef<NavigationContainerRef<RootStackParamList> | null>(null);
  const cancelledRef = useRef(false);
  const progressRef = useRef({currentRun: 0, totalRuns: 0});
  const crashIndexRef = useRef(0);
  // Forced-cadence counters for infinite-mode chaos injection.
  const eligibleAnrGuestRef = useRef(0);
  const eligibleForceQuitRef = useRef(0);

  const setNavigationRef = useCallback((ref: NavigationContainerRef<RootStackParamList>) => {
    navigationRef.current = ref;
  }, []);

  // ── Variant / chaos setters: update state, refs, and re-broadcast feature flags ──
  const reapplyFlags = useCallback(() => {
    applyVariant(variantRef.current, chaosRef.current);
  }, []);

  const setVariant = useCallback(
    (variant: SimVariant) => {
      variantRef.current = variant;
      setActiveVariantState(variant);
      // ANR-A is only valid for Variant A; auto-disable otherwise (matches Android).
      if (variant !== SimVariant.VariantA && chaosRef.current.anrAEnabled) {
        chaosRef.current = {...chaosRef.current, anrAEnabled: false};
        setAnrAState(false);
      }
      reapplyFlags();
    },
    [reapplyFlags],
  );

  const setCrashLoop = useCallback(
    (enabled: boolean) => {
      chaosRef.current = {...chaosRef.current, crashLoopEnabled: enabled};
      setCrashLoopState(enabled);
      reapplyFlags();
    },
    [reapplyFlags],
  );

  const setAnrA = useCallback(
    (enabled: boolean) => {
      chaosRef.current = {...chaosRef.current, anrAEnabled: enabled};
      setAnrAState(enabled);
      reapplyFlags();
    },
    [reapplyFlags],
  );

  const setForceQuit = useCallback(
    (enabled: boolean) => {
      chaosRef.current = {...chaosRef.current, forceQuitEnabled: enabled};
      setForceQuitState(enabled);
      reapplyFlags();
    },
    [reapplyFlags],
  );

  const setSlowMode = useCallback((enabled: boolean) => setSlowModeState(enabled), []);

  const setSupportLog = useCallback((enabled: boolean) => {
    setSupportLogState(enabled);
    ScreenLogger.addField('supportlog', String(enabled));
  }, []);

  const stopCrashLoop = useCallback(() => {
    chaosRef.current = {...chaosRef.current, crashLoopEnabled: false};
    setCrashLoopState(false);
    reapplyFlags();
    ScreenLogger.logInfo('crash_loop_stopped');
  }, [reapplyFlags]);

  const nextCrashName = useCallback(
    () => CRASHES[crashIndexRef.current % CRASHES.length].name,
    [],
  );

  // ── Navigation helper ────────────────────────────────────────────────────────
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
    await delay(STEP_DELAY_MS);
  };

  // ── API fetch helpers (best-effort, never throw out of the loop) ───────────────
  const fetchBrowseIds = async (): Promise<string[]> => {
    try {
      return (await ApiClient.getBrowse()).products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };
  const fetchSearchIds = async (): Promise<string[]> => {
    try {
      return (await ApiClient.search(randomChoice(SEARCH_TERMS))).products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };
  const fetchFeaturedIds = async (): Promise<string[]> => {
    try {
      return (await ApiClient.getFeatured()).featured_products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };
  const fetchCategories = async (): Promise<string[]> => {
    try {
      return (await ApiClient.getCategories()).categories.map(c => c.name);
    } catch {
      return ['Electronics'];
    }
  };
  const fetchCategoryIds = async (category: string): Promise<string[]> => {
    try {
      return (await ApiClient.getCategoryProducts(category)).products.map(p => p.id);
    } catch {
      return ['prod_a1b2c3'];
    }
  };

  // ── Chaos injection ────────────────────────────────────────────────────────────
  const maybeInjectForceQuit = (isInfinite: boolean): boolean => {
    if (!chaosRef.current.forceQuitEnabled) {
      return false;
    }
    eligibleForceQuitRef.current += 1;
    const randomHit = rand() < FORCE_QUIT_PROBABILITY;
    const forcedHit =
      isInfinite && eligibleForceQuitRef.current >= FORCE_QUIT_FORCE_AFTER_JOURNEYS;
    if (!randomHit && !forcedHit) {
      return false;
    }
    eligibleForceQuitRef.current = 0;
    ScreenLogger.logError('force_quit_injected', {
      force_quit_enabled: 'true',
      force_quit_screen: FORCE_QUIT_TARGET_SCREEN,
      variant: VARIANT_LABELS[variantRef.current],
      trigger_mode: forcedHit ? 'forced_infinite' : 'random',
    });
    triggerForceQuit();
    return true;
  };

  const maybeInjectGuestAnr = (isGuest: boolean, isInfinite: boolean): boolean => {
    if (!chaosRef.current.anrAEnabled || variantRef.current !== SimVariant.VariantA || !isGuest) {
      return false;
    }
    eligibleAnrGuestRef.current += 1;
    const randomHit = rand() < ANR_PROBABILITY;
    const forcedHit =
      isInfinite && eligibleAnrGuestRef.current >= ANR_FORCE_AFTER_ELIGIBLE_GUEST_JOURNEYS;
    if (!randomHit && !forcedHit) {
      return false;
    }
    eligibleAnrGuestRef.current = 0;
    ScreenLogger.logError('guest_anr_injected', {
      anr_a_enabled: 'true',
      journey_type: 'guest',
      anr_screen_name: ANR_TARGET_SCREEN_NAME,
      variant: VARIANT_LABELS[variantRef.current],
      trigger_mode: forcedHit ? 'forced_infinite' : 'random',
    });
    triggerAnr(ANR_BLOCK_DURATION_MS);
    return true;
  };

  const maybeFireCrash = () => {
    if (!chaosRef.current.crashLoopEnabled) {
      return;
    }
    const idx = crashIndexRef.current % CRASHES.length;
    const {name, fn} = CRASHES[idx];
    crashIndexRef.current = (idx + 1) % CRASHES.length;
    ScreenLogger.addField('crash_kind', name);
    ScreenLogger.logWarning(`about_to_crash: ${name} (idx=${idx})`, {crash_kind: name});
    cancelledRef.current = true;
    setTimeout(() => fn(), 300);
  };

  const pickPaymentMethod = (variant: SimVariant): PaymentMethod => {
    const w = VARIANT_PROFILES[variant].paymentWeights;
    const roll = rand();
    if (roll < w.card) {
      return 'card';
    }
    if (roll < w.card + w.applePay) {
      return 'applePay';
    }
    if (roll < w.card + w.applePay + w.payPal) {
      return 'payPal';
    }
    return 'androidPay';
  };

  const paymentScreenFor = (m: PaymentMethod): keyof RootStackParamList =>
    m === 'card'
      ? 'PaymentCard'
      : m === 'applePay'
      ? 'PaymentApplePay'
      : m === 'payPal'
      ? 'PaymentPayPal'
      : 'PaymentAndroidPay';

  const payApi = async (m: PaymentMethod, session: string): Promise<string> => {
    try {
      switch (m) {
        case 'card':
          return (await ApiClient.payCard(session)).order_id;
        case 'applePay':
          return (await ApiClient.payApplePay(session)).order_id;
        case 'payPal':
          return (await ApiClient.payPayPal(session)).order_id;
        case 'androidPay':
          return (await ApiClient.payAndroidPay(session)).order_id;
      }
    } catch {
      return '';
    }
  };

  // ── A single journey ─────────────────────────────────────────────────────────
  const runSingleJourney = async (runNumber: number, isInfinite: boolean) => {
    const nav = navigationRef.current;
    if (!nav || cancelledRef.current) {
      return;
    }

    const variant = variantRef.current;
    const profile = VARIANT_PROFILES[variant];
    const variantLabel = VARIANT_LABELS[variant];
    const entity = DEMO_ENTITIES[(runNumber - 1) % DEMO_ENTITIES.length];

    // New session per journey is not available in the RN SDK (see logger.ts notes);
    // re-apply variant flags + entity on each journey instead, then mark the boundary.
    applyVariant(variant, chaosRef.current);
    ScreenLogger.setEntityId(entity);
    ScreenLogger.logInfo('journey_started', {run: String(runNumber), variant: variantLabel});

    const journeySpan: Span = ScreenLogger.startSpan('journey', {
      variant: variantLabel,
      entity,
    });
    const discoverySpan: Span = ScreenLogger.startSpan(
      'product_discovery',
      {variant: variantLabel},
      journeySpan.id,
    );

    // Welcome
    nav.navigate('Welcome');
    try {
      await ApiClient.getWelcome();
    } catch {}
    await delay(STEP_DELAY_MS);

    // Discovery — biased by variant
    let productIds: string[];
    let source: string;
    const dRoll = rand();
    const dChoice =
      dRoll < profile.discoveryBrowseMax ? 0 : dRoll < profile.discoverySearchMax ? 1 : 2;
    if (dChoice === 0) {
      await navigate('Browse');
      productIds = await fetchBrowseIds();
      source = 'browse';
    } else if (dChoice === 1) {
      await navigate('Search');
      productIds = await fetchSearchIds();
      source = 'search';
    } else {
      await navigate('Categories');
      const category = randomChoice(await fetchCategories()) ?? 'Electronics';
      await navigate('CategoryBrowse', {category});
      productIds = await fetchCategoryIds(category);
      source = 'categories';
    }

    if (rand() < profile.featuredProb) {
      await navigate('Featured');
      productIds = await fetchFeaturedIds();
      source = 'featured';
    }

    const pid = randomChoice(productIds) ?? 'prod_a1b2c3';

    // ProductDetail — force-quit injection point
    await navigate('ProductDetail', {source, productId: pid});
    try {
      await ApiClient.getProduct(pid);
    } catch {}
    if (maybeInjectForceQuit(isInfinite)) {
      journeySpan.end('canceled', {reason: 'force_quit'});
      return;
    }

    if (rand() < profile.reviewsProb) {
      await navigate('Reviews', {source, productId: pid});
      try {
        await ApiClient.getReviews(pid);
      } catch {}
    }

    if (rand() < profile.wishlistProb) {
      await navigate('Wishlist', {productId: pid});
      try {
        await ApiClient.addToWishlist(pid);
      } catch {}
      ScreenLogger.logInfo('add_to_wishlist', {product_id: pid, source_screen: source});
    }

    // Cart — first add, then variant-driven mutations
    const cart: string[] = [pid];
    await navigate('Cart', {productId: pid});
    try {
      await ApiClient.addToCart(pid);
    } catch {}
    ScreenLogger.logInfo('add_to_cart', {product_id: pid, source_screen: source});
    discoverySpan.end('success', {source, product_id: pid});

    const extra = randInt(profile.extraCartMin, profile.extraCartMax);
    for (let i = 0; i < extra; i++) {
      const epid = randomChoice(productIds) ?? 'prod_a1b2c3';
      cart.push(epid);
      try {
        await ApiClient.addToCart(epid, randInt(1, 3));
      } catch {}
      ScreenLogger.logInfo('add_to_cart', {product_id: epid, source_screen: 'cart'});
      await delay(STEP_DELAY_MS);
    }
    try {
      await ApiClient.getCart();
    } catch {}

    if (rand() < profile.removeItemProb && cart.length > 1) {
      const ridx = Math.floor(rand() * cart.length);
      const rpid = cart.splice(ridx, 1)[0];
      try {
        await ApiClient.deleteCartItem(rpid);
      } catch {}
      ScreenLogger.logInfo('cart_item_removed', {product_id: rpid});
      await delay(STEP_DELAY_MS);
    }

    if (rand() < profile.emptyReaddProb) {
      for (const item of cart) {
        try {
          await ApiClient.deleteCartItem(item);
        } catch {}
        ScreenLogger.logInfo('cart_item_removed', {product_id: item});
        await delay(STEP_DELAY_MS);
      }
      cart.length = 0;
      const rpid = randomChoice(productIds) ?? 'prod_a1b2c3';
      cart.push(rpid);
      try {
        await ApiClient.addToCart(rpid);
      } catch {}
      ScreenLogger.logInfo('add_to_cart', {product_id: rpid, source_screen: 'cart'});
    }

    if (rand() < profile.quantityFlipProb && cart.length > 0) {
      const fpid = randomChoice(cart);
      try {
        await ApiClient.deleteCartItem(fpid);
      } catch {}
      try {
        await ApiClient.addToCart(fpid, randInt(1, 5));
      } catch {}
    }
    try {
      await ApiClient.getCart();
    } catch {}

    // Abandon before checkout?
    if (rand() < profile.cartAbandonProb) {
      ScreenLogger.logInfo('cart_abandoned', {
        items_in_cart: String(cart.length),
        variant: variantLabel,
      });
      journeySpan.end('canceled', {reason: 'cart_abandoned'});
      return;
    }

    const checkoutPid = cart[cart.length - 1] ?? pid;

    // Checkout — guest vs signin (ANR-A forces guest for Variant A)
    const isGuest =
      chaosRef.current.anrAEnabled && variant === SimVariant.VariantA
        ? true
        : rand() < profile.guestProb;
    const checkoutType = isGuest ? 'guest' : 'signin';
    const checkoutSpan: Span = ScreenLogger.startSpan(
      'checkout',
      {checkout_type: checkoutType},
      journeySpan.id,
    );

    let session = '';
    if (isGuest) {
      await navigate('CheckoutGuest', {productId: checkoutPid});
      try {
        session = (await ApiClient.checkoutGuest()).checkout_session;
      } catch {}
    } else {
      await navigate('CheckoutSignIn', {productId: checkoutPid});
      try {
        session = (await ApiClient.checkoutSignIn()).checkout_session;
      } catch {}
    }
    ScreenLogger.logInfo('checkout_started', {checkout_type: checkoutType});

    // ANR injection (guest only)
    if (maybeInjectGuestAnr(isGuest, isInfinite)) {
      // Main thread is now frozen; spans intentionally left open.
      return;
    }

    // Checkout dropout?
    if (rand() < profile.checkoutDropoutProb) {
      ScreenLogger.logInfo('checkout_abandoned', {
        checkout_type: checkoutType,
        variant: variantLabel,
      });
      checkoutSpan.end('canceled', {reason: 'checkout_abandoned'});
      journeySpan.end('canceled', {reason: 'checkout_abandoned'});
      return;
    }

    // Payment — pick method, attempt, maybe fail, maybe retry
    let method = pickPaymentMethod(variant);
    const failProb =
      method === 'androidPay' ? profile.androidPayFailProb : profile.paymentFailProb;
    let retried = false;
    let orderId = '';

    await navigate(paymentScreenFor(method), {checkoutSession: session});

    if (rand() < failProb) {
      ScreenLogger.logError('payment_failed', {payment_method: PAYMENT_METHOD_EVENT[method]});
      if (rand() < PAYMENT_RETRY_PROBABILITY) {
        // Retry with a different method.
        const originalMethod = method;
        const alternatives: PaymentMethod[] = (['card', 'applePay', 'payPal'] as PaymentMethod[]).filter(
          m => m !== originalMethod,
        );
        method = randomChoice(alternatives);
        retried = true;
        await navigate(paymentScreenFor(method), {checkoutSession: session});
        orderId = await payApi(method, session);
        ScreenLogger.logInfo('payment_retry', {
          original_method: PAYMENT_METHOD_EVENT[originalMethod],
          retry_method: PAYMENT_METHOD_EVENT[method],
          variant: variantLabel,
        });
      } else {
        // No retry — land on the failure screen and end the journey.
        await navigate('PaymentFailed', {paymentMethod: PAYMENT_METHOD_EVENT[method]});
        checkoutSpan.end('failure', {payment_method: PAYMENT_METHOD_EVENT[method]});
        journeySpan.end('failure', {reason: 'payment_failed'});
        return;
      }
    } else {
      orderId = await payApi(method, session);
    }

    const completedFields: Record<string, string> = {
      payment_method: PAYMENT_METHOD_EVENT[method],
      order_id: orderId,
    };
    if (method === 'card') {
      completedFields.card_last4 = '4242';
    }
    ScreenLogger.logInfo('payment_completed', completedFields);
    checkoutSpan.end('success', {
      payment_method: PAYMENT_METHOD_EVENT[method],
      retried: String(retried),
    });

    // Confirmation
    await navigate('Confirmation', {orderId});
    try {
      await ApiClient.getConfirmation(orderId);
    } catch {}
    ScreenLogger.logInfo('confirmation_reached', {
      _screen_name: 'Confirmation',
      payment_retried: String(retried),
      ...(retried ? {retry_method: PAYMENT_METHOD_EVENT[method]} : {}),
    });
    journeySpan.end('success');

    // Crash loop fires at the very end of the journey.
    maybeFireCrash();
  };

  // ── Simulation loops ───────────────────────────────────────────────────────────
  const runLoop = async (runs: number, infinite: boolean) => {
    cancelledRef.current = false;
    eligibleAnrGuestRef.current = 0;
    eligibleForceQuitRef.current = 0;
    setState({isSimulating: true, currentRun: 0, totalRuns: runs, isInfinite: infinite});
    progressRef.current = {currentRun: 0, totalRuns: runs};

    if (infinite) {
      ScreenLogger.logInfo('infinite_simulation_start');
    } else {
      ScreenLogger.logSimulationStart(runs);
    }

    let run = 0;
    while ((infinite || run < runs) && !cancelledRef.current) {
      run++;
      setState(prev => ({...prev, currentRun: run}));
      progressRef.current = {...progressRef.current, currentRun: run};
      await runSingleJourney(run, infinite);
      await delay(STEP_DELAY_MS);
    }

    if (infinite) {
      ScreenLogger.logInfo('infinite_simulation_end', {total_runs: String(run)});
    } else {
      ScreenLogger.logSimulationEnd(run);
    }
    finishLoop();
  };

  const finishLoop = () => {
    if (navigationRef.current && !cancelledRef.current) {
      navigationRef.current.navigate('Welcome');
    }
    setState({isSimulating: false, currentRun: 0, totalRuns: 0, isInfinite: false});
    progressRef.current = {currentRun: 0, totalRuns: 0};
  };

  const startSimulation = useCallback((runs: number) => {
    runLoop(runs, false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const startInfiniteSimulation = useCallback(() => {
    runLoop(Infinity, true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A/B rotation: runsEach journeys per variant (Control → A → B).
  const startAbSimulation = useCallback((runsEach: number) => {
    const loop = async () => {
      cancelledRef.current = false;
      eligibleAnrGuestRef.current = 0;
      eligibleForceQuitRef.current = 0;
      const total = runsEach * 3;
      setState({isSimulating: true, currentRun: 0, totalRuns: total, isInfinite: false});
      progressRef.current = {currentRun: 0, totalRuns: total};
      ScreenLogger.logInfo('ab_simulation_start', {runs_each: String(runsEach)});

      let count = 0;
      const order = [SimVariant.Control, SimVariant.VariantA, SimVariant.VariantB];
      for (const v of order) {
        if (cancelledRef.current) {
          break;
        }
        setVariant(v);
        for (let i = 0; i < runsEach && !cancelledRef.current; i++) {
          count++;
          setState(prev => ({...prev, currentRun: count}));
          progressRef.current = {...progressRef.current, currentRun: count};
          await runSingleJourney(count, false);
          await delay(STEP_DELAY_MS);
        }
      }
      ScreenLogger.logInfo('ab_simulation_end', {total_runs: String(count)});
      finishLoop();
    };
    loop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [setVariant]);

  // Cardinality demo: hammer the inventory endpoint with unique session segments.
  const startCardinalitySimulation = useCallback(() => {
    const loop = async () => {
      cancelledRef.current = false;
      setState({isSimulating: true, currentRun: 0, totalRuns: Infinity, isInfinite: true});
      progressRef.current = {currentRun: 0, totalRuns: Infinity};
      ScreenLogger.logInfo('cardinality_simulation_start');
      let count = 0;
      while (!cancelledRef.current) {
        count++;
        setState(prev => ({...prev, currentRun: count}));
        progressRef.current = {...progressRef.current, currentRun: count};
        try {
          await ApiClient.inventoryLookup(randomChoice(SEARCH_TERMS));
        } catch {}
        await delay(STEP_DELAY_MS);
      }
      ScreenLogger.logInfo('cardinality_simulation_end', {total_runs: String(count)});
      finishLoop();
    };
    loop();
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
        stopCrashLoop,
        nextCrashName,
        startSimulation,
        startInfiniteSimulation,
        startAbSimulation,
        startCardinalitySimulation,
        cancelSimulation,
        setNavigationRef,
      }}>
      {children}
    </SimulationContext.Provider>
  );
};
