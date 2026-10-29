package org.wikipedia.bitdriftdev

import java.util.concurrent.atomic.AtomicBoolean

object DebugLeaker {
    private val running = AtomicBoolean(false)
    private val oomList = mutableListOf<ByteArray>()

    /** Fast: allocate ~1 MB every 50ms until OOM */
    @JvmStatic fun forceOutOfMemoryCrash() {
        if (!running.compareAndSet(false, true)) return
        Thread({
            while (true) {
                oomList.add(ByteArray(1024 * 1024))
                try { Thread.sleep(50) } catch (_: InterruptedException) {}
            }
        }, "BitdriftDev-OOM").start()
    }

    /** Slow: allocate ~256 KB every 500ms to demo “leaky” jank without instant crash */
    @JvmStatic fun startSlowLeak() {
        if (!running.compareAndSet(false, true)) return
        Thread({
            while (true) {
                oomList.add(ByteArray(256 * 1024))
                try { Thread.sleep(500) } catch (_: InterruptedException) {}
            }
        }, "BitdriftDev-SlowLeak").start()
    }
}
