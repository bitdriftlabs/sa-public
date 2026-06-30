package ai.bitdrift.manualtracing

import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.network.HttpRequestInfo
import io.bitdrift.capture.network.HttpResponse
import io.bitdrift.capture.network.HttpResponseInfo
import io.bitdrift.capture.network.HttpUrlPath
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom

data class RequestResult(
    val url: String,
    val method: String,
    val statusCode: Int?,
    val durationMs: Long,
    val traceId: String?,
    val success: Boolean,
    val error: String? = null,
    val clientType: String = "HttpURLConnection",
    val stepName: String? = null,
)

/**
 * Manually-instrumented HTTP client using raw HttpURLConnection.
 *
 * This is the manual tracing counterpart to [OkHttpNetworkClient]. Where OkHttp delegates
 * everything to two SDK components (CaptureOkHttpEventListenerFactory + CaptureOkHttpTracingInterceptor),
 * this client wires the same four concerns by hand:
 *
 *   1. SPAN CREATION  — Call Logger.log(HttpRequestInfo) before the request and
 *                       Logger.log(HttpResponseInfo) after. The SDK assigns a shared _span_id
 *                       to both calls, turning them into a matched start/end span pair in the
 *                       bitdrift timeline. Passing the same HttpRequestInfo instance to
 *                       HttpResponseInfo is what links them — do not create a new instance for
 *                       the response.
 *
 *   2. TRACE GATING   — Logger.isTracingActive is true when a bitdrift workflow has fired a
 *                       StartTracing action for this session. Only generate trace context when
 *                       it is true; when false or null (SDK not yet started) skip it so no
 *                       placeholder data pollutes the timeline.
 *
 *   3. TRACE CONTEXT  — Generate a valid W3C traceparent (version 00, 128-bit traceId,
 *                       64-bit spanId, sampled flag 01) and inject it into the outgoing
 *                       HttpURLConnection so downstream services can join the distributed trace.
 *                       Any cryptographically-random hex IDs are acceptable here — the SDK does
 *                       not require its own ID factory.
 *
 *   4. _trace_id FIELD — The SDK does NOT automatically extract _trace_id from the traceparent
 *                        header in HttpRequestInfo.headers. It must be set explicitly in
 *                        HttpResponseInfo.extraFields. This matches what CaptureOkHttpEventListener
 *                        does internally via buildExtraFieldsWithOptionalTraceId. Without this
 *                        field, the "View Trace" link will not appear in the bitdrift timeline
 *                        even if the traceparent header is present on the wire.
 */
object ManualHttpClient {

    private val secureRandom = SecureRandom()

    fun execute(url: String, method: String = "GET"): RequestResult {
        val parsedUrl = URL(url)
        val host = parsedUrl.host
        val path = parsedUrl.path.ifEmpty { "/" }
        val query = parsedUrl.query

        // ── Step 1: generate trace context if this session is being traced ────────────────────
        //
        // Logger.isTracingActive is set to true by a bitdrift workflow StartTracing action.
        // The app emits a "manual_tracing_started" log with manual_tracing=true at the start
        // of each journey; a deployed workflow matches that field and fires the action.
        // NetworkViewModel.awaitTracingActive() polls this flag before starting requests so
        // the first request in the journey always has a trace context available.
        val headers = mutableMapOf<String, String>()
        var traceId: String? = null

        if (Logger.isTracingActive == true) {
            traceId = generateHex(16)   // 128-bit / 32 hex chars  (OTel traceId)
            val spanId = generateHex(8) //  64-bit / 16 hex chars  (OTel spanId / W3C parentId)
            // W3C Trace Context v0: "00-<traceId>-<parentId>-<flags>"  flags=01 means sampled
            headers["traceparent"] = "00-$traceId-$spanId-01"
        }

        // ── Step 2: open the bitdrift request span ────────────────────────────────────────────
        //
        // Logger.log(HttpRequestInfo) writes an HTTPRequest log (span_type=start) and internally
        // assigns a UUID _span_id. That same instance must be passed to HttpResponseInfo so the
        // SDK can emit the matching HTTPResponse log (span_type=end) under the same _span_id.
        val requestInfo = HttpRequestInfo(
            method = method,
            host = host,
            path = HttpUrlPath(value = path),
            query = query,
            headers = headers, // headers are logged as-is; traceparent propagates to the server
        )
        Logger.log(requestInfo)

        val startMs = System.currentTimeMillis()

        // ── Step 3: make the actual HTTP call ─────────────────────────────────────────────────
        return try {
            val connection = (parsedUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 10_000
                readTimeout = 10_000
                headers.forEach { (k, v) -> setRequestProperty(k, v) } // propagate traceparent to server
            }

            val statusCode = connection.responseCode
            val durationMs = System.currentTimeMillis() - startMs

            val responseHeaders: Map<String, String> = connection.headerFields
                .entries
                .filter { it.key != null }
                .associate { it.key to it.value.joinToString(", ") }

            connection.disconnect()

            // ── Step 4: close the bitdrift response span ──────────────────────────────────────
            //
            // _trace_id must go in extraFields explicitly. The SDK does not parse the traceparent
            // from HttpRequestInfo.headers — that extraction only happens inside the OkHttp
            // event listener (CaptureOkHttpEventListener.buildExtraFieldsWithOptionalTraceId).
            // For manual instrumentation we own the traceId string and just pass it directly.
            Logger.log(
                HttpResponseInfo(
                    request = requestInfo,   // same instance → same _span_id → matched span
                    response = HttpResponse(
                        result = if (statusCode in 200..399) HttpResponse.HttpResult.SUCCESS
                                 else HttpResponse.HttpResult.FAILURE,
                        statusCode = statusCode,
                        headers = responseHeaders,
                    ),
                    durationMs = durationMs,
                    extraFields = if (traceId != null) mapOf("_trace_id" to traceId) else emptyMap(),
                ),
            )

            RequestResult(url, method, statusCode, durationMs, traceId, statusCode in 200..399)
        } catch (e: Exception) {
            val durationMs = System.currentTimeMillis() - startMs

            Logger.log(
                HttpResponseInfo(
                    request = requestInfo,
                    response = HttpResponse(
                        result = HttpResponse.HttpResult.FAILURE,
                        error = e,
                    ),
                    durationMs = durationMs,
                    extraFields = if (traceId != null) mapOf("_trace_id" to traceId) else emptyMap(),
                ),
            )

            RequestResult(url, method, null, durationMs, traceId, false, e.message)
        }
    }

    private fun generateHex(byteCount: Int): String {
        val bytes = ByteArray(byteCount)
        secureRandom.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
