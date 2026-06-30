package ai.bitdrift.manualtracing

import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import ai.bitdrift.manualtracing.ui.theme.ManualTracingTheme
import io.bitdrift.capture.Capture.Logger
import kotlin.time.Duration.Companion.nanoseconds

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ManualTracingTheme {
                TracingScreen()
            }
        }
        window.decorView.post {
            val durationNs = SystemClock.elapsedRealtimeNanos() - TraceDemoApp.appStartNs
            Logger.logAppLaunchTTI(durationNs.nanoseconds)
        }
    }
}
