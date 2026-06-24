package ai.bitdrift.shop

import android.app.Application
import android.util.Log
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.session.SessionStrategy
import okhttp3.HttpUrl

class ShoppingDemoApp : Application() {
    override fun onCreate() {
        super.onCreate()

        Logger.start(
            apiKey = BuildConfig.BITDRIFT_SDK_KEY,
            apiUrl = HttpUrl.Builder()
                .scheme("https")
                .host(BuildConfig.BITDRIFT_API_HOST)
                .build(),
            sessionStrategy = SessionStrategy.Fixed(),
        )

        Logger.addField("app_variant", "kmp-demo")

        Log.d(TAG, "ShoppingDemo KMP app launched")
        Logger.logInfo { "app_launched" }
    }

    companion object {
        private const val TAG = "ShoppingDemoKMP"
    }
}
