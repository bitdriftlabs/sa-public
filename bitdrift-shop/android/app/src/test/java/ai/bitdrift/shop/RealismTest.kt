package ai.bitdrift.shop

import java.io.File
import java.nio.file.Files
import org.json.JSONException
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Phase 6: the realistic crash sites, their precursors, and the cart/session helpers. */
class RealismTest {
    private val dir: File = Files.createTempDirectory("bdshop-realism").toFile()

    @After fun cleanup() {
        Recorder.stop()
        dir.deleteRecursively()
    }

    private fun records(f: File) = f.readLines().filter { it.isNotBlank() }.map { JSONObject(it) }

    @Test(expected = NoSuchElementException::class)
    fun couponOnEmptyCartThrowsFromCartPricing() {
        CartPricing.applyCoupon(emptyList(), "SUMMER20")
    }

    @Test fun couponDiscountsTheMostValuableLine() {
        val lines = listOf(CartPricing.Line("a", 10.0, 1), CartPricing.Line("b", 50.0, 2))
        assertEquals(20.0, CartPricing.applyCoupon(lines, "SUMMER20"), 1e-9)
    }

    @Test fun malformedPromoPayloadThrowsAnUncheckedExceptionFromParser() {
        val e = runCatching { PromoBannerParser.parse(PromoBannerParser.MALFORMED_PAYLOAD) }.exceptionOrNull()
        assertTrue("IllegalStateException, not a bare checked JSONException: $e", e is IllegalStateException)
        assertTrue(e!!.cause is JSONException)
    }

    @Test fun wellFormedPromoPayloadParses() {
        val b = PromoBannerParser.parse("""{"title":"T","discount_percent":20,"ends_at_ms":1}""")
        assertEquals(20, b.discountPercent)
    }

    @Test fun crashCatalogHasTheRealisticEntriesAndPrecursors() {
        val names = Crashes.all.map { it.first }
        for (n in listOf("app_coupon_empty_cart", "app_promo_banner_payload")) {
            assertTrue("$n in catalog", n in names)
            assertNotNull("$n has a precursor", Crashes.precursors[n])
        }
        // announced catalog entries have no precursor, so they keep about_to_crash
        assertNull(Crashes.precursors["null_pointer"])
    }

    @Test fun couponPrecursorLogsAHandledErrorAndDoesNotCrash() {
        val file = Recorder.start(dir, "p1.jsonl")
        Crashes.precursors.getValue("app_coupon_empty_cart")()
        val r = records(file)
        assertEquals(listOf("coupon_apply_failed"), r.map { it.getString("message") })
        assertEquals("error", r[0].getString("level"))
        assertEquals("SUMMER20", r[0].getJSONObject("fields").getString("coupon_code"))
    }

    @Test fun promoPrecursorLogsFailureThenRetry() {
        val file = Recorder.start(dir, "p2.jsonl")
        Crashes.precursors.getValue("app_promo_banner_payload")()
        val r = records(file)
        assertEquals(listOf("promo_banner_parse_failed", "promo_banner_retry"), r.map { it.getString("message") })
        assertEquals("1", r[0].getJSONObject("fields").getString("attempt"))
        assertEquals("2", r[1].getJSONObject("fields").getString("attempt"))
    }

    @Test fun cartJsonCarriesCategoryPricesAndTotal() {
        ProductCatalog.learn(JSONObject("""{"products":[{"id":"p1","category":"Electronics"}]}"""))
        ProductCatalog.learn(JSONObject("""{"id":"p2","category":"Clothing"}"""))
        val cart = JSONObject(
            """{"items":[{"product_id":"p1","unit_price":10.5,"quantity":2},
                         {"product_id":"p2","unit_price":4.0,"quantity":1},
                         {"product_id":"zz","unit_price":1.0,"quantity":1}],"total":26.0}"""
        )
        val j = JSONObject(CartJson.from(cart))
        val items = j.getJSONArray("items")
        assertEquals(3, items.length())
        assertEquals("Electronics", items.getJSONObject(0).getString("category"))
        assertEquals("Clothing", items.getJSONObject(1).getString("category"))
        assertEquals("unknown", items.getJSONObject(2).getString("category"))
        assertEquals(10.5, items.getJSONObject(0).getDouble("price"), 1e-9)
        assertEquals(26.0, j.getDouble("total"), 1e-9)
        assertEquals(CartJson.lines(cart).size, 3)
        assertEquals(0, JSONObject(CartJson.from(null)).getJSONArray("items").length())
    }

    @Test fun sessionModeParsesAndDefaultsToPerJourney() {
        assertEquals(SessionMode.REALISTIC, SessionMode.fromId("realistic"))
        assertEquals(SessionMode.PER_JOURNEY, SessionMode.fromId("per_journey"))
        assertEquals(SessionMode.PER_JOURNEY, SessionMode.fromId(null))
        assertEquals(SessionMode.PER_JOURNEY, SessionMode.fromId("garbage"))
        assertFalse(DemoSettings.activeSessionMode == SessionMode.REALISTIC)
    }
}
