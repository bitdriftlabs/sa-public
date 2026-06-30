package com.example.metricdemo

import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.example.metricdemo.ui.theme.MetricdemoTheme
import io.bitdrift.capture.Capture.Logger
import kotlin.time.Duration.Companion.nanoseconds

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MetricdemoTheme {
                MetricsScreen()
            }
        }
        window.decorView.post {
            val durationNs = SystemClock.elapsedRealtimeNanos() - MetricDemoApp.appStartNs
            Logger.logAppLaunchTTI(durationNs.nanoseconds)
        }
    }
}
