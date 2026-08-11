import Foundation

// Stand-ins for third-party SDKs, used by the vendor-SDK crash-attribution demo
// (`bd-shop-09-vendor-sdk-attribution.json`). They exist purely so a crash's
// stack carries a frame from a namespace that clearly is not the app's own —
// the iOS counterpart of the Android app's `com.adsdk.fake` /
// `com.analytics.fake` packages.
//
// Keep the two enums in distinct top-level namespaces and never route their
// crashes through a shared helper, or both land in the same issue group.

enum AdSDKFake {
    /// Simulated ad-request interceptor that trips over a malformed response.
    final class AdRequestInterceptor {
        @inline(never)
        func intercept(_ url: URL) -> Never {
            fatalError("AdSDK: malformed ad response envelope from \(url.host ?? "unknown")")
        }
    }
}

enum AnalyticsSDKFake {
    /// Simulated analytics batcher that trips over an unencodable event.
    final class AnalyticsPingInterceptor {
        @inline(never)
        func flushBatch(to url: URL) -> Never {
            fatalError("AnalyticsSDK: unencodable event in batch bound for \(url.host ?? "unknown")")
        }
    }
}
