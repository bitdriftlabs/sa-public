package com.adsdk.fake

import okhttp3.Interceptor
import okhttp3.Response

/**
 * Demo stand-in for a third-party ad SDK's OkHttp interceptor. Throws before the
 * request reaches the network, so the crash carries real com.adsdk.fake.* frames
 * with no dependency on network reachability.
 */
class AdRequestInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        throw IllegalStateException("AdSDK: native ad renderer failed to initialize")
    }
}
