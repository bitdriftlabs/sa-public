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

    // OOM variants, each exercising a different allocation path/thread context so they
    // land as distinct issue groups and cover different real-world OOM shapes. Kept as
    // its own list so the "OOMs" crash-loop mode can cycle through only these.
    private val oomCrashes: List<Pair<String, () -> Unit>> = listOf(
        "oom_allocator_thread"      to ::crashOomAllocatorThread,
        "oom_main_thread"           to ::crashOomMainThread,
        "oom_single_allocation"     to ::crashOomSingleAllocation,
        "oom_native_thread"         to ::crashOomNativeThreadExhaustion,
        "oom_bitmap_decode"         to ::crashOomBitmapDecode,
        "oom_cache_growth"          to ::crashOomCacheGrowth,
    )

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
    ) + oomCrashes

    // Subset used by the "OOMs" crash-loop mode (Advanced screen) to cycle through
    // only out-of-memory variants.
    val oomOnly: List<Pair<String, () -> Unit>> = oomCrashes

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

    // A step delay is threaded through each gradual OOM loop below so the climb
    // takes ~20-30s instead of well under a second. Reasons this matters, not just
    // "make it slower": bitdrift's Resource Utilization panel is a periodic snapshot
    // on a 3s capture interval (confirmed live) -- a session that dies in under 3s
    // never gets a single sample, and one that dies in ~5s gets one, which reads as
    // a flat point, not a graph. Pacing each loop to run for several capture ticks
    // produces an actual rising memory curve. crashOomSingleAllocation is
    // deliberately excluded -- it represents the opposite case (a single allocation
    // failing instantly) and pacing it would defeat that contrast.
    private fun crashOomAllocatorThread() {
        Thread {
            val sink = mutableListOf<ByteArray>()
            while (true) {
                sink.add(ByteArray(2 * 1024 * 1024))
                Thread.sleep(BYTE_ARRAY_STEP_DELAY_MS)
            }
        }.apply { name = "oom-allocator" }.start()
        Thread.sleep(OOM_GRADUAL_WAIT_MS)
    }

    // ── OOM variants ────────────────────────────────────────────────────────

    // Same gradual accumulation as crashOomAllocatorThread, but on the calling
    // (main) thread directly — top frame and thread attribution differ from the
    // background-thread variant above.
    private fun crashOomMainThread() {
        val sink = mutableListOf<ByteArray>()
        while (true) {
            sink.add(ByteArray(2 * 1024 * 1024))
            Thread.sleep(BYTE_ARRAY_STEP_DELAY_MS)
        }
    }

    // A single allocation that exceeds the max array/heap size fails immediately,
    // rather than the gradual "death by a thousand allocations" pattern above —
    // a distinct OOM message shape ("won't fit in your heap"). Deliberately not
    // paced -- see the note above the first gradual crash.
    private fun crashOomSingleAllocation() {
        @Suppress("UNUSED_VARIABLE")
        val giant = ByteArray(Int.MAX_VALUE - 8)
    }

    // Native thread exhaustion, not Java heap exhaustion: leaks threads (each parked
    // forever) until the OS refuses to create another one. Common in real apps with
    // a leaking thread pool/executor. Surfaces as "OutOfMemoryError: pthread_create
    // failed" rather than a heap-allocation failure.
    //
    // Each leaked thread requests a 128MB stack so a handful of threads (not
    // thousands) exhausts address space -- confirmed live that the default ~1MB
    // stack made this open-ended and unpredictably slow (multiple minutes on an
    // emulator with several GB of RAM), which raced badly against the crash-loop's
    // restart alarm; see SimulationManager.OOM_CRASH_RESTART_DELAY_MS.
    private fun crashOomNativeThreadExhaustion() {
        Thread {
            val leaked = mutableListOf<Thread>()
            while (true) {
                val t = Thread(null, { Thread.sleep(Long.MAX_VALUE) }, "leaked-oom-thread", 128L * 1024 * 1024)
                t.start()
                leaked.add(t)
                Thread.sleep(THREAD_SPAWN_STEP_DELAY_MS)
            }
        }.apply { name = "oom-thread-spawner" }.start()
        Thread.sleep(OOM_GRADUAL_WAIT_MS)
    }

    // Bitmap allocation is one of the most common real-world OOM sources in
    // image-heavy apps. Decodes large bitmaps in a loop without recycling —
    // stresses the graphics/bitmap allocation path rather than a plain byte buffer.
    //
    // 8192x8192 (256MB/bitmap) instead of 4096x4096 (64MB/bitmap): bitmap pixel data
    // lives in native memory with a much larger ceiling than the ~192MB Dalvik heap
    // growth limit, so fewer, bigger allocations get to that ceiling faster and more
    // predictably than many small ones -- see SimulationManager.OOM_CRASH_RESTART_DELAY_MS.
    private fun crashOomBitmapDecode() {
        Thread {
            val bitmaps = mutableListOf<android.graphics.Bitmap>()
            while (true) {
                bitmaps.add(android.graphics.Bitmap.createBitmap(8192, 8192, android.graphics.Bitmap.Config.ARGB_8888))
                Thread.sleep(BITMAP_STEP_DELAY_MS)
            }
        }.apply { name = "oom-bitmap-decode" }.start()
        Thread.sleep(OOM_GRADUAL_WAIT_MS)
    }

    // Unbounded cache growth: many small String entries rather than a few large
    // buffers. Representative of a real leak (e.g. an unbounded in-memory cache),
    // and stresses the allocator with small, high-churn objects instead of large
    // ones. Note: ART reports this the same OutOfMemoryError as the others above —
    // it doesn't have HotSpot's distinct "GC overhead limit exceeded" message — but
    // the allocation shape and top frame are still a genuinely different scenario.
    //
    // Paced in batches rather than per-entry -- these entries are cheap enough that
    // a per-entry sleep would dominate wall time over actual allocation, and a
    // periodic pause is enough to spread the climb across several capture ticks.
    private fun crashOomCacheGrowth() {
        Thread {
            val cache = HashMap<String, String>()
            var i = 0L
            while (true) {
                val key = "session-cache-key-$i"
                cache[key] = key.repeat(64)
                i++
                if (i % CACHE_GROWTH_BATCH_SIZE == 0L) Thread.sleep(CACHE_GROWTH_BATCH_DELAY_MS)
            }
        }.apply { name = "oom-cache-growth" }.start()
        Thread.sleep(OOM_GRADUAL_WAIT_MS)
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

    // How long the calling thread waits for a gradual OOM loop to actually crash the
    // process before giving up and returning normally. Comfortably above the ~20-30s
    // these loops are paced to take -- must stay under
    // SimulationManager.OOM_CRASH_RESTART_DELAY_MS or the restart alarm fires before
    // the crash does (see that constant's comment for what goes wrong when it doesn't).
    private const val OOM_GRADUAL_WAIT_MS = 35_000L
    private const val BYTE_ARRAY_STEP_DELAY_MS = 400L
    private const val THREAD_SPAWN_STEP_DELAY_MS = 700L
    private const val BITMAP_STEP_DELAY_MS = 2_000L
    private const val CACHE_GROWTH_BATCH_SIZE = 5_000L
    private const val CACHE_GROWTH_BATCH_DELAY_MS = 250L
}
