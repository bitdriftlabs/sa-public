# Manual Tracing Demo (Android)

Demonstrates the contrast between **manual** network instrumentation (`HttpURLConnection`) and **automatic** instrumentation (`OkHttp`) using the bitdrift Capture SDK. The app shows side-by-side how both approaches produce the same bitdrift log structure, and how `_trace_id` appears on response logs when a tracing workflow is active.

## What it shows

- **Loop Journey (URLConnection) / Run 5x Journey (URLConnection)** — simulates a 10-step shopping journey via raw `HttpURLConnection`, manually instrumented with `Logger.log(HttpRequestInfo)` / `Logger.log(HttpResponseInfo)`. Each step logs a screen view or action event with contextual fields, then fires one network request. Loop repeats indefinitely; each journey starts a new bitdrift session via `Logger.startNewSession()`. Run 5x Journey executes five complete journeys back-to-back, each as its own session.
- **Loop Journey (OkHttp) / Run 5x Journey (OkHttp)** — fires rotating requests via `OkHttpClient` with `CaptureOkHttpEventListenerFactory` and `CaptureOkHttpTracingInterceptor` attached. No manual logging code needed — the SDK handles everything automatically. Run 5x Journey creates five separate sessions.
- A live **Tracing Active / Inactive** badge driven by polling `Logger.isTracingActive`.
- A **Device Code** button (with one-tap copy) to stream logs live in the bitdrift dashboard.

Each URLConnection request card shows the shopping step name, HTTP status, duration, and trace status.

---

## Shopping journey steps

Each Loop Journey / Run 5x Journey (URLConnection) run walks through this 10-step journey. Every step emits a bitdrift log event with screen/action fields, then makes one real HTTPS request to a public placeholder API (no backend required).

| # | Screen | Event logged | Key fields | Network call |
|---|--------|-------------|------------|--------------|
| 1 | Welcome | `screen_view` | `_screen_name=Welcome` | `GET /posts/1` |
| 2 | Browse | `screen_view` | `_screen_name=Browse` | `GET /users/1` |
| 3 | Search | `screen_view` | `_screen_name=Search`, `query=headphones` | `GET /todos/1` |
| 4 | Featured | `screen_view` | `_screen_name=Featured` | `GET /albums/1` |
| 5 | ProductDetail | `screen_view` | `_screen_name=ProductDetail`, `product_id=p42`, `source_screen=Featured` | `GET /photos/1` |
| 6 | Reviews | `screen_view` | `_screen_name=Reviews`, `product_id=p42` | `GET /comments/1` |
| 7 | Cart | `add_to_cart` | `_screen_name=Cart`, `product_id=p42`, `source_screen=Reviews` | `GET /posts/2` |
| 8 | CheckoutGuest | `checkout_started` | `_screen_name=CheckoutGuest`, `checkout_type=guest` | `GET /users/1` |
| 9 | PaymentCard | `screen_view` | `_screen_name=PaymentCard`, `payment_method=card` | `GET /todos/1` |
| 10 | Confirmation | `payment_completed` | `_screen_name=Confirmation`, `payment_method=card`, `order_id=ord-demo` | `GET /albums/1` |

All network calls go to `jsonplaceholder.typicode.com`. The journey is self-contained — no local server or backend setup needed.

At the start of each journey, `Logger.startNewSession()` is called so each run appears as a distinct session in the bitdrift timeline. The app then logs a `manual_tracing_started` event with `manual_tracing=true` and waits until `Logger.isTracingActive` flips to `true` (workflow round-trip) before firing any network requests, ensuring every request in the journey carries a `_trace_id`.

---

## How the log structure works

Every instrumented network request produces a **span** in bitdrift: a matched start/end log pair linked by a shared `_span_id`. Whether you use OkHttp auto-instrumentation or the manual API, the structure in the timeline is identical:

| Field | Request log | Response log |
|---|---|---|
| `_span_id` | UUID assigned by SDK | Same UUID |
| `_span_name` | `_http` | `_http` |
| `_span_type` | `start` | `end` |
| `_method` | e.g. `GET` | e.g. `GET` |
| `_host` | e.g. `jsonplaceholder.typicode.com` | same |
| `_path` | e.g. `/posts/1` | same |
| `_status_code` | — | e.g. `200` |
| `_duration_ms` | — | e.g. `142` |
| `_result` | — | `success` / `failure` |
| `_trace_id` | — | present only when tracing is active |

`_trace_id` on the response log is what enables the **View Trace** link in the bitdrift timeline and connects the session to your APM system.

---

## Manual instrumentation vs auto-instrumentation

The two clients in this app produce identical log output but wire the same four concerns in completely different ways.

### The four concerns

