package ai.bitdrift.shop

import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import kotlin.system.exitProcess

/**
 * Native crash module for the React Native demo — the RN counterpart to the Android
 * app's Crashes.kt native-signal variants. Each native signal method calls Os.kill
 * DIRECTLY (not via a shared helper) so each crash has a distinct top frame and
 * bitdrift's issue grouper places them in separate groups, exactly as on Android.
 *
 * Exposed to JS as NativeModules.BdCrash (see src/sim/crashes.ts).
 */
class BdCrashModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String = "BdCrash"

  @ReactMethod
  fun nativeSigsegv() {
    Thread {
      Os.kill(Os.getpid(), OsConstants.SIGSEGV)
    }.start()
  }

  @ReactMethod
  fun nativeSigbus() {
    Thread {
      Os.kill(Os.getpid(), OsConstants.SIGBUS)
    }.start()
  }

  @ReactMethod
  fun nativeSigabrt() {
    Thread {
      Os.kill(Os.getpid(), OsConstants.SIGABRT)
    }.start()
  }

  @ReactMethod
  fun nativeSigfpe() {
    Thread {
      Os.kill(Os.getpid(), OsConstants.SIGFPE)
    }.start()
  }

  @ReactMethod
  fun unsatisfiedLink() {
    // Loading a non-existent native library throws UnsatisfiedLinkError.
    System.loadLibrary("bd_does_not_exist")
  }

  /** True ANR: block the main (UI) thread so Android's input dispatcher detects it. */
  @ReactMethod
  fun blockMainThread(ms: Double) {
    Handler(Looper.getMainLooper()).post {
      try {
        Thread.sleep(ms.toLong())
      } catch (_: InterruptedException) {
      }
      // Hard freeze loop, mirroring the Android app's infinite freeze after the block.
      while (true) {
        try {
          Thread.sleep(60000L)
        } catch (_: InterruptedException) {
        }
      }
    }
  }

  /** Hard process exit — the closest RN equivalent of a user force-quit. */
  @ReactMethod
  fun forceQuit() {
    android.os.Process.killProcess(android.os.Process.myPid())
    exitProcess(0)
  }
}
