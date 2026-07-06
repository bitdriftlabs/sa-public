package ai.bitdrift.shop

import android.system.Os
import android.system.OsConstants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request

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
        // Lock contention — real, uncorrelated thread states across three threads
        "lock_contention"           to ::crashLockContention,
        // Vendor SDK attribution — two distinct fake-vendor namespaces
        "vendor_sdk_interceptor"    to ::crashVendorSdkInterceptor,
        "vendor_sdk_analytics"      to ::crashAnalyticsSdkInterceptor,
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

    // ── Lock contention — three real, uncorrelated thread states captured ──

    private fun crashLockContention() {
        val lock = Object()
        val holderReady = java.util.concurrent.CountDownLatch(1)

        // Holds the lock without crashing itself. Keeping "holds" and "crashes" on
        // separate threads means this thread is still genuinely TIMED_WAITING —
        // still holding `lock` — at snapshot time, rather than having already
        // released the monitor via its own exception unwinding.
        Thread {
            synchronized(lock) {
                holderReady.countDown()
                Thread.sleep(LOCK_HOLD_MS)
            }
        }.apply { name = "image-decode-thread" }.start()
        holderReady.await()

        // A watchdog thread, uninvolved in the lock itself, converts the block into
        // a crash after a short, fixed delay -- independent of LOCK_HOLD_MS, so
        // there's real margin against scheduler jitter rather than a race against
        // the same window the lock holder is using. Honest about what it's doing:
        // this is a synthetic stand-in for a real ANR, deliberately turned into a
        // crash so it's guaranteed to land in the existing capture pipeline.
        Thread {
            Thread.sleep(WATCHDOG_DELAY_MS)
            throw RuntimeException(
                "anr-watchdog: main thread blocked on shared lock for ${WATCHDOG_DELAY_MS}ms " +
                    "-- converting to a crash for reporting",
            )
        }.apply { name = "anr-watchdog-thread" }.start()

        // Blocks the calling (main) thread on the same monitor for the remainder of
        // image-decode-thread's hold window — real Thread.State.BLOCKED.
        synchronized(lock) { }
    }

    // ── Vendor SDK attribution — real com.adsdk.fake./com.analytics.fake. frames ─

    private fun crashVendorSdkInterceptor() {
        val client = OkHttpClient.Builder()
            .addInterceptor(com.adsdk.fake.AdRequestInterceptor())
            .build()
        val request = Request.Builder().url("https://ads.fake-vendor.example/init").build()
        client.newCall(request).execute()
    }

    private fun crashAnalyticsSdkInterceptor() {
        val client = OkHttpClient.Builder()
            .addInterceptor(com.analytics.fake.AnalyticsPingInterceptor())
            .build()
        val request = Request.Builder().url("https://ping.fake-analytics.example/batch").build()
        client.newCall(request).execute()
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
    private const val WATCHDOG_DELAY_MS = 300L // fixed, independent of hold duration
    private const val LOCK_HOLD_MS = 2000L // wide margin vs. WATCHDOG_DELAY_MS
}
