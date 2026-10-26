import React, {createContext, useContext, useState, useRef, useCallback} from 'react';
import type {NavigationContainerRef} from '@react-navigation/native';
import type {RootStackParamList} from '../navigation/types';
import {ScreenLogger, type Span, type SpanResult} from '../utils/logger';
import {ApiClient} from '../api/ApiClient';
import {
  SimVariant,
  VARIANT_PERSONAS,
  applyVariant,
  type ChaosState,
} from '../sim/variants';
import {CRASHES, triggerAnr, triggerForceQuit} from '../sim/crashes';
import {JourneyEngine, type JourneyAdapter} from '../sim/journeyEngine';
import {specJourney} from '../generated/specJourney';
import {SpecEvents, SpecFields, SpecScreens} from '../generated/specConstants';

const ANR_BLOCK_DURATION_MS = 15000;
const STEP_DELAY_MS = 50;

// Cardinality demo search terms (personas.yaml sim_data.search_terms).
const SEARCH_TERMS = [
  'headphones', 'jacket', 'running shoes', 'laptop', 'watch',
  'camera', 'speaker', 'backpack', 'tablet', 'sneakers',
];

// Spec screen id -> this app's route key (SpecScreens.<id>.platformRoute).
const ROUTE_BY_SCREEN_ID = new Map<string, string>(
  Object.values(SpecScreens).map(s => [s.id, s.platformRoute]),
);

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
  // seed: 0..2^31-1; a random one is drawn when omitted.
  startSimulation: (runs: number, seed?: number) => void;
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

