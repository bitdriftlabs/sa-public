import React, {useRef, useEffect} from 'react';
import {View, StyleSheet, StatusBar, Platform} from 'react-native';
import {NavigationContainer, NavigationContainerRef} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {SafeAreaProvider} from 'react-native-safe-area-context';

// Workshop 1 — SDK Initialization
// Import and initialise the bitdrift Capture SDK as early as possible so all
// subsequent logs, screen views, and network events are captured.
import {init, SessionStrategy, addField, logAppLaunchTTI} from '@bitdrift/react-native';

import {SimulationProvider, useSimulation} from './src/context/SimulationContext';
import {SimulationOverlay} from './src/components';
import {Colors} from './src/utils/colors';
import {ScreenLogger} from './src/utils/logger';
import {BITDRIFT_API_KEY, BITDRIFT_API_HOST} from './src/config';
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
  ConfirmationScreen,
} from './src/screens';

// Capture wall-clock time at module evaluation for TTI measurement.
const APP_START_TIME = Date.now();

// Initialise with an activity-based session so new sessions begin after a
// period of inactivity, matching how iOS/Android demos are configured.
// API key is loaded from src/config.ts (reads BITDRIFT_API_KEY from .env).
init(BITDRIFT_API_KEY, SessionStrategy.Activity, {
  url: BITDRIFT_API_HOST,
  crashReporting: {
    UNSTABLE_enableJsErrors: true,
  },
});

// Workshop 5 — Global Fields
// These fields are automatically attached to every log, span, and network
// event so dashboards can slice data by variant or platform.
addField('app_variant', 'workshop-demo');
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
          <Stack.Screen name="Confirmation" component={ConfirmationScreen} />
        </Stack.Navigator>
      </NavigationContainer>
      <SimulationOverlay />
    </View>
  );
};

const App: React.FC = () => {
  useEffect(() => {
    // Workshop 3 — App Launch TTI
    // Measure time from module evaluation to first render and emit the
    // standard TTI event so the dashboard shows your app's launch latency.
    logAppLaunchTTI(Date.now() - APP_START_TIME);
    ScreenLogger.logInfo('app_launched');
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
