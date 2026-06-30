# OTel Demo Shopping App (Android — SDK)

A demo Android app simulating an e-commerce shopping experience, instrumented with the **bitdrift Capture SDK** and backed by the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) Telescope Store.

## What This Is

- **bitdrift Capture SDK** — logging, screen views, network capture, feature flag exposure, ANR simulation.
- **OpenTelemetry Demo backend** — the open-source OTel Demo microservices stack (Telescope Store). The app talks to its frontend proxy on port 8080 instead of the original FastAPI backend.

The OTel Demo backend generates rich distributed traces across its microservices as the app drives cart and checkout flows. The bitdrift SDK captures the mobile-side story: screen views, structured logs, network timing, and session context.

## Local Config

`local.properties` is committed as a blank template. Add real values to `.local.properties` (gitignored):

```properties
BITDRIFT_SDK_KEY=your_key_here
BITDRIFT_API_HOST=api.bitdrift.io
```

To override the backend address (defaults to Android emulator → host):

```properties
OTEL_DEMO_HOST=10.0.2.2
OTEL_DEMO_PORT=8080
```

## Tracing (bitdrift)

`ApiClient.kt` uses bitdrift's manual OkHttp tracing integration:

- `CaptureOkHttpTracingInterceptor()` — injects trace context headers
- `CaptureOkHttpEventListenerFactory()` — records network spans

Gradle auto OkHttp instrumentation is disabled (`automaticOkHttpInstrumentation=false`) to avoid duplicate paths. Trace propagation format and sampling are controlled remotely via the bitdrift dashboard.

