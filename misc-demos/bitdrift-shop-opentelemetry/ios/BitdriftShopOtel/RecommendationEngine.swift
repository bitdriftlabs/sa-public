import Foundation

/// "Smart" product recommendation engine — direct port of `RecommendationEngine.kt`. Computes
/// relevance scores based on description similarity, category match, price proximity, and shared
/// vocabulary.
enum RecommendationEngine {
    /// Scores all products against a reference product. Returns `(product, score)` pairs sorted
    /// by score descending.
    static func scoreProducts(catalogJson: String, referenceProductId: String) -> [(JSONObject, Double)] {
        guard let data = catalogJson.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        let products = array.map(JSONObject.init)

        guard let reference = products.first(where: { $0.optString("id") == referenceProductId }) else {
            return products.map { ($0, 0.0) }
        }

        let refDesc = reference.optString("description", reference.optString("name"))
        let refCategory = reference.optString("category")
        let refPrice = reference.optDouble("price")

        return products
            .filter { $0.optString("id") != referenceProductId }
            .map { product -> (JSONObject, Double) in
                let desc = product.optString("description", product.optString("name"))
                let cat = product.optString("category")

                let descSimilarity = levenshteinSimilarity(refDesc, desc)
                let catBoost = cat == refCategory ? 0.3 : 0.0
                let priceProximity = priceScore(refPrice, product.optDouble("price"))
                let sharedWords = countSharedWords(refDesc, desc)

                let score = (descSimilarity * 0.4) + catBoost + (priceProximity * 0.2) + (Double(sharedWords) * 0.01)
                return (product, score)
            }
            .sorted { $0.1 > $1.1 }
    }

    /// Levenshtein distance normalized to 0.0-1.0 similarity.
    private static func levenshteinSimilarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0.0 }
        let a = Array(a)
        let b = Array(b)
        let m = a.count
        let n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0 ... m { dp[i][0] = i }
        for j in 0 ... n { dp[0][j] = j }
        for i in 1 ... m {
            for j in 1 ... n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
        let maxLen = max(m, n)
        return 1.0 - (Double(dp[m][n]) / Double(maxLen))
    }

    private static func priceScore(_ refPrice: Double, _ otherPrice: Double) -> Double {
        guard refPrice > 0.0 else { return 0.0 }
        let ratio = otherPrice / refPrice
        return 1.0 - min(abs(1.0 - ratio), 1.0)
    }

    /// Tokenizes both strings, counts shared unique words.
    private static func countSharedWords(_ a: String, _ b: String) -> Int {
        func words(_ s: String) -> Set<String> {
            Set(
                s.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 2 }
            )
        }
        return words(a).intersection(words(b)).count
    }
}
