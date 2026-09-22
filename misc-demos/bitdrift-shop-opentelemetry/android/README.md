# Bitdrift Shop - OpenTelemetry (Android — SDK)

A demo Android app simulating an e-commerce shopping experience, instrumented with the **bitdrift Capture SDK** and backed by the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) Telescope Store.

## What This Is

- **bitdrift Capture SDK** — logging, screen views, network capture, feature flag exposure, ANR simulation.
- **OpenTelemetry Demo backend** — the open-source OTel Demo microservices stack (Telescope Store), not the original FastAPI backend. The app talks to its frontend proxy on port 8081 (moved off the default 8080 to leave that port free for ClickStack).

The OTel Demo backend generates rich distributed traces across its microservices as the app drives cart and checkout flows. The bitdrift SDK captures the mobile-side story: screen views, structured logs, network timing, and session context.

## Local Config

`local.properties` is committed as a blank template. Add real values to `.local.properties` (gitignored):

```properties
BITDRIFT_SDK_KEY=your_key_here
BITDRIFT_API_HOST=api.bitdrift.io
```

The OTel Demo backend in this setup runs on **8081**, not the default 8080 (8080 is left free for ClickStack — set up in step 1 below). Add these to the same `.local.properties` file so the app points at it (defaults to Android emulator → host):

```properties
OTEL_DEMO_HOST=10.0.2.2
OTEL_DEMO_PORT=8081
```

## Tracing (bitdrift)

`ApiClient.kt` uses bitdrift's manual OkHttp tracing integration:

- `CaptureOkHttpTracingInterceptor()` — injects trace context headers
- `CaptureOkHttpEventListenerFactory()` — records network spans

Gradle auto OkHttp instrumentation is disabled (`automaticOkHttpInstrumentation=false`) to avoid duplicate paths. Trace propagation format and sampling are controlled remotely via the bitdrift dashboard.

