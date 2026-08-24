package com.analytics.fake

import okhttp3.Interceptor
import okhttp3.Response

/**
 * Demo stand-in for a third-party analytics SDK's OkHttp interceptor — a second,
 * distinct vendor namespace so the resulting BDRL chart has more than one bucket
 * to compare instead of a binary "this vendor or app code" switch.
 */
class AnalyticsPingInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        throw IllegalStateException("AnalyticsSDK: ping batch serialization failed")
    }
}
