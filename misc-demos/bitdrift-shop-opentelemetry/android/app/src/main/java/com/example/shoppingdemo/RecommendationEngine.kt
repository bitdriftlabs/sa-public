package com.example.shoppingdemo

import org.json.JSONArray
import org.json.JSONObject

/**
 * "Smart" product recommendation engine.
 * Computes relevance scores based on description similarity.
 */
object RecommendationEngine {

    /**
     * Scores all products against a reference product.
     * Returns a list of (productJson, score) pairs sorted by score descending.
     */
    fun scoreProducts(
        catalogJson: String,
        referenceProductId: String
    ): List<Pair<JSONObject, Double>> {
        val catalog = try { JSONArray(catalogJson) } catch (_: Exception) { return emptyList() }
        val products = (0 until catalog.length()).map { catalog.getJSONObject(it) }

        val reference = products.find { it.optString("id") == referenceProductId }
            ?: return products.map { it to 0.0 }

        val refDesc = reference.optString("description", reference.optString("name", ""))
        val refCategory = reference.optString("category", "")

        return products
            .filter { it.optString("id") != referenceProductId }
            .map { product ->
                val desc = product.optString("description", product.optString("name", ""))
                val cat = product.optString("category", "")

                val descSimilarity = levenshteinSimilarity(refDesc, desc)
                val catBoost = if (cat == refCategory) 0.3 else 0.0
                val priceProximity = priceScore(
                    reference.optDouble("price", 0.0),
                    product.optDouble("price", 0.0)
                )

                val sharedWords = countSharedWords(refDesc, desc)

                val score = (descSimilarity * 0.4) + catBoost + (priceProximity * 0.2) + (sharedWords * 0.01)
                product to score
            }
            .sortedByDescending { it.second }
    }

    /**
     * Levenshtein distance normalized to 0.0–1.0 similarity.
     */
    private fun levenshteinSimilarity(a: String, b: String): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val m = a.length
        val n = b.length
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in 0..m) dp[i][0] = i
        for (j in 0..n) dp[0][j] = j
        for (i in 1..m) {
            for (j in 1..n) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                dp[i][j] = minOf(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        val maxLen = maxOf(m, n)
        return 1.0 - (dp[m][n].toDouble() / maxLen)
    }

    private fun priceScore(refPrice: Double, otherPrice: Double): Double {
        if (refPrice <= 0.0) return 0.0
        val ratio = otherPrice / refPrice
        return 1.0 - minOf(kotlin.math.abs(1.0 - ratio), 1.0)
    }

    /** Tokenize both strings, count shared unique words. */
    private fun countSharedWords(a: String, b: String): Int {
        val wordsA = a.lowercase().split(Regex("\\W+")).filter { it.length > 2 }.toSet()
        val wordsB = b.lowercase().split(Regex("\\W+")).filter { it.length > 2 }.toSet()
        return wordsA.intersect(wordsB).size
    }
}
