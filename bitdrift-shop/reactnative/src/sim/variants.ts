import {ScreenLogger} from '../utils/logger';

// ─── Personas / Variants ───────────────────────────────────────────────────────
// Mirrors the Android app's SimVariant. Each variant biases the simulation state
// machine and maps to a fixed set of feature-flag exposures, so the dashboard can
// slice every metric, crash, and funnel by variant.

export enum SimVariant {
  Control = 'Control',
  VariantA = 'Variant A',
  VariantB = 'Variant B',
}

export const VARIANT_LABELS: Record<SimVariant, string> = {
  [SimVariant.Control]: 'Control',
  [SimVariant.VariantA]: 'Variant A',
  [SimVariant.VariantB]: 'Variant B',
};

// Probability profile per variant. Numbers are exact ports of SimulationManager.kt.
export type VariantProfile = {
  // Discovery: cumulative thresholds for [browse, search, categories].
  // browseMax = P(browse); searchMax = P(browse)+P(search); rest = categories.
  discoveryBrowseMax: number;
  discoverySearchMax: number;
  featuredProb: number; // visit Featured
  reviewsProb: number; // read Reviews
  wishlistProb: number; // visit Wishlist
  extraCartMin: number; // extra items added beyond first
  extraCartMax: number;
  removeItemProb: number; // remove an item
  emptyReaddProb: number; // empty cart + re-add
  quantityFlipProb: number; // remove & re-add same item
  cartAbandonProb: number; // abandon before checkout (journey ends)
  guestProb: number; // P(guest) vs signin
  checkoutDropoutProb: number; // abandon at checkout screen (journey ends)
  // Payment method weights: card, applePay, payPal, androidPay (sum = 1.0).
  paymentWeights: {card: number; applePay: number; payPal: number; androidPay: number};
  paymentFailProb: number; // failure rate for non-Android-Pay methods
  androidPayFailProb: number; // failure rate specifically for Android Pay
};

export const VARIANT_PROFILES: Record<SimVariant, VariantProfile> = {
  // CONTROL — baseline, mostly uniform/random.
  [SimVariant.Control]: {
    discoveryBrowseMax: 0.3333,
    discoverySearchMax: 0.6666,
    featuredProb: 0.5,
    reviewsProb: 0.5,
    wishlistProb: 0.4,
    extraCartMin: 1,
    extraCartMax: 3,
    removeItemProb: 0.6,
    emptyReaddProb: 0.2,
    quantityFlipProb: 0.3,
    cartAbandonProb: 0.05,
    guestProb: 0.5,
    checkoutDropoutProb: 0.0,
    paymentWeights: {card: 0.25, applePay: 0.25, payPal: 0.25, androidPay: 0.25},
    paymentFailProb: 0.15,
    androidPayFailProb: 0.3,
  },
  // VARIANT A — digital native: snap decisions, guest + digital pay, more friction.
  [SimVariant.VariantA]: {
    discoveryBrowseMax: 0.4,
    discoverySearchMax: 0.85,
    featuredProb: 0.15,
    reviewsProb: 0.1,
    wishlistProb: 0.05,
    extraCartMin: 0,
    extraCartMax: 1,
    removeItemProb: 0.1,
    emptyReaddProb: 0.05,
    quantityFlipProb: 0.05,
    cartAbandonProb: 0.15,
    guestProb: 0.95,
    checkoutDropoutProb: 0.35,
    paymentWeights: {card: 0.05, applePay: 0.4, payPal: 0.35, androidPay: 0.2},
    paymentFailProb: 0.35,
    androidPayFailProb: 0.2,
  },
  // VARIANT B — deliberate shopper: reads everything, signin + card, low friction.
  [SimVariant.VariantB]: {
    discoveryBrowseMax: 0.25,
    discoverySearchMax: 0.5,
    featuredProb: 0.75,
    reviewsProb: 0.9,
    wishlistProb: 0.75,
    extraCartMin: 2,
    extraCartMax: 4,
    removeItemProb: 0.9,
    emptyReaddProb: 0.6,
    quantityFlipProb: 0.7,
    cartAbandonProb: 0.0,
    guestProb: 0.05,
    checkoutDropoutProb: 0.05,
    paymentWeights: {card: 0.95, applePay: 0.03, payPal: 0.02, androidPay: 0.0},
    paymentFailProb: 0.05,
    androidPayFailProb: 0.0,
  },
};

