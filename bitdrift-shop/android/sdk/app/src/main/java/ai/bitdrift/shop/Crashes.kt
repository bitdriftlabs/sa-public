package ai.bitdrift.shop

import android.system.Os
import android.system.OsConstants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Catalog of crash variants. Each entry is a top-frame method so bitdrift's
 * crash issue grouper places them in distinct groups.
 *
 * Rules for distinct grouping:
 *  - JVM crashes: each must have its own uniquely-named top-frame method.
 *  - Native signals: each signal method must call Os.kill DIRECTLY — do NOT
 *    route through a shared helper, or they all group under the same frame.
 */
object Crashes {

    val all: List<Pair<String, () -> Unit>> = listOf(
        // Main-thread JVM — each exception type is a distinct issue group
        "null_pointer"              to ::crashNullPointer,
        "array_index"               to ::crashArrayIndex,
        "class_cast"                to ::crashClassCast,
        "divide_by_zero"            to ::crashDivideByZero,
        "number_format"             to ::crashNumberFormat,
        "illegal_state"             to ::crashIllegalState,
        "illegal_argument"          to ::crashIllegalArgument,
        "concurrent_modification"   to ::crashConcurrentModification,
        "stack_overflow"            to ::crashStackOverflow,
        "string_index"              to ::crashStringIndex,
        "negative_array_size"       to ::crashNegativeArraySize,
        "assertion_error"           to ::crashAssertionError,
        "unsatisfied_link"          to ::crashUnsatisfiedLink,
        // Background-thread JVM — same exception but different stack frame
        "runtime_background_thread" to ::crashRuntimeBackgroundThread,
        "coroutine_io"              to ::crashCoroutineIO,
        "oom_allocator_thread"      to ::crashOomAllocatorThread,
        // Native signals — each calls Os.kill directly so frames are distinct
        "native_sigsegv"            to ::crashNativeSigsegv,
        "native_sigbus"             to ::crashNativeSigbus,
        "native_sigabrt"            to ::crashNativeSigabrt,
        "native_sigfpe"             to ::crashNativeSigfpe,
    )

    // ── Main-thread JVM ────────────────────────────────────────────────────

    private fun crashNullPointer() {
        val s: String? = null
        @Suppress("UNNECESSARY_NOT_NULL_ASSERTION")
        s!!.length
    }

    private fun crashArrayIndex() {
        val arr = IntArray(3)
        @Suppress("UNUSED_VARIABLE")
        val x = arr[99]
    }

    private fun crashClassCast() {
        val any: Any = "not-a-number"
        @Suppress("UNCHECKED_CAST")
        val n = any as Int
        println(n)
    }

    private fun crashDivideByZero() {
        val a = 1; val b = 0
        println(a / b)
    }

    private fun crashNumberFormat() {
        "not-a-number".toInt()
    }

    private fun crashIllegalState() {
        check(false) { "object in invalid state" }
    }

    private fun crashIllegalArgument() {
        require(false) { "amount must be positive" }
    }

    private fun crashConcurrentModification() {
        val list = mutableListOf(1, 2, 3, 4, 5)
        for (item in list) { list.remove(item) }
    }

    private fun crashStackOverflow() {
        infiniteRecurse(0)
    }

    private fun infiniteRecurse(n: Int): Int = infiniteRecurse(n + 1) + 1

    private fun crashStringIndex() {
        val s = "hello"
        println(s[999])
    }

    private fun crashNegativeArraySize() {
        @Suppress("UNUSED_VARIABLE")
        val arr = IntArray(-1)
    }

    private fun crashAssertionError() {
        throw AssertionError("assertion failed in payment validator")
    }

    private fun crashUnsatisfiedLink() {
        throw UnsatisfiedLinkError("no native-lib in java.library.path")
    }

    // ── Background-thread JVM ──────────────────────────────────────────────

    private fun crashRuntimeBackgroundThread() {
        Thread {
            throw RuntimeException("unhandled exception on worker thread")
        }.apply { name = "worker-thread" }.start()
        Thread.sleep(SIGNAL_WAIT_MS)
    }

    private fun crashCoroutineIO() {
        CoroutineScope(Dispatchers.IO).launch {
            throw IllegalStateException("illegal state in coroutine on IO dispatcher")
        }
        Thread.sleep(SIGNAL_WAIT_MS)
    }

    private fun crashOomAllocatorThread() {
        Thread {
            val sink = mutableListOf<ByteArray>()
            while (true) { sink.add(ByteArray(2 * 1024 * 1024)) }
        }.apply { name = "oom-allocator" }.start()
        Thread.sleep(SIGNAL_WAIT_MS * 10) // OOM takes longer
    }

    // ── Native signals — NO shared helper so each has a distinct top frame ─

    private fun crashNativeSigsegv() {
        Thread { Thread.sleep(80); Os.kill(Os.getpid(), OsConstants.SIGSEGV) }
            .apply { name = "sig-sigsegv" }.start()
        Thread.sleep(SIGNAL_WAIT_MS)
    }

    private fun crashNativeSigbus() {
        Thread { Thread.sleep(80); Os.kill(Os.getpid(), OsConstants.SIGBUS) }
            .apply { name = "sig-sigbus" }.start()
        Thread.sleep(SIGNAL_WAIT_MS)
    }

    private fun crashNativeSigabrt() {
        Thread { Thread.sleep(80); Os.kill(Os.getpid(), OsConstants.SIGABRT) }
            .apply { name = "sig-sigabrt" }.start()
        Thread.sleep(SIGNAL_WAIT_MS)
    }

    private fun crashNativeSigfpe() {
        Thread { Thread.sleep(80); Os.kill(Os.getpid(), OsConstants.SIGFPE) }
            .apply { name = "sig-sigfpe" }.start()
        Thread.sleep(SIGNAL_WAIT_MS)
    }

    private const val SIGNAL_WAIT_MS = 500L
}