| # | Concern | Manual (URLConnection) | Auto (OkHttp) |
|---|---|---|---|
| 1 | **Span creation** | `Logger.log(HttpRequestInfo)` / `Logger.log(HttpResponseInfo)` called explicitly | `CaptureOkHttpEventListenerFactory` hooks OkHttp's internal events and emits both logs automatically |
| 2 | **Trace gating** | App code checks `Logger.isTracingActive` before generating trace context | `CaptureOkHttpTracingInterceptor` checks `Logger.isTracingActive` inside the interceptor chain |
| 3 | **Trace header** | App generates a W3C `traceparent` and sets it on `HttpURLConnection` via `setRequestProperty` | Interceptor generates the `traceparent` and injects it into the OkHttp `Request` before it leaves the chain |
| 4 | **`_trace_id` field** | App passes `extraFields = mapOf("_trace_id" to traceId)` to `HttpResponseInfo` explicitly | Event listener calls `TracePropagation.extractSampledTraceId(request)` to read back the injected header, then sets `_trace_id` in `extraFields` |

The key non-obvious point is concern 4: **the SDK does not automatically extract `_trace_id` from the `traceparent` header you pass to `HttpRequestInfo.headers`**. For manual instrumentation you own the trace ID string and must pass it directly to `HttpResponseInfo.extraFields`. Without it the span is logged and the `traceparent` propagates to the server, but the "View Trace" link will not appear in the bitdrift timeline.

---

## How tracing works — URLConnection path

Source: [`ManualHttpClient.kt`](app/src/main/java/ai/bitdrift/manualtracing/ManualHttpClient.kt)

```kotlin
// 1. Gate on isTracingActive — only generate trace context when a workflow has activated tracing.
val headers = mutableMapOf<String, String>()
var traceId: String? = null

if (Logger.isTracingActive == true) {
    traceId = generateHex(16)   // 128-bit OTel traceId (32 hex chars)
    val spanId = generateHex(8) //  64-bit OTel spanId  (16 hex chars)
    headers["traceparent"] = "00-$traceId-$spanId-01"  // W3C Trace Context v0, sampled
}

// 2. Open the span. The SDK assigns a _span_id and emits an HTTPRequest log (span_type=start).
val requestInfo = HttpRequestInfo(
    method = method, host = host,
    path = HttpUrlPath(value = path), query = query,
    headers = headers,  // logged as-is; traceparent propagates to the server
)
Logger.log(requestInfo)

// 3. Make the actual HTTP call and inject the traceparent so the backend can join the trace.
val connection = (URL(url).openConnection() as HttpURLConnection).apply {
    headers.forEach { (k, v) -> setRequestProperty(k, v) }
}

// 4. Close the span. Pass the same requestInfo instance so the SDK links both logs via _span_id.
//    Set _trace_id explicitly in extraFields — the SDK does not read it from HttpRequestInfo.headers.
Logger.log(
    HttpResponseInfo(
        request = requestInfo,
        response = HttpResponse(result = ..., statusCode = statusCode),
        durationMs = durationMs,
        extraFields = if (traceId != null) mapOf("_trace_id" to traceId) else emptyMap(),
    )
)
```

`Logger.isTracingActive` is set by a bitdrift **workflow** with a **Start Tracing** action. The app emits a `manual_tracing_started` log (with `manual_tracing=true`) at the beginning of each journey. The deployed workflow matches that field and fires the action. Because the workflow round-trip takes a moment, `NetworkViewModel` polls `isTracingActive` after logging the trigger event and only starts making requests once it flips to `true`.

---

## How tracing works — OkHttp path

Source: [`OkHttpNetworkClient.kt`](app/src/main/java/ai/bitdrift/manualtracing/OkHttpNetworkClient.kt)

```kotlin
val client = OkHttpClient.Builder()
    .addInterceptor(CaptureOkHttpTracingInterceptor())        // concern 2 + 3: gating + header injection
    .eventListenerFactory(CaptureOkHttpEventListenerFactory()) // concern 1 + 4: span logs + _trace_id
    .build()
```

**`CaptureOkHttpEventListenerFactory`** hooks OkHttp's internal lifecycle events to emit `HTTPRequest` / `HTTPResponse` log pairs automatically — the equivalent of the manual `Logger.log(HttpRequestInfo)` / `Logger.log(HttpResponseInfo)` calls. It also reads the `traceparent` header back from the finalized request (after the interceptor has injected it) and writes `_trace_id` into `HttpResponseInfo.extraFields`, which is the same field the manual client sets explicitly.

**`CaptureOkHttpTracingInterceptor`** sits in the interceptor chain and, when `Logger.isTracingActive == true`, generates a W3C `traceparent` and adds it to the request before it leaves the chain — the same header the manual client builds and sets via `setRequestProperty`.

Both components are required. The event listener alone produces the full span structure but **will not produce `_trace_id`**, because it reads `traceparent` from the request after the interceptor chain — if the interceptor is absent there is no header to read.

---

## Setup

1. Copy your SDK key and (optionally) API host into `.local.properties` at the project root:

```
BITDRIFT_SDK_KEY=your-key-here
# BITDRIFT_API_HOST=api.bitdrift.io   # default; override only if needed
```