const delay = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));
const newSimSeed = () => Math.floor(Math.random() * 2147483647);

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
  const chaosRef = useRef<ChaosState>({crashLoopEnabled, anrAEnabled, forceQuitEnabled, slowModeEnabled});

  const navigationRef = useRef<NavigationContainerRef<RootStackParamList> | null>(null);
  const cancelledRef = useRef(false);
  const progressRef = useRef({currentRun: 0, totalRuns: 0});
  const crashIndexRef = useRef(0);
  const simSeedRef = useRef(0);

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

  const setSlowMode = useCallback(
    (enabled: boolean) => {
      chaosRef.current = {...chaosRef.current, slowModeEnabled: enabled};
      setSlowModeState(enabled);
      reapplyFlags();
    },
    [reapplyFlags],
  );

  const setSupportLog = useCallback((enabled: boolean) => {
    setSupportLogState(enabled);
    ScreenLogger.addField(SpecFields.supportlog, String(enabled));
  }, []);

  const stopCrashLoop = useCallback(() => {
    chaosRef.current = {...chaosRef.current, crashLoopEnabled: false};
    setCrashLoopState(false);
    reapplyFlags();
    ScreenLogger.logInfo(SpecEvents.crashLoopStopped);
  }, [reapplyFlags]);

  const nextCrashName = useCallback(
    () => CRASHES[crashIndexRef.current % CRASHES.length].name,
    [],
  );

  // ── Journey adapter ──────────────────────────────────────────────────────────
  // The journey itself is data (spec/journey.yaml), interpreted by JourneyEngine
  // identically on every platform. This keeps only what is React Native specific:
  // navigation, the API client, the SDK calls and how each fault physically happens.
  const callApi = async (endpoint: string, a: Record<string, string>): Promise<unknown> => {
    switch (endpoint) {
      case 'welcome': return ApiClient.getWelcome();
      case 'browse': return ApiClient.getBrowse();
      case 'search': return ApiClient.search(a.q ?? '');
      case 'featured': return ApiClient.getFeatured();
      case 'categories': return ApiClient.getCategories();
      case 'category_products': return ApiClient.getCategoryProducts(a.category ?? '');
      case 'product': return ApiClient.getProduct(a.id ?? '');
      case 'reviews': return ApiClient.getReviews(a.id ?? '');
      case 'cart_get': return ApiClient.getCart();
      case 'cart_add': return ApiClient.addToCart(a.product_id ?? '', Number(a.quantity) || 1);
      case 'cart_delete': return ApiClient.deleteCartItem(a.id ?? '');
      case 'wishlist_add': return ApiClient.addToWishlist(a.product_id ?? '');
      case 'checkout_guest': return ApiClient.checkoutGuest();
      case 'checkout_signin': return ApiClient.checkoutSignIn();
      case 'pay_card': return ApiClient.payCard(a.checkout_session ?? '', a.card_last4 ?? '4242');
      case 'pay_apple_pay': return ApiClient.payApplePay(a.checkout_session ?? '');
      case 'pay_paypal': return ApiClient.payPayPal(a.checkout_session ?? '');
      case 'pay_android_pay': return ApiClient.payAndroidPay(a.checkout_session ?? '');
      case 'confirmation': return ApiClient.getConfirmation(a.id ?? '');
      default: throw new Error(`unknown endpoint ${endpoint}`);
    }
  };

  // Fires the next crash-loop crash. The engine already set crash_journey_point.
  const fireCrash = () => {
    const idx = crashIndexRef.current % CRASHES.length;
    const {name, fn} = CRASHES[idx];
    crashIndexRef.current = (idx + 1) % CRASHES.length;
    ScreenLogger.addField(SpecFields.crashKind, name);
    ScreenLogger.addField(SpecFields.crashContext, 'foreground');
    ScreenLogger.logWarning(`about_to_crash: ${name} (context=foreground)`);
    cancelledRef.current = true;
    setTimeout(() => fn(), 300);
  };

  const journeyAdapter: JourneyAdapter = {
    isCancelled: () => cancelledRef.current,
    // The RN SDK has no startNewSession (spec D-SES-1: optional on RN).
    startNewSession: () => {},
    applyExposures: () => applyVariant(variantRef.current, chaosRef.current),
    setEntity: entity => ScreenLogger.setEntityId(entity),
    delay,
    navigate: async (screen, args) => {
      const nav = navigationRef.current;
      const route = ROUTE_BY_SCREEN_ID.get(screen);
      if (!nav || !route) {
        return;
      }
      if (route === SpecScreens.welcome.platformRoute) {
        nav.reset({index: 0, routes: [{name: 'Welcome'}]});
      } else {
        nav.navigate(route as never, args as never);
      }
    },
    callApi: async (endpoint, args) => {
      try {
        return (await callApi(endpoint, args)) as Record<string, unknown>;
      } catch {
        return null;
      }
    },
    log: (level, event, fields) => {
      switch (level) {
        case 'error': return ScreenLogger.logError(event, fields);
        case 'warning': return ScreenLogger.logWarning(event, fields);
        case 'debug': return ScreenLogger.logDebug(event, fields);
        case 'trace': return ScreenLogger.logTrace(event, fields);
        default: return ScreenLogger.logInfo(event, fields);
      }
    },
    // Spans are the paired-log shim; the parent handle's id is recorded as parent_span_id.
    startSpan: (name, parent, fields) =>
      ScreenLogger.startSpan(name, fields, (parent as Span | undefined)?.id),
    endSpan: (handle, result, fields) => (handle as Span).end(result as SpanResult, fields),
    addField: (key, value) => ScreenLogger.addField(key, value),
    injectFault: id => {
      if (id === 'force_quit') {
        cancelledRef.current = true;
        triggerForceQuit();
      } else if (id === 'anr') {
        // Main thread is now frozen; spans intentionally left open.
        triggerAnr(ANR_BLOCK_DURATION_MS);
      }
    },
    fireCrash,
  };

  // One engine per simulator: its fault counters persist across journeys.
  const engineRef = useRef<JourneyEngine | null>(null);
  if (!engineRef.current) {
    engineRef.current = new JourneyEngine(specJourney, journeyAdapter);
  }

  const runSingleJourney = async (runNumber: number, isInfinite: boolean) => {
    if (!navigationRef.current || cancelledRef.current) {
      return;
    }
    const chaos = chaosRef.current;
    const toggles = [
      ...(chaos.crashLoopEnabled ? ['crash_loop'] : []),
      ...(chaos.anrAEnabled ? ['anr'] : []),
      ...(chaos.forceQuitEnabled ? ['force_quit'] : []),
    ];
    const persona = VARIANT_PERSONAS[variantRef.current];
    const outcome = await engineRef.current!.run(persona, runNumber, simSeedRef.current, toggles, isInfinite);
    console.log(`journey ${runNumber} (${persona}, seed=${simSeedRef.current}): ${outcome}`);
  };

  // ── Simulation loops ───────────────────────────────────────────────────────────
  const beginLoop = (totalRuns: number, infinite: boolean) => {
    cancelledRef.current = false;
    setState({isSimulating: true, currentRun: 0, totalRuns, isInfinite: infinite});
    progressRef.current = {currentRun: 0, totalRuns};
  };

  const markRun = (run: number) => {
    setState(prev => ({...prev, currentRun: run}));
    progressRef.current = {...progressRef.current, currentRun: run};
  };

  // Runs journeys until `runs` is reached (or forever) or the loop is cancelled; returns the
  // number started. beforeRun lets the A/B loop switch persona.
  const runJourneys = async (
    runs: number,
    infinite: boolean,
    seed: number | undefined,
    beforeRun?: (run: number) => void,
  ): Promise<number> => {
    simSeedRef.current = seed ?? newSimSeed();
    let run = 0;
    while ((infinite || run < runs) && !cancelledRef.current) {
      run++;
      beforeRun?.(run);
      markRun(run);
      await runSingleJourney(run, infinite);
      await delay(STEP_DELAY_MS);
    }
    return run;
  };

  const finishLoop = () => {
    if (navigationRef.current && !cancelledRef.current) {
      navigationRef.current.reset({index: 0, routes: [{name: 'Welcome'}]});
    }
    setState({isSimulating: false, currentRun: 0, totalRuns: 0, isInfinite: false});
    progressRef.current = {currentRun: 0, totalRuns: 0};
  };

  const startSimulation = useCallback((runs: number, seed?: number) => {
    const loop = async () => {
      beginLoop(runs, false);
      ScreenLogger.logSimulationStart(runs);
      const run = await runJourneys(runs, false, seed);
      ScreenLogger.logSimulationEnd(run);
      finishLoop();
    };
    loop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const startInfiniteSimulation = useCallback(() => {
    const loop = async () => {
      beginLoop(Infinity, true);
      ScreenLogger.logInfo(SpecEvents.infiniteSimulationStart);
      const run = await runJourneys(Infinity, true, undefined);
      ScreenLogger.logInfo(SpecEvents.infiniteSimulationEnd, {[SpecFields.totalRuns]: String(run)});
      finishLoop();
    };
    loop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A/B rotation: personas interleave per run (Control, A, B, Control, ...) so every run is
  // a flag transition (spec D-PER-3).
  const startAbSimulation = useCallback((runsEach: number) => {
    const loop = async () => {
      const total = runsEach * 3;
      const order = [SimVariant.Control, SimVariant.VariantA, SimVariant.VariantB];
      beginLoop(total, false);
      ScreenLogger.logInfo(SpecEvents.abSimulationStart, {[SpecFields.runsEach]: String(runsEach)});
      const count = await runJourneys(total, false, undefined, run => setVariant(order[(run - 1) % 3]));
      ScreenLogger.logInfo(SpecEvents.abSimulationEnd, {[SpecFields.totalRuns]: String(count)});
      finishLoop();
    };
    loop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [setVariant]);

  // Cardinality demo: hammer the inventory endpoint with unique session segments.
  const startCardinalitySimulation = useCallback(() => {
    const loop = async () => {
      beginLoop(Infinity, true);
      ScreenLogger.logInfo(SpecEvents.cardinalitySimulationStart);
      let count = 0;
      while (!cancelledRef.current) {
        count++;
        markRun(count);
        try {
          await ApiClient.inventoryLookup(SEARCH_TERMS[Math.floor(Math.random() * SEARCH_TERMS.length)]);
        } catch {}
        await delay(STEP_DELAY_MS);
      }
      ScreenLogger.logInfo(SpecEvents.cardinalitySimulationEnd, {[SpecFields.totalRuns]: String(count)});
      finishLoop();
    };
    loop();
  }, []);

  const cancelSimulation = useCallback(() => {
    cancelledRef.current = true;
    ScreenLogger.logInfo(SpecEvents.simulationCancelled, {
      [SpecFields.completedRuns]: String(progressRef.current.currentRun),
      [SpecFields.totalRuns]: String(progressRef.current.totalRuns),
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
