package ai.bitdrift.shop

import ai.bitdrift.shop.generated.SpecEvents
import ai.bitdrift.shop.generated.SpecFields
import ai.bitdrift.shop.generated.SpecFlags
import ai.bitdrift.shop.generated.SpecScreen
import ai.bitdrift.shop.generated.SpecSpans
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The generated constants (from the spec yaml files) must not collide, or two names would share one wire value. */
class SpecConstantsTest {
    private fun values(c: Class<*>): List<String> =
        c.declaredFields.filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
            .map { it.get(null) as String }

    @Test fun eventNamesAreUnique() = assertNoDuplicates("SpecEvents", values(SpecEvents::class.java))
    @Test fun fieldKeysAreUnique() = assertNoDuplicates("SpecFields", values(SpecFields::class.java))
    @Test fun spanNamesAreUnique() = assertNoDuplicates("SpecSpans", values(SpecSpans::class.java))
    @Test fun flagNamesAndMirrorFieldsAreUnique() {
        // Persona values (e.g. "random", "enabled") repeat across flags on purpose; names and mirror fields must not.
        val names = SpecFlags::class.java.declaredFields
            .filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
            .filter { f -> listOf("_CONTROL", "_VARIANT_A", "_VARIANT_B").none { f.name.endsWith(it) } }
            .map { it.get(null) as String }
        assertNoDuplicates("SpecFlags names", names)
    }

    @Test fun screensHaveUniqueNamesAndRoutes() {
        assertNoDuplicates("screen names", SpecScreen.entries.map { it.screenName })
        assertNoDuplicates("screen routes", SpecScreen.entries.map { it.route })
        assertEquals(19, SpecScreen.entries.size)
    }

    @Test fun telemetryNamesArePopulated() {
        assertTrue(values(SpecEvents::class.java).size > 40)
        assertEquals("confirmation_reached", SpecEvents.CONFIRMATION_REACHED)
        assertEquals("journey", SpecSpans.JOURNEY)
        assertEquals("_screen_name", SpecFields.SDK_SCREEN_NAME)
    }

    private fun assertNoDuplicates(what: String, names: List<String>) {
        val dupes = names.groupingBy { it }.eachCount().filterValues { it > 1 }.keys
        assertTrue("$what has duplicate values: $dupes", dupes.isEmpty())
    }
}
