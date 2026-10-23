package org.wikipedia.bitdriftdev

import android.system.Os
import android.system.OsConstants

/**
 * Triggers a native crash (SIGSEGV) so the next launch exercises Capture's native crash
 * reporting, including tombstone parsing via protobuf. Also triggers an ANR by blocking
 * the main thread.
 */
object DebugCrasher {

    @JvmStatic fun forceNativeCrash() {
        // A real invalid memory write inside the process gives the OS a full tombstone.
        runCatching {
            val unsafeClass = Class.forName("sun.misc.Unsafe")
            val field = unsafeClass.getDeclaredField("theUnsafe").apply { isAccessible = true }
            val unsafe = field.get(null)
            unsafeClass.getMethod("putLong", Long::class.javaPrimitiveType, Long::class.javaPrimitiveType)
                .invoke(unsafe, 0L, 0L)
        }
        // Fallback if the write above isn't available: signal ourselves, like Capture's test app does.
        Os.kill(Os.getpid(), OsConstants.SIGSEGV)
    }

    /**
     * Blocks the main thread so the system raises an ANR. Blocking alone isn't enough: Android
     * only declares an ANR when an input event goes undelivered for ~5s, so tap the screen after
     * triggering this. Choose "Close app" on the ANR dialog so ApplicationExitInfo records
     * REASON_ANR, which Capture reports on the next launch.
     */
    @JvmStatic fun forceAnr(blockMs: Long = 60_000L) {
        val end = System.currentTimeMillis() + blockMs
        while (System.currentTimeMillis() < end) {
            try {
                Thread.sleep(end - System.currentTimeMillis())
            } catch (_: InterruptedException) {
                // Keep blocking.
            }
        }
    }
}
