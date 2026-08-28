import React, {useRef, useEffect} from 'react';
import {View, StyleSheet, StatusBar, Platform, LogBox} from 'react-native';
import {NavigationContainer, NavigationContainerRef} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {SafeAreaProvider} from 'react-native-safe-area-context';

// This demo generates errors on purpose — simulated payment failures, cart/checkout
// failures, and the injected ANR / force-quit / crash faults — so that the bitdrift
// dashboard has real error capture to show. Every one of them goes through
// ScreenLogger.logError, which calls console.error, which makes RN's LogBox throw a
// blocking banner over the app. During a demo that banner is pure noise.
//
// Matching the logger's own "[ERROR] / [WARNING] <event> | k=v" prefix rather than
// listing event names: there are eight logError call sites and naming them one at a
// time is whack-a-mole (payment_failed was suppressed first and api_request_failed
// promptly took its place). Warnings are covered too — api_response_error and
// memory_pressure are demo signals in the same way, and they raise the yellow LogBox
// notice. Only this app's own logger uses that prefix, so warnings and errors raised
// by React Native itself still surface normally. Anchored with ^ so a framework
// message that merely quotes "[ERROR] " somewhere in its text is not swallowed too.
//
// This hides only the popup. console.error still fires, so the line is still in
// logcat / the iOS unified log, and bdError() still ships it to bitdrift — the
// dashboard-side demonstration of error capture is unaffected. If you see repeated
// api_request_failed there, the backend is genuinely unreachable; see the README's
// Troubleshooting section.
LogBox.ignoreLogs([/^\[(ERROR|WARNING)\]\s/]);

// Workshop 1 — SDK Initialization
// Import and initialise the bitdrift Capture SDK as early as possible so all
// subsequent logs, screen views, and network events are captured.
import {init, SessionStrategy, addField, logAppLaunchTTI} from '@bitdrift/react-native';

import {SimulationProvider, useSimulation} from './src/context/SimulationContext';
import {SimulationOverlay} from './src/components';
import {Colors} from './src/utils/colors';
import {ScreenLogger} from './src/utils/logger';
import {startLifecycleLogging} from './src/utils/appLifecycle';
import {BITDRIFT_API_KEY, BITDRIFT_API_HOST, APP_VARIANT} from './src/config';
import type {RootStackParamList} from './src/navigation/types';

import {
  WelcomeScreen,
  BrowseScreen,
  SearchScreen,
  FeaturedScreen,
  CategoriesScreen,
  CategoryBrowseScreen,
  ProductDetailScreen,
  ReviewsScreen,
  CartScreen,
  WishlistScreen,
  CheckoutGuestScreen,
  CheckoutSignInScreen,
  PaymentCardScreen,
  PaymentApplePayScreen,
  PaymentPayPalScreen,
  PaymentAndroidPayScreen,
  PaymentFailedScreen,
  ConfirmationScreen,
  AdvancedScreen,
} from './src/screens';

// Capture wall-clock time at module evaluation for TTI measurement.
const APP_START_TIME = Date.now();

// Initialise with an activity-based session so new sessions begin after a
// period of inactivity, matching how iOS/Android demos are configured.
// API key is loaded from src/config.ts (reads BITDRIFT_API_KEY from .env).
const SDK_INIT_STARTED_AT = Date.now();
init(BITDRIFT_API_KEY, SessionStrategy.Activity, {
  url: BITDRIFT_API_HOST,
  // Automatic HTTP capture. iOS only — this flag instruments NSURLSession, which is
  // what RN's fetch uses. Android ignores it and needs the io.bitdrift.capture-plugin
  // Gradle plugin instead (see android/app/build.gradle).
  //
  // Without this, the SDK emits no NETWORK_RESPONSE events, and every network-based
  // Instant Insight — API Latency by Endpoint, Network Success Rate, Requests by
  // Endpoint — stays empty. ApiClient's own `api_response` logs are ordinary
  // structured logs and do not satisfy those OOTB matches. It is also what makes the
  // `x-capture-path-template` header ApiClient already sends meaningful; with capture
  // off the header is inert.
  enableNetworkInstrumentation: true,
  crashReporting: {
    UNSTABLE_enableJsErrors: true,
  },
});
// Duration of init() itself, reported below as the `sdk_init` child of `app_cold_start`.
// Cannot be logged here: the SDK is only just up, and the span has to be back-dated.
const SDK_INIT_DURATION_MS = Date.now() - SDK_INIT_STARTED_AT;

