package ai.bitdrift.manualtracing

import android.app.Application
import android.os.SystemClock
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.session.SessionStrategy
import okhttp3.HttpUrl

class TraceDemoApp : Application() {

    override fun onCreate() {
        appStartNs = SystemClock.elapsedRealtimeNanos()
        super.onCreate()

        Logger.start(
            apiKey = BuildConfig.BITDRIFT_SDK_KEY,
            apiUrl = HttpUrl.Builder().scheme("https").host(BuildConfig.BITDRIFT_API_HOST).build(),
            sessionStrategy = SessionStrategy.Fixed(),
        )

        registerActivityLifecycleCallbacks(AppLifecycleCallbacks())
    }

    companion object {
        var appStartNs: Long = 0
    }
}
