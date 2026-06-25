package ai.bitdrift.shop.shared

// Platform actuals for crashes that require native/OS-level operations.
internal expect fun platformNativeSigsegv()
internal expect fun platformNativeSigbus()
internal expect fun platformNativeSigabrt()
internal expect fun platformNativeSigfpe()
internal expect fun platformUnsatisfiedLink()
internal expect fun platformBlockMainThread(ms: Long)
internal expect fun platformForceQuit()

data class CrashEntry(val name: String, val fn: () -> Unit)

// ── Main-thread Kotlin crashes ───────────────────────────────────────────────
// These are standard Kotlin exception paths that work on both JVM and Native.

private fun crashNullPointer(): Unit { val x: String? = null; x!!.length }

private fun crashArrayIndex(): Unit { val a = intArrayOf(1, 2, 3); a[99].toString() }

private fun crashClassCast(): Unit { val x: Any = "hello"; (x as Int).toString() }

private fun crashDivideByZero(): Unit { val _ = 1 / 0 }

private fun crashNumberFormat(): Unit { "not-a-number".toInt() }

private fun crashIllegalState(): Unit { check(false) { "check(false) failed" } }

private fun crashIllegalArgument(): Unit { require(false) { "require(false) failed" } }

private fun crashConcurrentModification(): Unit {
    throw ConcurrentModificationException("list mutated during iteration")
}

private fun crashStackOverflow(): Unit {
    fun recurse(n: Int): Int = recurse(n + 1)
    recurse(0)
}

private fun crashStringIndex(): Unit { val s = "hello"; s[999].toString() }

private fun crashNegativeArraySize(): Unit { IntArray(-1) }

private fun crashAssertionError(): Unit { throw AssertionError("assertion failed") }

// ── Background / async crashes ───────────────────────────────────────────────

private fun crashRuntimeBackgroundThread(): Unit {
    throw RuntimeException("RuntimeException on worker thread")
}

private fun crashCoroutineIo(): Unit {
    throw IllegalStateException("IllegalState on IO dispatcher (coroutine_io)")
}

private fun crashOomAllocatorThread(): Unit {
    val blocks = mutableListOf<ByteArray>()
    while (true) { blocks.add(ByteArray(64 * 1024 * 1024)) }
}

// ── Delegates to platform actuals ────────────────────────────────────────────

private fun crashUnsatisfiedLink(): Unit = platformUnsatisfiedLink()
private fun crashNativeSigsegv(): Unit = platformNativeSigsegv()
private fun crashNativeSigbus(): Unit = platformNativeSigbus()
private fun crashNativeSigabrt(): Unit = platformNativeSigabrt()
private fun crashNativeSigfpe(): Unit = platformNativeSigfpe()

// ── Ordered catalog — same names and order as Android's Crashes.all ──────────

val CRASHES: List<CrashEntry> = listOf(
    CrashEntry("null_pointer",              ::crashNullPointer),
    CrashEntry("array_index",               ::crashArrayIndex),
    CrashEntry("class_cast",                ::crashClassCast),
    CrashEntry("divide_by_zero",            ::crashDivideByZero),
    CrashEntry("number_format",             ::crashNumberFormat),
    CrashEntry("illegal_state",             ::crashIllegalState),
    CrashEntry("illegal_argument",          ::crashIllegalArgument),
    CrashEntry("concurrent_modification",   ::crashConcurrentModification),
    CrashEntry("stack_overflow",            ::crashStackOverflow),
    CrashEntry("string_index",              ::crashStringIndex),
    CrashEntry("negative_array_size",       ::crashNegativeArraySize),
    CrashEntry("assertion_error",           ::crashAssertionError),
    CrashEntry("unsatisfied_link",          ::crashUnsatisfiedLink),
    CrashEntry("runtime_background_thread", ::crashRuntimeBackgroundThread),
    CrashEntry("coroutine_io",              ::crashCoroutineIo),
    CrashEntry("oom_allocator_thread",      ::crashOomAllocatorThread),
    CrashEntry("native_sigsegv",            ::crashNativeSigsegv),
    CrashEntry("native_sigbus",             ::crashNativeSigbus),
    CrashEntry("native_sigabrt",            ::crashNativeSigabrt),
    CrashEntry("native_sigfpe",             ::crashNativeSigfpe),
)

val CRASH_NAMES: List<String> = CRASHES.map { it.name }

fun crashByName(name: String): CrashEntry? = CRASHES.find { it.name == name }

fun triggerCrash(name: String) {
    val entry = crashByName(name) ?: return
    ScreenLogger.addField("crash_kind", name)
    ScreenLogger.logWarning("about_to_crash: $name", mapOf("crash_kind" to name))
    entry.fn()
}

fun triggerAnr(ms: Long) = platformBlockMainThread(ms)

fun triggerForceQuit() = platformForceQuit()