// Global Fields
// These fields are automatically attached to every log, span, and network
// event so dashboards can slice data by variant or platform. app_variant matches
// the Android app's value ("sdk-demo") so both platforms slice identically.
addField('app_variant', APP_VARIANT);
addField('platform', Platform.OS);

const Stack = createNativeStackNavigator<RootStackParamList>();

const AppNavigator: React.FC = () => {
  const navigationRef = useRef<NavigationContainerRef<RootStackParamList>>(null);
  const {setNavigationRef} = useSimulation();

  useEffect(() => {
    if (navigationRef.current) {
      setNavigationRef(navigationRef.current);
    }
  }, [setNavigationRef]);

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" />
      <NavigationContainer ref={navigationRef}>
        <Stack.Navigator
          screenOptions={{
            headerShown: false,
            contentStyle: {backgroundColor: Colors.background},
            animation: 'slide_from_right',
          }}>
          <Stack.Screen name="Welcome" component={WelcomeScreen} />
          <Stack.Screen name="Browse" component={BrowseScreen} />
          <Stack.Screen name="Search" component={SearchScreen} />
          <Stack.Screen name="Featured" component={FeaturedScreen} />
          <Stack.Screen name="Categories" component={CategoriesScreen} />
          <Stack.Screen name="CategoryBrowse" component={CategoryBrowseScreen} />
          <Stack.Screen name="ProductDetail" component={ProductDetailScreen} />
          <Stack.Screen name="Reviews" component={ReviewsScreen} />
          <Stack.Screen name="Cart" component={CartScreen} />
          <Stack.Screen name="Wishlist" component={WishlistScreen} />
          <Stack.Screen name="CheckoutGuest" component={CheckoutGuestScreen} />
          <Stack.Screen name="CheckoutSignIn" component={CheckoutSignInScreen} />
          <Stack.Screen name="PaymentCard" component={PaymentCardScreen} />
          <Stack.Screen name="PaymentApplePay" component={PaymentApplePayScreen} />
          <Stack.Screen name="PaymentPayPal" component={PaymentPayPalScreen} />
          <Stack.Screen name="PaymentAndroidPay" component={PaymentAndroidPayScreen} />
          <Stack.Screen name="PaymentFailed" component={PaymentFailedScreen} />
          <Stack.Screen name="Confirmation" component={ConfirmationScreen} />
          <Stack.Screen name="Advanced" component={AdvancedScreen} />
        </Stack.Navigator>
      </NavigationContainer>
      <SimulationOverlay />
    </View>
  );
};

const App: React.FC = () => {
  useEffect(() => {
    // App Launch TTI
    // Measure time from module evaluation to first render and emit the
    // standard TTI event so the dashboard shows your app's launch latency.
    const ttiMs = Date.now() - APP_START_TIME;
    logAppLaunchTTI(ttiMs);

    // Cold-start span tree, mirroring Android's `app_cold_start` root with its
    // `sdk_init` child. The RN SDK has no span API, so these use the app's paired
    // start/end log convention (_span_id / _span_type / _duration_ms), back-dated
    // because the work completed before the SDK could accept logs.
    // Child span name must stay dotted: CaptureBridge.kt and CaptureBridge.swift both
    // emit `app_cold_start.sdk_init`, and the cold-start workflows filter on that full
    // name. (Native also emits `.scene_render` and `.state_restore` children, which have
    // no RN equivalent — see README § Platform parity notes.)
    const coldStartId = ScreenLogger.logCompletedSpan('app_cold_start', ttiMs);
    ScreenLogger.logCompletedSpan(
      'app_cold_start.sdk_init',
      SDK_INIT_DURATION_MS,
      undefined,
      coldStartId,
    );

    ScreenLogger.logInfo('app_launched');
    // Foreground/background lifecycle events (app_open / app_close).
    startLifecycleLogging();
  }, []);

  return (
    <SafeAreaProvider>
      <SimulationProvider>
        <AppNavigator />
      </SimulationProvider>
    </SafeAreaProvider>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});

export default App;
