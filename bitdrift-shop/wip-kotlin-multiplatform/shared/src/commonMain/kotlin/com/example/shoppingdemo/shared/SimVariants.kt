package ai.bitdrift.shop.shared

enum class SimVariant { CONTROL, VARIANT_A, VARIANT_B }

data class VariantProfile(
    val discoveryBrowseMax: Double,
    val discoverySearchMax: Double,
    val featuredProb: Double,
    val reviewsProb: Double,
    val wishlistProb: Double,
    val extraCartMin: Int,
    val extraCartMax: Int,
    val removeItemProb: Double,
    val emptyReaddProb: Double,
    val quantityFlipProb: Double,
    val cartAbandonProb: Double,
    val guestProb: Double,
    val checkoutDropoutProb: Double,
    val paymentCardWeight: Double,
    val paymentApplePayWeight: Double,
    val paymentPayPalWeight: Double,
    val paymentAndroidPayWeight: Double,
    val paymentFailProb: Double,
    val androidPayFailProb: Double,
)

val VARIANT_PROFILES: Map<SimVariant, VariantProfile> = mapOf(
    SimVariant.CONTROL to VariantProfile(
        discoveryBrowseMax = 0.3333, discoverySearchMax = 0.6666,
        featuredProb = 0.5, reviewsProb = 0.5, wishlistProb = 0.4,
        extraCartMin = 1, extraCartMax = 3,
        removeItemProb = 0.6, emptyReaddProb = 0.2, quantityFlipProb = 0.3,
        cartAbandonProb = 0.05,
        guestProb = 0.5, checkoutDropoutProb = 0.0,
        paymentCardWeight = 0.25, paymentApplePayWeight = 0.25,
        paymentPayPalWeight = 0.25, paymentAndroidPayWeight = 0.25,
        paymentFailProb = 0.15, androidPayFailProb = 0.3,
    ),
    SimVariant.VARIANT_A to VariantProfile(
        discoveryBrowseMax = 0.4, discoverySearchMax = 0.85,
        featuredProb = 0.15, reviewsProb = 0.1, wishlistProb = 0.05,
        extraCartMin = 0, extraCartMax = 1,
        removeItemProb = 0.1, emptyReaddProb = 0.05, quantityFlipProb = 0.05,
        cartAbandonProb = 0.15,
        guestProb = 0.95, checkoutDropoutProb = 0.35,
        paymentCardWeight = 0.05, paymentApplePayWeight = 0.4,
        paymentPayPalWeight = 0.35, paymentAndroidPayWeight = 0.2,
        paymentFailProb = 0.35, androidPayFailProb = 0.2,
    ),
    SimVariant.VARIANT_B to VariantProfile(
        discoveryBrowseMax = 0.25, discoverySearchMax = 0.5,
        featuredProb = 0.75, reviewsProb = 0.9, wishlistProb = 0.75,
        extraCartMin = 2, extraCartMax = 4,
        removeItemProb = 0.9, emptyReaddProb = 0.6, quantityFlipProb = 0.7,
        cartAbandonProb = 0.0,
        guestProb = 0.05, checkoutDropoutProb = 0.05,
        paymentCardWeight = 0.95, paymentApplePayWeight = 0.03,
        paymentPayPalWeight = 0.02, paymentAndroidPayWeight = 0.0,
        paymentFailProb = 0.05, androidPayFailProb = 0.0,
    ),
)

val DEMO_ENTITIES: List<String> = listOf(
    "Groucho", "Harpo", "Chico", "Gummo", "Zeppo",
    "Moe", "Larry", "Curly", "Abbott", "Costello",
)

fun variantDisplayName(variant: SimVariant): String = when (variant) {
    SimVariant.CONTROL -> "Control"
    SimVariant.VARIANT_A -> "Variant A"
    SimVariant.VARIANT_B -> "Variant B"
}

fun applyVariant(variant: SimVariant) {
    val name = variantDisplayName(variant)
    val flags = listOf(
        "checkout_flow", "payment_ui", "cart_abandon_rate",
        "payment_android_pay", "order_summary", "anr_a", "force_quit",
    )
    for (flag in flags) {
        ScreenLogger.setFeatureFlagExposure(flag, name)
        ScreenLogger.addField("ff_$flag", name)
    }
}
