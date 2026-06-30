package ai.bitdrift.manualtracing

import io.bitdrift.capture.network.okhttp.CaptureOkHttpEventListenerFactory
import io.bitdrift.capture.network.okhttp.CaptureOkHttpTracingInterceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Auto-instrumented HTTP client using OkHttp.
 *
 * This is the auto-instrumentation counterpart to [ManualHttpClient]. The same four concerns
 * that ManualHttpClient wires by hand are handled here by two SDK components attached to the
 * OkHttpClient builder:
 *
 *   CaptureOkHttpEventListenerFactory
 *     Hooks into OkHttp's internal event callbacks (callStart, responseHeadersEnd, callEnd, etc.)
 *     to emit HTTPRequest (span_type=start) and HTTPResponse (span_type=end) logs automatically.
 *     This is the equivalent of manually calling Logger.log(HttpRequestInfo) and
 *     Logger.log(HttpResponseInfo). No application code is required.
 *
 *   CaptureOkHttpTracingInterceptor
 *     Runs in the OkHttp interceptor chain before each request. When Logger.isTracingActive is
 *     true it generates a W3C traceparent header (identical format to the one ManualHttpClient
 *     builds by hand) and injects it into the outgoing request. The event listener factory then
 *     reads the traceparent back from the finalized request via TracePropagation.extractSampledTraceId
 *     and writes _trace_id into HttpResponseInfo.extraFields — the same field ManualHttpClient
 *     sets explicitly.
 *
 * Both components are required. The event listener alone produces the span structure but will
 * not produce _trace_id, because it only reads traceparent after the interceptor has injected it.
 */
object OkHttpNetworkClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .addInterceptor(CaptureOkHttpTracingInterceptor())       // injects traceparent when tracing active
        .eventListenerFactory(CaptureOkHttpEventListenerFactory()) // emits span logs + _trace_id
        .build()

    fun execute(url: String, method: String = "GET"): RequestResult {
        val startMs = System.currentTimeMillis()
        val request = Request.Builder().url(url).build()
        return try {
            client.newCall(request).execute().use { response ->
                val durationMs = System.currentTimeMillis() - startMs
                RequestResult(
                    url = url,
                    method = method,
                    statusCode = response.code,
                    durationMs = durationMs,
                    traceId = null, // SDK handles _trace_id internally; not surfaced here
                    success = response.code in 200..399,
                    clientType = "OkHttp",
                )
            }
        } catch (e: Exception) {
            val durationMs = System.currentTimeMillis() - startMs
            RequestResult(
                url = url,
                method = method,
                statusCode = null,
                durationMs = durationMs,
                traceId = null,
                success = false,
                error = e.message,
                clientType = "OkHttp",
            )
        }
    }
}
