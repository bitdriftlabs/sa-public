package ai.bitdrift.shop

/** Small app-owned wrappers for work that may fail or be cancelled. */
object AppWork {
    suspend fun <T> runSuspend(block: suspend () -> T): T = block()

    suspend fun <T> runSuspend(
        name: String,
        fields: Map<String, String> = emptyMap(),
        parentSpanId: Any? = null,
        block: suspend () -> T,
    ): T = block()

    fun <T> run(block: () -> T): T = block()

    fun <T> run(
        name: String,
        fields: Map<String, String> = emptyMap(),
        parentSpanId: Any? = null,
        block: () -> T,
    ): T = block()

    suspend fun <T> bestEffort(block: suspend () -> T): T? = try {
        block()
    } catch (_: Exception) {
        null
    }
}