// Feature-flag values per variant (ports SimulationManager.setVariant()).
type VariantFlags = {
  checkout_flow: string;
  payment_ui: string;
  cart_abandon_rate: string;
  payment_android_pay: string;
};

const VARIANT_FLAGS: Record<SimVariant, VariantFlags> = {
  [SimVariant.Control]: {
    checkout_flow: 'random',
    payment_ui: 'random',
    cart_abandon_rate: 'medium',
    payment_android_pay: 'enabled',
  },
  [SimVariant.VariantA]: {
    checkout_flow: 'guest',
    payment_ui: 'digital',
    cart_abandon_rate: 'high',
    payment_android_pay: 'enabled',
  },
  [SimVariant.VariantB]: {
    checkout_flow: 'signin',
    payment_ui: 'card',
    cart_abandon_rate: 'low',
    payment_android_pay: 'disabled',
  },
};

// Chaos toggles that also feed feature-flag exposures (set independently of variant).
export type ChaosState = {
  crashLoopEnabled: boolean;
  anrAEnabled: boolean;
  forceQuitEnabled: boolean;
};

// Apply a variant: records every feature-flag exposure AND its mirror global field,
// exactly like Android's setVariant(). Call after every new session/journey start.
export const applyVariant = (variant: SimVariant, chaos: ChaosState): void => {
  const flags = VARIANT_FLAGS[variant];
  const orderSummary = chaos.crashLoopEnabled ? 'v2' : 'v1';
  const anrA = chaos.anrAEnabled ? 'enabled' : 'disabled';
  const forceQuit = chaos.forceQuitEnabled ? 'enabled' : 'disabled';

  // Feature-flag exposures (queryable as flag exposures in the dashboard).
  ScreenLogger.setFeatureFlagExposure('checkout_flow', flags.checkout_flow);
  ScreenLogger.setFeatureFlagExposure('payment_ui', flags.payment_ui);
  ScreenLogger.setFeatureFlagExposure('cart_abandon_rate', flags.cart_abandon_rate);
  ScreenLogger.setFeatureFlagExposure('payment_android_pay', flags.payment_android_pay);
  ScreenLogger.setFeatureFlagExposure('order_summary', orderSummary);
  ScreenLogger.setFeatureFlagExposure('anr_a', anrA);
  ScreenLogger.setFeatureFlagExposure('force_quit', forceQuit);

  // Mirror fields (ff_*) so the same values are also filterable as global fields.
  ScreenLogger.addField('ff_checkout_flow', flags.checkout_flow);
  ScreenLogger.addField('ff_payment_ui', flags.payment_ui);
  ScreenLogger.addField('ff_cart_abandon_rate', flags.cart_abandon_rate);
  ScreenLogger.addField('ff_variant', VARIANT_LABELS[variant]);
  ScreenLogger.addField('ff_payment_android_pay', flags.payment_android_pay);
  ScreenLogger.addField('ff_order_summary', orderSummary);
  ScreenLogger.addField('ff_anr_a', anrA);
  ScreenLogger.addField('ff_force_quit', forceQuit);

  ScreenLogger.logInfo('feature_flag_exposure_set');
};

// Fixed entity pool, rotated per journey (ports DEMO_ENTITIES).
export const DEMO_ENTITIES = [
  'Groucho', 'Harpo', 'Chico', 'Gummo', 'Zeppo',
  'Moe', 'Larry', 'Curly', 'Abbott', 'Costello',
];