Reference: [Tracing: Network integration](https://docs.bitdrift.io/sdk/features/tracing.html#network-integration)

## Quick Start

### 1. Set up the OTel Demo backend for B3

Copy the B3 override file from this repo to your `opentelemetry-demo` clone root:

```bash
cp /path/to/shoppingdemo-oteldemo/docker-compose.b3-propagation.yaml /path/to/opentelemetry-demo/
```

Add the Zipkin exporter to `src/otel-collector/otelcol-config-extras.yml` in your `opentelemetry-demo` clone (create the file if it doesn't exist):

```yaml
exporters:
  zipkin:
    endpoint: http://zipkin:9411/api/v2/spans

service:
  pipelines:
    traces:
      exporters: [debug, span_metrics, zipkin]
    metrics:
      receivers: [docker_stats, http_check/frontend-proxy, host_metrics, nginx, otlp, redis, span_metrics]
      exporters: [debug]
    logs:
      exporters: [debug]
```

### 2. Start the backend

From the `opentelemetry-demo` repo root:

```bash
docker compose \
  -f compose.yaml \
  -f docker-compose.b3-propagation.yaml \
  up \
  --scale load-generator=0 \
  --force-recreate \
  --remove-orphans \
  --detach
```

Frontend proxy starts on `http://localhost:8080`. Zipkin starts on `http://localhost:9411`.

> **Note:** Always use `--force-recreate` when switching between compose configurations. Without it, containers may keep stale environment variables from a previous run (e.g. a `recommendation` container that still has old propagator settings), which can block `frontend-proxy` from starting.

### 3. Run the Android app

Open in Android Studio and run on an emulator. The app connects via `http://10.0.2.2:8080`.

**Emulator requirements:**

| Setting | Value |
|---------|-------|
| API level | API 36 (Android 16) |
| Screen resolution | 1080×2400 (FHD+) |
| Device profile | Medium Phone / Pixel 7 / 6a |
| RAM | 2 GB+ |

## Screens

| Screen | Description |
|--------|-------------|
| `Welcome` | Entry point, simulation controls |
| `Browse` | Full product listing |
| `Search` | Keyword search |
| `Featured` | Curated featured products |
| `Categories` | Category listing |
| `CategoryBrowse` | Products within a category |
| `ProductDetail` | Full product info with images |
| `Reviews` | Customer reviews + ratings |
| `Cart` | Shopping cart |
| `Wishlist` | Saved items |
| `CheckoutGuest` | Guest checkout |
| `CheckoutSignIn` | Member checkout with loyalty points |
| `PaymentCard` | Credit card payment |
| `PaymentApplePay` | Apple Pay |
| `PaymentPayPal` | PayPal |
| `PaymentAndroidPay` | Android Pay |
| `Confirmation` | Order confirmation |

## Simulation

The Welcome screen has simulation buttons (**Sim 10**, **∞ Sim**, **Sim A/B**) that run automated journeys through the app using a probabilistic state machine. Three variant presets bias the simulator toward different user personas:

- **Control** — fully random baseline
- **Variant A (Guest)** — non-member, high cart-abandon rate, digital wallet payments
- **Variant B (Member)** — signed-in loyalty member, low abandon rate, card payments

**Sim A/B** cycles through variants across 15 journeys (5 per variant), guaranteeing flag transitions for bitdrift workflow matching.

## Requirements

- Android API 36 (targetSdk / compileSdk), API 26+ minimum
- Emulator: 1080×2400 resolution (Medium Phone / Pixel 7)
- [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) running on port 8080

## Project Structure

```
app/src/main/java/com/example/shoppingdemo/
├── ShoppingDemoApp.kt         # Application class, SDK init
├── MainActivity.kt            # Main activity with NavHost
├── Screen.kt                  # Navigation routes (sealed class)
├── Screens.kt                 # All screen composables
├── Components.kt              # Reusable UI components
├── ApiClient.kt               # OTel Demo compatibility adapter (OkHttp)
├── SimulationManager.kt       # Probabilistic state machine simulator
├── RecommendationEngine.kt    # Product recommendation scoring engine
├── ScreenLogger.kt            # Centralized logging wrapper
├── AppLifecycleCallbacks.kt   # App lifecycle event logging
└── ui/theme/
    └── Theme.kt               # Material 3 theme
```

## Architecture

```
┌─────────────────────┐        HTTP (OkHttp)        ┌──────────────────────────────────────┐
│   Android Emulator   │ ◄─────────────────────────► │  OTel Demo Frontend Proxy (Envoy)    │
│   (10.0.2.2:8080)    │    JSON request/response    │  (localhost:8080)                    │
└─────────────────────┘                              │                                      │
                                                     │  /api/products  → product-catalog    │
                                                     │  /api/cart      → cart service       │
                                                     │  /api/checkout  → checkout service   │
                                                     │  /images/       → image-provider     │
                                                     └──────────────────────────────────────┘
```

## B3 Propagation + Zipkin

The bitdrift SDK is configured remotely to emit **B3 multi-header** trace context (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`). The compose override makes every backend service propagate those headers, and Zipkin provides a visual trace viewer.

### How it works

**`docker-compose.b3-propagation.yaml`** (in this repo, copy to `opentelemetry-demo` root):
- Adds a Zipkin container on port 9411, joined to the `opentelemetry-demo` network
- Sets `OTEL_PROPAGATORS=b3multi,baggage` on all backend services that support it

**`src/otel-collector/otelcol-config-extras.yml`** — wires the OTel Collector's traces pipeline to export to Zipkin.

> **Note on `recommendation`:** The Python-based `recommendation` service requires the `opentelemetry-propagator-b3` package which is not installed in the OTel Demo image. It is intentionally excluded from the B3 override and continues to use W3C propagation. This does not affect the core shopping flow or Zipkin traces.

### View traces in Zipkin

1. Open **http://localhost:9411**
2. In the app, tap **Sim 10** to generate traffic
3. In Zipkin, click **Run Query** — traces appear within a few seconds
4. Click any trace to see the full waterfall across OTel Demo microservices, with B3 trace/span IDs matching what bitdrift recorded on the mobile side

### bitdrift backend config

```yaml
frontend_features:
  tracing_features:
    trace_id_deep_link_url_template: http://localhost:9411/zipkin/traces/{traceId}
  views_ui_enabled: true
runtime_set:
  runtimes:
  - matcher:
      always: true
    runtime:
      values:
        client_config.trace.propagation_mode:
          string_value: b3-multi
```
