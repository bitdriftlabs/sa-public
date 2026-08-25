package com.analytics.fake

import okhttp3.Interceptor
import okhttp3.Response

/**
 * Demo stand-in for a third-party analytics SDK's OkHttp interceptor — a second,
 * distinct vendor namespace so the crash catalog exercises multiple third-party
 * stack-grouping fixtures instead of a binary "vendor or app code" switch.
 */
class AnalyticsPingInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        throw IllegalStateException("AnalyticsSDK: ping batch serialization failed")
    }
}
