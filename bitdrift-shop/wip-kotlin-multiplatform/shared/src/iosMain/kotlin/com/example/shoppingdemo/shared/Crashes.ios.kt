package ai.bitdrift.shop.shared

import platform.posix.SIGABRT
import platform.posix.SIGBUS
import platform.posix.SIGFPE
import platform.posix.SIGSEGV
import platform.posix.getpid
import platform.posix.kill
import kotlin.system.exitProcess

// Native signals via POSIX — same approach as the Android Os.kill path.

internal actual fun platformNativeSigsegv() { kill(getpid(), SIGSEGV) }

internal actual fun platformNativeSigbus() { kill(getpid(), SIGBUS) }

internal actual fun platformNativeSigabrt() { kill(getpid(), SIGABRT) }

internal actual fun platformNativeSigfpe() { kill(getpid(), SIGFPE) }

// iOS has no JNI / JVM linkage; use SIGABRT as the closest analog.
internal actual fun platformUnsatisfiedLink() { kill(getpid(), SIGABRT) }

internal actual fun platformBlockMainThread(ms: Long) {
    // On iOS the Kotlin coroutine runs on the main thread; sleeping here blocks it.
    platform.Foundation.NSThread.sleepForTimeInterval(ms / 1000.0)
    while (true) { platform.Foundation.NSThread.sleepForTimeInterval(60.0) }
}

internal actual fun platformForceQuit() {
    exitProcess(0)
}
