import Capture
import Foundation

/// "Smart" product recommendation engine — computes relevance scores from
/// description similarity.
///
/// This is deliberately the slow-rendering trap described in
/// `android/demo-slow-rendering.md`, ported intact: a Levenshtein-similarity
/// pass over each product's **full JSON profile** (not just its description),
/// run synchronously and unmemoized from a SwiftUI view body, so it re-executes
/// on every re-render. The code is correct — it type-checks, produces sensible
/// recommendations, and throws nothing. The defect is a runtime performance
/// characteristic you can only see by watching frames render.
///
/// On iOS the OOTB `DROPPED_FRAME` condition that catches this on Android does
/// not exist, so the `score_products` span wrapped around each call site (see
/// `BrowseScreen` / `ProductDetailScreen`) is the detection path here — the
/// shape `bd-shop-11b-slow-rendering-manual-span.json` matches on.
enum RecommendationEngine {

    /// Upper bound on the profile length fed to the O(n·m) distance function.
    ///
    /// Android compares whole profiles; a browse card serialises to ~2–3 KB,
    /// which on the JVM stays in "janky frame" territory. An unbounded Swift
    /// port lands very differently between `-Onone` and `-O`: debug builds would
    /// spend tens of seconds per pass and read as a hang, not as jank, which
    /// defeats the demo. Capping the compared prefix keeps the cost predictable
    /// across build configurations while leaving the trap — full profiles, main
    /// thread, unmemoized — intact.
    private static let maxProfileChars = 1200

    /// Scores all products against a reference product.
    /// Returns `(product, score)` pairs sorted by score descending.
    ///
    /// `parentSpanID` nests the two sub-spans below under the caller's own
    /// `score_products` span (see `Screens.swift`'s two call sites), so a slow
    /// call's P99 tail can be attributed to "parsing was slow" vs "the O(n·m)
    /// string comparison was slow" instead of one opaque number.
    static func scoreProducts(
        catalogJSON: String, referenceProductID: String, parentSpanID: UUID? = nil
    ) -> [(product: JSON, score: Double)] {
        // bitdrift SDK: trackSpan() isolates parsing the whole catalog JSON string
        // back into JSON values, separate from the similarity pass below.
        // POC: event tracking — sub-phase duration within an already-spanned call.
        let products = CaptureBridge.trackSpan(
            "score_products.parse_catalog", parentSpanID: parentSpanID
        ) { _ in
            JSON.parse(string: catalogJSON).array
        }
        guard !products.isEmpty else { return [] }

        guard let reference = products.first(where: { $0.str("id") == referenceProductID }) else {
            return products.map { ($0, 0.0) }
        }

        let refDesc = reference.str("description", reference.str("name"))
        let refCategory = reference.str("category")
        let refPrice = reference.num("price")
        // Compare full product profiles (specs, colors, promotions, seller info,
        // …), not just the description, so similar-but-differently-worded
        // listings still score as related.
        let refProfile = clip(reference.serialized)

        // bitdrift SDK: trackSpan() isolates the O(n·m) Levenshtein pass per
        // product — the most legitimately interesting perf case in the app (see
        // the type doc's "slow-rendering trap"), separate from parsing above.
        // POC: event tracking — sub-phase duration within an already-spanned call.
        return CaptureBridge.trackSpan(
            "score_products.similarity_pass", parentSpanID: parentSpanID
        ) { _ in
            products
                .filter { $0.str("id") != referenceProductID }
                .map { product -> (product: JSON, score: Double) in
                    let desc = product.str("description", product.str("name"))
                    let category = product.str("category")

                    let descSimilarity = levenshteinSimilarity(refProfile, clip(product.serialized))
                    let categoryBoost = category == refCategory ? 0.3 : 0.0
                    let priceProximity = priceScore(refPrice, product.num("price"))
                    let sharedWords = Double(countSharedWords(refDesc, desc))

                    let score = (descSimilarity * 0.4) + categoryBoost + (priceProximity * 0.2)
                        + (sharedWords * 0.01)
                    return (product, score)
                }
                .sorted { $0.score > $1.score }
        }
    }

    // MARK: - Scoring primitives

    private static func clip(_ text: String) -> String {
        text.count <= maxProfileChars ? text : String(text.prefix(maxProfileChars))
    }

    /// Levenshtein distance normalised to a 0.0–1.0 similarity.
    ///
    /// Two rolling rows instead of a full (m+1)×(n+1) matrix: same result and
    /// the same O(n·m) time the Android version has, without allocating a
    /// multi-megabyte 2D array per comparison.
    private static func levenshteinSimilarity(_ a: String, _ b: String) -> Double {
        let lhs = Array(a.unicodeScalars)
        let rhs = Array(b.unicodeScalars)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0.0 }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            let lhsChar = lhs[i - 1]
            for j in 1...rhs.count {
                let cost = lhsChar == rhs[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }

        let distance = previous[rhs.count]
        return 1.0 - (Double(distance) / Double(max(lhs.count, rhs.count)))
    }

    private static func priceScore(_ refPrice: Double, _ otherPrice: Double) -> Double {
        guard refPrice > 0 else { return 0.0 }
        let ratio = otherPrice / refPrice
        return 1.0 - min(abs(1.0 - ratio), 1.0)
    }

    /// Tokenise both strings, count shared unique words.
    private static func countSharedWords(_ a: String, _ b: String) -> Int {
        tokens(a).intersection(tokens(b)).count
    }

    private static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }
}