Reference: [Tracing: Network integration](https://docs.bitdrift.io/sdk/features/tracing.html#network-integration)

## Prerequisites (macOS)

The OTel Demo backend is a `docker compose` stack, so it needs a Docker daemon — but
**not Docker Desktop**. Like the rest of `bitdrift-shop` in this repo (see
[bitdrift-shop/backend/README.md#prerequisites-macos](../../../bitdrift-shop/backend/README.md#prerequisites-macos)),
the recommended backend here is [Colima](https://github.com/abiosoft/colima), a
lightweight Docker daemon that runs in a small Linux VM without Docker Desktop's
licensing or resource overhead:

```bash
brew install colima docker docker-compose
colima start
docker ps          # should print an empty table, not a connection error
```

`colima start` provisions the VM and points the `docker` CLI at it — no `DOCKER_HOST`
needed. If a command below reports `Cannot connect to the Docker daemon`, Colima isn't
running; `colima status` shows the current state. The ClickStack container in step 1
needs more RAM than Colima's default VM — see the memory note there.

You also need a local clone of the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) itself — this repo only ships overrides (`docker-compose.b3-propagation.yaml`, `otelcol-config-extras.yml`) that layer on top of it, not the backend stack:

```bash
git clone https://github.com/open-telemetry/opentelemetry-demo.git
cd opentelemetry-demo
```

Every `docker compose` command below (and the `cp .../docker-compose.b3-propagation.yaml ...` step) is meant to be run from that `opentelemetry-demo` clone's root.

## Quick Start

### 1. Set up ClickStack

Set this up **before** starting the OTel Demo backend, so the backend's collector is already
wired to export to ClickStack the first time it boots — no need to restart it afterward. (If you'd
rather skip ClickStack entirely and use plain W3C or Zipkin instead, skip to
[step 2](#2-start-the-otel-demo-backend-configured-for-clickstack) and see
[Switch to B3 Propagation and Zipkin (Optional)](#switch-to-b3-propagation-and-zipkin-optional).)

[ClickStack](https://github.com/ClickHouse/ClickStack) is ClickHouse's open-source observability stack for OpenTelemetry — logs, traces, metrics, and session replay in one UI. (Formerly branded standalone as "HyperDX" — same image, ports, and API, just repackaged/renamed under ClickHouse.) It's an export target for the OTel Collector — no B3 override or propagation change required, it works with the stock W3C setup from step 2.

> **Memory requirement:** the ClickStack all-in-one container bundles ClickHouse + Mongo + the ClickStack app, and needs **at least 4GB RAM** on its own (ClickStack's own recommendation). Combined with the ~20 containers in the OTel Demo stack (started in step 2), give your Docker VM **8GB+** total or ClickHouse will get silently OOM-killed after a few minutes (check `docker inspect <container> --format '{{.State.OOMKilled}}'` if traces stop landing).
>
> - **Colima** (see [Prerequisites](#prerequisites-macos) above): `colima stop && colima start --memory 8 --cpu 4` (this restarts the whole VM — every running container goes down; the OTel Demo stack's containers have `restart: unless-stopped` so they come back on their own, but the ClickStack container below does not and must be relaunched manually)
> - **Docker Desktop:** Settings → Resources → bump Memory to 8GB → Apply & Restart

Run the ClickStack all-in-one container standalone (it does **not** join the `opentelemetry-demo` docker network — it's just a container on your host). Name it so it's easy to manage/restart later:

Make sure Colima is running first — with the memory bump above if you haven't already applied it:

```bash
colima start
docker run -d --name clickstack -p 8080:8080 -p 4317:4317 -p 4318:4318 docker.hyperdx.io/hyperdx/hyperdx-all-in-one
```

> The image itself is still published under the `hyperdx` Docker namespace (`docker.hyperdx.io/hyperdx/hyperdx-all-in-one`) — that's just the registry path and is current/correct. Everywhere else in this doc refers to it as ClickStack.

> **Port note:** ClickStack's UI defaults to host port 8080 — the same port the OTel Demo `frontend-proxy` normally wants. Step 2 moves the frontend proxy to `8081` via `ENVOY_PORT` so both can run at once.

Open **http://localhost:8080** and sign up (any email/password works locally) — this auto-creates a team and an ingestion API key. Grab the key from **Team Settings → API Keys** in the UI.

> **Grab the key now and hold onto it** — the next step (starting the OTel Demo backend) uses it to configure the collector's ClickStack exporter before the backend's first boot.

> **No persistence:** this container has no volume mounts, so a restart (crash, `docker stop`, Colima/Docker VM restart) wipes all data and creates a **new** team + API key on next signup. If traces stop showing up after a restart, re-check the key.

### 2. Start the OTel Demo backend (configured for ClickStack)

Stock setup, no propagation overrides — services use the OTel Demo's default W3C trace context propagation; only the collector's export target changes. `ENVOY_PORT=8081` moves the frontend proxy off the default 8080, leaving it free for ClickStack. From the `opentelemetry-demo` repo root:

Make sure Colima is running first (see [Prerequisites](#prerequisites-macos) — `colima start` is a no-op if it's already up):

```bash
colima start
```

Point `src/otel-collector/otelcol-config-extras.yml` at ClickStack via OTLP/HTTP, with the API key from step 1 as an `authorization` header (create the file if it doesn't exist) — do this **before** bringing the backend up, so the collector exports to ClickStack from its first boot:

```yaml
exporters:
  otlphttp/clickstack:
    endpoint: http://host.docker.internal:4318
    headers:
      authorization: <your ClickStack API key>
    tls:
      insecure: true

service:
  pipelines:
    traces:
      exporters: [debug, span_metrics, otlphttp/clickstack]
    metrics:
      receivers: [docker_stats, http_check/frontend-proxy, host_metrics, nginx, otlp, redis, span_metrics]
      exporters: [debug, otlphttp/clickstack]
    logs:
      exporters: [debug, otlphttp/clickstack]
```

> `host.docker.internal` resolves to the host machine from inside a container on Docker Desktop (macOS/Windows) and Colima automatically. On plain Linux Docker, add `--add-host=host.docker.internal:host-gateway` to the `docker run` command in step 1.
>
> Without the `authorization` header, the collector logs `401 Unauthorized` / `missing or empty authorization header` and silently drops everything — check `docker logs otel-collector | grep clickstack` if data isn't showing up.

Now bring up the backend:

```bash
ENVOY_PORT=8081 docker compose \
  -f compose.yaml \
  up \
  --scale load-generator=0 \
  --force-recreate \
  --remove-orphans \
  --detach
```

Frontend proxy starts on `http://localhost:8081`.

> **Troubleshooting — `frontend-proxy` restart-looping:** if `docker ps` shows `frontend-proxy` stuck in a restart loop, check `docker logs frontend-proxy` for an Envoy `Proto constraint validation failed` error on a socket address. This means the image you pulled (`ghcr.io/open-telemetry/demo:latest-frontend-proxy`) is newer than your local `opentelemetry-demo` checkout — its baked-in `envoy.tmpl.yaml` references env vars (e.g. `OPAMP_HOST`/`OPAMP_PORT`) that your local `compose.yaml`/`.env` don't set, so they render empty and Envoy rejects the config. Fix by building the image from your local source instead of the stale pulled one:
>
> ```bash
> ENVOY_PORT=8081 docker compose -f compose.yaml build frontend-proxy
> ```
>
> then re-run the `up` command above.

To view traces once the app (next step) is running and you've generated some traffic: open **http://localhost:8080**, tap **Sim 10** in the app, then search or browse traces/logs/metrics in the ClickStack UI — data lands within a few seconds. To sanity-check ingestion directly in ClickHouse: `docker exec clickstack sh -c "curl -s 'http://localhost:8123/?query=SELECT+count()+FROM+otel_traces'"`.

> **Zipkin ↔ ClickStack are mutually exclusive** in `otelcol-config-extras.yml` — it only holds one exporter config at a time. To switch to Zipkin, see [Switch to B3 Propagation and Zipkin (Optional)](#switch-to-b3-propagation-and-zipkin-optional) below instead.

### 3. Run the Android app

Set `OTEL_DEMO_PORT=8081` in `.local.properties` (see [Local Config](#local-config)), then open the project in Android Studio and run on an emulator. The app connects via `http://10.0.2.2:8081`.

**Emulator requirements:**

| Setting | Value |
|---------|-------|
| API level | API 36 (Android 16) |
| Screen resolution | 1080×2400 (FHD+) |
| Device profile | Medium Phone / Pixel 7 / 6a |
| RAM | 2 GB+ |

**(Optional) No Android Studio?** `scripts/android-{1..5}-*.sh` set up the SDK/AVD, boot the emulator, and build+install+launch from the command line instead — modeled on [bitdrift-shop/android's own no-Studio scripts](../../../bitdrift-shop/android/scripts/):

```bash
cd android
./scripts/android-1-setup.sh          # one-time: cmdline-tools, SDK packages, AVD
./scripts/android-2-start-emulator.sh # boot and wait for it to come up
./scripts/android-3-start-app.sh      # gradlew install<Variant> + launch
./scripts/android-4-stop-app.sh       # force-stop, leaves the emulator running
./scripts/android-5-stop-emulator.sh  # kill the emulator
```

### 4. Deploy the session-capture workflow

Before running the live demo, publish the workflow that guarantees every session gets fully
captured — a capture workflow only sees sessions that start *after* it deploys, so this needs to
happen before you start driving traffic through the app, not mid-demo.

This step needs the `bd` CLI, authenticated:

```bash
# Install (see https://github.com/bitdriftlabs/bd-cli-releases for other platforms)
brew tap bitdriftlabs/bd && brew install bd

# Authenticate — opens a browser; safe to re-run, it skips login if already authenticated
bd auth

# Confirm
bd auth --status
```

Then deploy the workflow:

```bash
./scripts/deploy-capture-workflow.sh
```

Idempotent — safe to re-run; it reuses the existing workflow instead of creating a duplicate. See
[workflows/README.md](workflows/README.md) for what it deploys and how to do it by hand with `bd`.

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
- [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) running on port 8081 (see [Local Config](#local-config))

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
│   (10.0.2.2:8081)    │    JSON request/response    │  (localhost:8081)                    │
└─────────────────────┘                              │                                      │
                                                     │  /api/products  → product-catalog    │
                                                     │  /api/cart      → cart service       │
                                                     │  /api/checkout  → checkout service   │
                                                     │  /images/       → image-provider     │
                                                     └──────────────────────────────────────┘
```

## Switch to B3 Propagation and Zipkin (Optional)

The bitdrift SDK is configured remotely to emit **B3 multi-header** trace context (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`). The compose override makes every backend service propagate those headers, and Zipkin provides a visual trace viewer.

Copy the B3 override file from this repo to your `opentelemetry-demo` clone root:

```bash
cp /path/to/bitdrift-shop-opentelemetry/docker-compose.b3-propagation.yaml /path/to/opentelemetry-demo/
```

This adds a Zipkin container on port 9411, joined to the `opentelemetry-demo` network, and sets `OTEL_PROPAGATORS=b3multi,baggage` on all backend services that support it.

> **Note on `recommendation`:** The Python-based `recommendation` service requires the `opentelemetry-propagator-b3` package which is not installed in the OTel Demo image. It is intentionally excluded from the B3 override and continues to use W3C propagation. This does not affect the core shopping flow or Zipkin traces.

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

Restart the backend with the B3 override layered on top:

Make sure Colima is running first (see [Prerequisites](#prerequisites-macos) — `colima start` is a no-op if it's already up):

```bash
colima start
ENVOY_PORT=8081 docker compose \
  -f compose.yaml \
  -f docker-compose.b3-propagation.yaml \
  up \
  --scale load-generator=0 \
  --force-recreate \
  --remove-orphans \
  --detach
```

Zipkin starts on `http://localhost:9411`.

> **Note:** Always use `--force-recreate` when switching between compose configurations (stock ↔ B3). Without it, containers may keep stale environment variables from a previous run (e.g. a `recommendation` container that still has old propagator settings), which can block `frontend-proxy` from starting.

To view traces: open **http://localhost:9411**, tap **Sim 10** in the app, then click **Run Query** in Zipkin — traces appear within a few seconds. Click any trace to see the full waterfall across OTel Demo microservices, with B3 trace/span IDs matching what bitdrift recorded on the mobile side.

**bitdrift backend config** (to deep-link trace IDs from bitdrift into Zipkin):

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