2. Open the project in Android Studio and run the `app` configuration on a device or emulator (API 26+).

3. Tap **Device Code** to get a temporary code; tap **Copy & Close** to copy it, then enter it in the bitdrift dashboard to stream logs from this device live.

4. Tap **Loop Journey** (URLConnection or OkHttp) to start firing requests continuously. Tap again to stop. Or tap **Run 5x Journey** to run five complete journeys back-to-back, each as a new session.

5. Activate a **Start Tracing** workflow in the dashboard and watch `_trace_id` appear on response logs for both client types. The workflow files are included in this repo — see [Workflows](#workflows) below.

---

## Workflows

Two workflows are included, one per client type:

| File | Matches | Purpose | Live URL |
|---|---|---|---|
| [`workflow-manual-tracing.json`](workflow-manual-tracing.json) | `manual_tracing=true` field | URLConnection sessions | https://explorations.bitdrift.io/workflow/1iBn |
| [`workflow-manual-tracing-metadata.json`](workflow-manual-tracing-metadata.json) | — | Metadata for above | — |
| [`workflow-auto-tracing.json`](workflow-auto-tracing.json) | Any log (`REGEX .*`) | OkHttp sessions | https://explorations.bitdrift.io/workflow/8jAN |
| [`workflow-auto-tracing-metadata.json`](workflow-auto-tracing-metadata.json) | — | Metadata for above | — |

Both workflows fire the same two actions: `start_tracing_rule` (flips `Logger.isTracingActive` to `true`, enabling `traceparent` injection and `_trace_id` on all response logs in that session) and `flush_rule` (uploads the captured session to the bitdrift timeline, limit 100/day).

**URLConnection workflow** matches on the `manual_tracing=true` field logged by `NetworkViewModel` at the start of each journey. The app polls `isTracingActive` and waits for the workflow round-trip before firing any requests, so every request in the journey carries a `_trace_id`.

**OkHttp workflow** matches on any log message (`REGEX .*`), which fires immediately on the first log of each OkHttp session. `CaptureOkHttpTracingInterceptor` reads `isTracingActive` per-request so it picks up tracing as soon as the workflow responds.

**To deploy:**

```bash
# URLConnection workflow (manual tracing)
bd workflow create \
  --metadata-file workflow-manual-tracing-metadata.json \
  --deploy \
  workflow-manual-tracing.json

# OkHttp workflow (auto tracing)
bd workflow create \
  --metadata-file workflow-auto-tracing-metadata.json \
  --deploy \
  workflow-auto-tracing.json
```

---

## Key APIs used

### bitdrift Capture SDK

| API | Where | Purpose |
|---|---|---|
| `Logger.start(...)` | `TraceDemoApp.kt` | SDK initialization |
| `Logger.isTracingActive` | `ManualHttpClient.kt`, `NetworkViewModel.kt` | Gate for traceparent injection; polled until `true` before journey starts |
| `Logger.log(HttpRequestInfo)` | `ManualHttpClient.kt` | Opens the HTTP span — emits HTTPRequest log (`_span_type=start`) |
| `Logger.log(HttpResponseInfo)` | `ManualHttpClient.kt` | Closes the HTTP span — emits HTTPResponse log (`_span_type=end`) with `_trace_id` |
| `Logger.log(level, fields) { message }` | `NetworkViewModel.kt` | Logs screen view and action events with contextual fields per journey step |
| `CaptureOkHttpEventListenerFactory` | `OkHttpNetworkClient.kt` | Auto span logging for OkHttp — replaces manual `HttpRequestInfo`/`HttpResponseInfo` calls |
| `CaptureOkHttpTracingInterceptor` | `OkHttpNetworkClient.kt` | Auto traceparent injection for OkHttp — replaces manual `isTracingActive` check and header generation |
| `Logger.logAppLaunchTTI(...)` | `MainActivity.kt` | TTI instrumentation |
| `Logger.createTemporaryDeviceCode` | `Screens.kt` | Generates a short code for live log streaming in the bitdrift dashboard |
| `Logger.startNewSession()` | `NetworkViewModel.kt` | Starts a new session at the beginning of each journey run |

### Non-bitdrift

| API / Class | Where | Purpose |
|---|---|---|
| `HttpURLConnection` | `ManualHttpClient.kt` | Raw HTTP client — used to demonstrate manual instrumentation without an SDK-aware library |
| `OkHttpClient` | `OkHttpNetworkClient.kt` | HTTP client — receives the Capture SDK components via builder hooks |
| `SecureRandom` | `ManualHttpClient.kt` | Generates cryptographically-random OTel-compatible trace ID and span ID bytes |

---

## Test endpoints

Both loops cycle through these endpoints on `jsonplaceholder.typicode.com`:

- `GET /posts/1`
- `GET /users/1`
- `GET /todos/1`
- `GET /comments/1`
- `GET /posts/2`
- `GET /albums/1`
- `GET /photos/1`
