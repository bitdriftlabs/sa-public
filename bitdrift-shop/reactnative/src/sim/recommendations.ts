import {ScreenLogger} from '../utils/logger';

// "Smart" product recommendation engine — ports Android's RecommendationEngine.kt /
// iOS's RecommendationEngine.swift. Computes relevance scores from description
// similarity using an O(n*m) Levenshtein pass, which is deliberately expensive: it is
// the on-thread workload behind the "Slow" toggle and the recommendations_v2 flag.
//
// Scoring is split into two nested spans under the caller's `score_products` span, so a
// slow call's tail can be attributed to "parsing was slow" vs. "the similarity pass was
// slow" rather than one opaque number.

export type ScoredProduct = {
  product: Record<string, unknown>;
  score: number;
};

// Levenshtein distance normalised to a 0.0-1.0 similarity.
// Two-row implementation: full matrix on product profiles would be O(n*m) memory.
const levenshteinSimilarity = (a: string, b: string): number => {
  if (a.length === 0 || b.length === 0) {
    return 0;
  }
  let prev = new Array<number>(b.length + 1);
  let curr = new Array<number>(b.length + 1);
  for (let j = 0; j <= b.length; j++) {
    prev[j] = j;
  }
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    const ca = a.charCodeAt(i - 1);
    for (let j = 1; j <= b.length; j++) {
      const cost = ca === b.charCodeAt(j - 1) ? 0 : 1;
      curr[j] = Math.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
    }
    const swap = prev;
    prev = curr;
    curr = swap;
  }
  const distance = prev[b.length];
  const maxLen = Math.max(a.length, b.length);
  return maxLen === 0 ? 0 : 1 - distance / maxLen;
};

// Closer prices score higher; 0.0 when either side is missing.
const priceScore = (refPrice: number, price: number): number => {
  if (refPrice <= 0 || price <= 0) {
    return 0;
  }
  const delta = Math.abs(refPrice - price);
  return 1 / (1 + delta / refPrice);
};

const countSharedWords = (a: string, b: string): number => {
  const wordsA = new Set(a.toLowerCase().split(/\W+/).filter(w => w.length > 3));
  let shared = 0;
  for (const w of b.toLowerCase().split(/\W+/)) {
    if (w.length > 3 && wordsA.has(w)) {
      shared += 1;
    }
  }
  return shared;
};

// startSpan takes a parentSpanId; trackSpanNested does not, so nest children explicitly.
// Without this the two sub-spans render as unrelated flat spans.
const trackChild = <T,>(name: string, parentSpanId: string | undefined, fn: () => T): T => {
  const span = ScreenLogger.startSpan(name, undefined, parentSpanId);
  try {
    const result = fn();
    span.end('success');
    return result;
  } catch (e) {
    span.end('failure');
    throw e;
  }
};

const str = (o: Record<string, unknown>, key: string, fallback = ''): string => {
  const v = o[key];
  return typeof v === 'string' ? v : fallback;
};

const num = (o: Record<string, unknown>, key: string): number => {
  const v = o[key];
  return typeof v === 'number' ? v : 0;
};

/**
 * Scores every product against a reference product, highest first.
 *
 * parentSpanId nests the two sub-spans under the caller's `score_products` span.
 */
export const scoreProducts = (
  catalogJson: string,
  referenceProductId: string,
  parentSpanId?: string,
): ScoredProduct[] => {
  // Isolates decoding the catalog JSON and building comparable profile strings, separate
  // from the similarity pass below. Takes the raw JSON string (rather than parsed
  // objects) so this span measures real parsing cost, as Android's does.
  const profiles = trackChild('score_products.parse_catalog', parentSpanId, () => {
      let catalog: Array<Record<string, unknown>>;
      try {
        const parsed = JSON.parse(catalogJson);
        catalog = Array.isArray(parsed) ? parsed : [];
      } catch {
        return [];
      }
    return catalog.map(p => ({product: p, profile: JSON.stringify(p)}));
  });
  if (profiles.length === 0) {
    return [];
  }

  const reference = profiles.find(p => str(p.product, 'id') === referenceProductId);
  if (!reference) {
    return profiles.map(p => ({product: p.product, score: 0}));
  }

  const refDesc = str(reference.product, 'description', str(reference.product, 'name'));
  const refCategory = str(reference.product, 'category');
  const refProfile = reference.profile;
  const refPrice = num(reference.product, 'price');

  // The O(n*m) Levenshtein pass — the actual cost centre, and the reason this engine
  // exists as a slow-rendering demo.
  return trackChild('score_products.similarity_pass', parentSpanId, () =>
    profiles
        .filter(p => str(p.product, 'id') !== referenceProductId)
        .map(({product, profile}) => {
          const desc = str(product, 'description', str(product, 'name'));
          const descSimilarity = levenshteinSimilarity(refProfile, profile);
          const catBoost = str(product, 'category') === refCategory ? 0.3 : 0;
          const priceProximity = priceScore(refPrice, num(product, 'price'));
          const sharedWords = countSharedWords(refDesc, desc);

          const score =
            descSimilarity * 0.4 + catBoost + priceProximity * 0.2 + sharedWords * 0.01;
          return {product, score};
        })
      .sort((a, b) => b.score - a.score),
  );
};
