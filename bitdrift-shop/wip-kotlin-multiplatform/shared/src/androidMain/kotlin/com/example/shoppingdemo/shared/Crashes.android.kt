package ai.bitdrift.shop.shared

import android.os.Handler
import android.os.Looper
import android.os.Process
import android.system.Os
import android.system.OsConstants
import kotlin.system.exitProcess

internal actual fun platformNativeSigsegv() {
    Thread { Os.kill(Os.getpid(), OsConstants.SIGSEGV) }.start()
}

internal actual fun platformNativeSigbus() {
    Thread { Os.kill(Os.getpid(), OsConstants.SIGBUS) }.start()
}

internal actual fun platformNativeSigabrt() {
    Thread { Os.kill(Os.getpid(), OsConstants.SIGABRT) }.start()
}

internal actual fun platformNativeSigfpe() {
    Thread { Os.kill(Os.getpid(), OsConstants.SIGFPE) }.start()
}

internal actual fun platformUnsatisfiedLink() {
    System.loadLibrary("bd_does_not_exist")
}

internal actual fun platformBlockMainThread(ms: Long) {
    // Blocks the main thread directly — triggers the ANR watchdog after ~5 s.
    Handler(Looper.getMainLooper()).post {
        Thread.sleep(ms)
        @Suppress("ControlFlowWithEmptyBody")
        while (true) { Thread.sleep(60_000L) }
    }
}

internal actual fun platformForceQuit() {
    Process.killProcess(Process.myPid())
    exitProcess(0)
}
