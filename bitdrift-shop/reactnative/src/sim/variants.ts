import {ScreenLogger} from '../utils/logger';
import {SpecEvents, SpecFields, SpecFlags} from '../generated/specConstants';

// ─── Personas / Variants ───────────────────────────────────────────────────────
// Mirrors the Android app's SimVariant. Each variant is a journey persona and maps to a
// fixed set of feature-flag exposures, so the dashboard can slice every metric, crash,
// and funnel by variant.

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

// Persona ids in spec/personas.yaml, which drive spec/journey.yaml (probabilities live there).
export const VARIANT_PERSONAS: Record<SimVariant, string> = {
  [SimVariant.Control]: 'control',
  [SimVariant.VariantA]: 'variant_a',
  [SimVariant.VariantB]: 'variant_b',
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
  // Drives the recommendations_v2 exposure and the expensive scoring pass, matching
  // Android's SimulationManager.recommendationsV2Enabled (surfaced as "Slow" in the UI).
  slowModeEnabled: boolean;
};

// Apply a variant: records every feature-flag exposure AND its mirror global field,
// exactly like Android's setVariant(). Called by the journey's `exposures` step.
export const applyVariant = (variant: SimVariant, chaos: ChaosState): void => {
  const flags = VARIANT_FLAGS[variant];
  const orderSummary = chaos.crashLoopEnabled ? 'v2' : 'v1';
  const anrA = chaos.anrAEnabled ? 'enabled' : 'disabled';
  const forceQuit = chaos.forceQuitEnabled ? 'enabled' : 'disabled';
  const recommendationsV2 = chaos.slowModeEnabled ? 'enabled' : 'disabled';

  // Feature-flag exposures (queryable as flag exposures in the dashboard).
  ScreenLogger.setFeatureFlagExposure(SpecFlags.checkoutFlow, flags.checkout_flow);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.paymentUi, flags.payment_ui);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.cartAbandonRate, flags.cart_abandon_rate);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.paymentAndroidPay, flags.payment_android_pay);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.orderSummary, orderSummary);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.anrA, anrA);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.forceQuit, forceQuit);
  ScreenLogger.setFeatureFlagExposure(SpecFlags.recommendationsV2, recommendationsV2);

  // Mirror fields (ff_*) so the same values are also filterable as global fields.
  ScreenLogger.addField(SpecFields.ffCheckoutFlow, flags.checkout_flow);
  ScreenLogger.addField(SpecFields.ffPaymentUi, flags.payment_ui);
  ScreenLogger.addField(SpecFields.ffCartAbandonRate, flags.cart_abandon_rate);
  ScreenLogger.addField(SpecFields.ffVariant, VARIANT_LABELS[variant]);
  ScreenLogger.addField(SpecFields.ffPaymentAndroidPay, flags.payment_android_pay);
  ScreenLogger.addField(SpecFields.ffOrderSummary, orderSummary);
  ScreenLogger.addField(SpecFields.ffAnrA, anrA);
  ScreenLogger.addField(SpecFields.ffForceQuit, forceQuit);
  ScreenLogger.addField(SpecFields.ffRecommendationsV2, recommendationsV2);

  ScreenLogger.logInfo(SpecEvents.featureFlagExposureSet);
};
