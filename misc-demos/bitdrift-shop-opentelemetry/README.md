# Bitdrift Shop - OpenTelemetry

Demo e-commerce shopping apps instrumented with the **bitdrift Capture SDK** and backed by the
[OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) Telescope Store.

> **Read first:** [Quick Reference](#quick-reference-humans-and-agents) has the commands, config and
> gotchas; [Telemetry Reference](#telemetry-reference) lists the screens, events and fields the app emits.
> Platform details: [android/README.md](android/README.md), [ios/README.md](ios/README.md).

Two client apps live in this repo, both driving the same backend and simulation logic:

| App | Stack | Docs |
|---|---|---|
| `android/` | Kotlin, Jetpack Compose | [android/README.md](android/README.md) |
| `ios/` | Swift, SwiftUI | [ios/README.md](ios/README.md) |

This README covers the shared backend (OTel Demo + ClickStack), Docker/Colima prerequisites and the
Quick Start; then follow the platform README for SDK config and running the app.

## Quick Links

Local URLs once the stack is running ([Quick Start](#quick-start)):

| Service | URL | What it's for |
|---|---|---|
| **HyperDX / ClickStack** | [http://localhost:8080](http://localhost:8080) | Logs, traces, metrics, session replay |
| **OTel Demo (app backend)** | [http://localhost:8081](http://localhost:8081) | The frontend proxy both apps talk to |
| **Portainer** (optional) | [http://localhost:9000](http://localhost:9000) | Container manager/dashboard — see [Container Monitoring](#container-monitoring-optional-portainer) |
| **Zipkin** (if using B3 instead of ClickStack) | [http://localhost:9411](http://localhost:9411) | See [B3_ZIPKIN.md](B3_ZIPKIN.md) |

## Quick Reference (humans and agents)

**Layout**

| Path | Contents |
|---|---|
| `android/` | Kotlin/Compose app (`ai.bitdrift.oteldemo`, Capture SDK 0.26.0), emulator + deploy scripts in `android/scripts/` |
| `ios/` | SwiftUI app and scripts |
| `workflows/` | Android bitdrift workflows (capture + tracing, journey sankey, metric workflows) and `chart-metadata/` |
| `dashboards/` | Dashboard JSON with workflow-ID placeholders (filled in by the deploy script) |
| `docker-compose.b3-propagation.yaml`, `B3_ZIPKIN.md`, `APPENDIX.md` | Optional B3/Zipkin override and troubleshooting |

**Common tasks** (run from the project root unless noted)

| Task | Command | Notes |
|---|---|---|
| Build, install, launch Android app | `cd android && ./scripts/android-3-start-app.sh` | Needs a running emulator (`android-2-start-emulator.sh`); reads `android/.local.properties` |
| Boot the emulator | `cd android && ./scripts/android-2-start-emulator.sh` | AVD `medium_phone`; `EMULATOR_WINDOW=0` for headless |
| Deploy capture + tracing workflow | `cd android && ./scripts/deploy-capture-workflow.sh` | Idempotent; do this *before* driving traffic |
| Deploy journey sankey | `cd android && ./scripts/deploy-sankey-workflow.sh` | Idempotent |
| Deploy metric workflows + dashboard | `cd android && ./scripts/deploy-metric-workflows.sh` | Idempotent; the dashboard is replaced |
| Generate traffic | Tap **Sim 5 / Sim 10 / Sim ∞** on the Welcome screen | Stop Sim ∞ with the ✕ (Cancel) button in the simulation banner |
| Stop everything | `./stop-backend.sh` | Removes the OTel Demo stack, ClickStack and Portainer containers |

**Config** (`android/.local.properties`, gitignored; env vars also work): `BITDRIFT_SDK_KEY`,
`BITDRIFT_API_HOST` (default `api.bitdrift.io`; use `api.bitdrift.dev` to report to `.dev`),
`OTEL_DEMO_HOST` (default `10.0.2.2`), `OTEL_DEMO_PORT` (default `8081`). Local ports: ClickStack UI `8080`,
OTLP `4317`/`4318`, OTel Demo frontend proxy `8081`.

**bitdrift environment.** `bd` targets production (`.io`) by default. `bd install-profile staging`
switches the CLI to `.dev` (then `bd auth`); `bd install-profile default` switches back. Confirm
with `bd connectivity check -ojson --jq '.endpoints[0].address'`. Docs and scripts here assume
`.io`.

**Things that bite**
- A workflow only sees sessions that start *after* it deploys.
- Tracing uses the manual OkHttp interceptor; keep `automaticOkHttpInstrumentation=false` or every
  request is double-instrumented.
- `NavHost` transitions are disabled on purpose — the default crossfade stacks screens during fast
  simulation and bloats session-replay wireframes.
- OTel *span* export from the app needs a local capture AAR (`BITDRIFT_USE_LOCAL_AAR`); the default
  build uses the published SDK and leaves it off.

**Verify it works**

| Check | Command | Expect |
|---|---|---|
| Backend up | `curl -s "http://localhost:8081/api/products?currencyCode=USD" \| head -c 200` | JSON product list |
| ClickStack up | `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/` | `200` |
| App running | `adb shell pidof ai.bitdrift.oteldemo` | a PID |
| bitdrift tenant | `bd connectivity check -ojson --jq '.endpoints[0].address'` | `https://api.bitdrift.io` (`.io`) or `https://api.bitdrift.dev` (`.dev`) |
| Workflows deployed | `bd workflow list --workflow-name "bitdrift-shop-opentelemetry" -ojson --jq '[.items[]\|{id:.workflow.id,name:.workflow.name,state:.workflow.state}]'` | the four workflows below, `LIVE` |

**Workflow and dashboard inventory** (names are the lookup keys the deploy scripts use)

| Name | File | Purpose |
|---|---|---|
| `bitdrift-shop-opentelemetry — Capture All Sessions (Demo)` | `workflows/capture-all-sessions.json` | On the `Welcome` screen view: flush the session and start backend tracing |
| `bitdrift-shop-opentelemetry — User Journey Paths (Welcome → Confirmation)` | `workflows/user-journey-sankey.json` | Sankey of screen paths from `Welcome` to `Confirmation` |
| `bitdrift-shop-opentelemetry — Backend API Metrics` | `workflows/otel-api-metrics.json` | `/api/*` request count, latency histogram, errors, error rate |
| `bitdrift-shop-opentelemetry — Journey Health` | `workflows/otel-journey-health.json` | Journeys started/completed, completion rate, failures, screen views |
| `bitdrift-shop-opentelemetry — Telescope Store` (dashboard) | `dashboards/otel-telescope-store.dashboard.json` | Journey and Backend API tabs over the two metric workflows |

## Telemetry Reference

What the Android app emits (useful when writing workflows or investigating sessions).

- **Screens** (`SCREEN_VIEW`, field `_screen_name`): `Welcome`, `Browse`, `Search`, `Featured`, `Categories`, `CategoryBrowse`, `ProductDetail`, `Reviews`, `Cart`, `Wishlist`, `CheckoutGuest`, `CheckoutSignIn`, `PaymentCard`, `PaymentApplePay`, `PaymentPayPal`, `PaymentAndroidPay`, `PaymentFailed`, `Confirmation`.
- **Log events** (match on log body): `app_launched`, `app_open`, `app_close`, `feature_flag_exposure_set`, `simulation_start`/`simulation_end` (field `total_runs`), `add_to_cart` and `add_to_wishlist` (fields `product_id`, `source_screen`), `cart_item_removed` (`product_id`), `cart_failed` (`product_id`), `checkout_failed` (`checkout_type`), `payment_failed` (`payment_method`), `payment_retry` (`original_method`, `retry_method`), `confirmation_reached`.
- **Network** (span end log, message `HTTPResponse`): `_span_name=_http`, `_span_type=end`, `_host`, `_path`, `_path_template`, `_method`, `_status_code`, `_duration_ms`, `_result` (`success` or not), `_trace_id`. Backend calls are `/api/*` on `10.0.2.2:8081`.
- **Global fields** (on every log/span): `app_variant=otel-demo`, `platform=android`, plus feature-flag fields `ff_variant`, `ff_checkout_flow`, `ff_payment_ui`, `ff_cart_abandon_rate`, `ff_payment_android_pay`, `ff_anr_a`.
- **Feature-flag exposures:** `checkout_flow` and `payment_ui`, set per session by the simulation presets.
- **Sessions:** the simulation calls `Logger.startNewSession()` once per journey, so one journey is one session.

## What This Is

- **bitdrift Capture SDK** — logging, screen views, network capture, feature flag exposure. Android also has ANR simulation ([android/README.md](android/README.md)); iOS has no equivalent.
- **OpenTelemetry Demo backend** — the OTel Demo microservices (Telescope Store), not the original FastAPI backend. Apps talk to its frontend proxy on port 8081 (moved off 8080, which ClickStack uses).

The backend produces distributed traces as the app drives cart and checkout; the SDK captures the mobile side: screen views, logs, network timing and session context.

## Prerequisites (macOS)

The backend is a `docker compose` stack. Use [Colima](https://github.com/abiosoft/colima) (a lightweight
Docker daemon in a small Linux VM), **not Docker Desktop** — same as the rest of `bitdrift-shop`
(see [bitdrift-shop/backend/README.md#prerequisites-macos](../../bitdrift-shop/backend/README.md#prerequisites-macos)):

```bash
brew install colima docker docker-compose
colima start
docker ps          # should print an empty table, not a connection error
```

`colima start` points the `docker` CLI at the VM (no `DOCKER_HOST` needed). `Cannot connect to the
Docker daemon` means Colima isn't running (`colima status`). ClickStack needs more RAM than
Colima's default — see [Memory Requirements](APPENDIX.md#memory-requirements).

Also clone the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo); this repo only ships overrides (`docker-compose.b3-propagation.yaml`, `otelcol-config-extras.yml`) on top of it:

```bash
git clone https://github.com/open-telemetry/opentelemetry-demo.git
cd opentelemetry-demo
```

Run every `docker compose` command below (and the `cp .../docker-compose.b3-propagation.yaml ...` step) from that clone's root.

## Quick Start

### 1. Set up ClickStack

Do this **before** starting the backend, so its collector exports to ClickStack from first boot. (To
skip ClickStack and use Zipkin instead, see
[Switch to B3 Propagation and Zipkin](APPENDIX.md#switch-to-b3-propagation-and-zipkin-optional).)

[ClickStack](https://github.com/ClickHouse/ClickStack) is ClickHouse's open-source observability stack for OpenTelemetry — logs, traces, metrics, and session replay in one UI. (Formerly branded standalone as "HyperDX" — same image, ports, and API, just repackaged/renamed under ClickHouse.) It's an export target for the OTel Collector — no B3 override or propagation change required, it works with the stock W3C setup from step 2.

> **Memory:** ClickStack needs far more RAM than the default Colima/Docker VM — apply [Memory Requirements](APPENDIX.md#memory-requirements) first.

Run the all-in-one container standalone (it does **not** join the `opentelemetry-demo` network) and name it for easy restarts:

```bash
colima start
docker run -d --name clickstack -p 8080:8080 -p 4317:4317 -p 4318:4318 docker.hyperdx.io/hyperdx/hyperdx-all-in-one
```

> The image is still published under the `hyperdx` Docker namespace; that's just the registry path. Elsewhere this doc calls it ClickStack.

> **Port:** ClickStack's UI uses host port 8080, which the OTel Demo `frontend-proxy` also wants. Step 2 moves the proxy to `8081` via `ENVOY_PORT`.

Open **http://localhost:8080** and sign up (any email/password works locally); this creates a team and an ingestion API key. **Copy the key from Team Settings → API Keys now** — step 2 configures the collector's exporter with it before first boot.

> **Persistence:** there is no `-v` flag, but the image declares an internal `VOLUME` for `/var/lib/clickhouse`, so Docker creates an anonymous volume: data survives `docker stop`/`start` and VM restarts, and is lost only if the container is removed (`docker rm`). For a true reset see [Fully purging ClickStack / HyperDX](APPENDIX.md#fully-purging-clickstack--hyperdx); that also creates a **new** team and API key on next signup.

#### Link bitdrift traces to ClickStack (shard config)

To make **View Trace** in bitdrift open the trace in your local ClickStack, set the shard's trace deep-link template (bitdrift-side config, not set by this repo):

```yaml
trace_id_deep_link_url_template: http://localhost:8080/search?traceId={traceId}
```

`localhost` only resolves on the machine running ClickStack, so the link works from your own browser only.

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

**Restarting the backend:**

- **Full recreate** (picks up changes to `compose.yaml`, `.env`, or `otelcol-config-extras.yml`) — safe to run again on top of an already-running stack:

```bash
ENVOY_PORT=8081 docker compose \
  -f compose.yaml \
  up \
  --scale load-generator=0 \
  --force-recreate \
  --remove-orphans \
  --detach
```

- **Quick restart** (containers stay, no config changes to pick up):

```bash
ENVOY_PORT=8081 docker compose -f compose.yaml restart
```

- **Stop everything** (just the OTel Demo stack, run from the `opentelemetry-demo` clone):

```bash
docker compose -f compose.yaml down
```

- **Stop and remove the whole demo** (OTel Demo stack + ClickStack + Portainer) — use this before a Colima/Docker restart if you don't want everything auto-relaunching:

```bash
./stop-backend.sh
```

The OTel Demo stack's services all use `restart: unless-stopped`, so a plain `colima stop && colima start` brings them back on its own — Docker only respects that policy once a container has been explicitly stopped first. This script stops and removes every container so a subsequent Colima restart leaves them down until you deliberately bring them back up. `astronomy-db`'s named volume survives and gets reattached correctly; **ClickStack's does not** — its volume is anonymous (no `-v` in the Quick Start's `docker run`), so removing that container orphans it for good, and the next ClickStack container starts with an empty database (new signup, new ingestion API key). See the comment at the top of `stop-backend.sh` for how to avoid that.

> Colima itself only needs restarting if you changed its VM resources (see [Memory Requirements](APPENDIX.md#memory-requirements)) or it's not running (`colima status`) — the backend restart commands above don't touch the VM.

> **Troubleshooting — `frontend-proxy` restart-looping:** if `docker ps` shows `frontend-proxy` stuck in a restart loop, check `docker logs frontend-proxy` for an Envoy `Proto constraint validation failed` error on a socket address. This means the image you pulled (`ghcr.io/open-telemetry/demo:latest-frontend-proxy`) is newer than your local `opentelemetry-demo` checkout — its baked-in `envoy.tmpl.yaml` references env vars (e.g. `OPAMP_HOST`/`OPAMP_PORT`) that your local `compose.yaml`/`.env` don't set, so they render empty and Envoy rejects the config. Fix by building the image from your local source instead of the stale pulled one:
>
> ```bash
> ENVOY_PORT=8081 docker compose -f compose.yaml build frontend-proxy
> ```
>
> then re-run the `up` command above.

To view traces once an app (next step) is running and you've generated some traffic:

- Open **http://localhost:8080**
- Tap **Sim 10** in the app (or **Sim ∞** to run journeys back to back until you tap the ✕ (Cancel) button in the simulation banner)
- Search or browse traces/logs/metrics in the ClickStack UI — data lands within a few seconds
- To sanity-check ingestion directly in ClickHouse: `docker exec clickstack sh -c "curl -s 'http://localhost:8123/?query=SELECT+count()+FROM+otel_traces'"`

### 3. Run an app

The backend is platform-agnostic — both apps point at the same `http://localhost:8081`. From here,
follow the app-specific README for SDK configuration, the (experimental) OTel span export wiring,
and how to build/run:

- [android/README.md](android/README.md) — Kotlin/Jetpack Compose, run via Android Studio or the no-Studio scripts
- [ios/README.md](ios/README.md) — Swift/SwiftUI, run via Xcode

### 4. Appendix

See [APPENDIX.md](APPENDIX.md) for troubleshooting notes and reference material that don't fit the quick-start flow above (most of it backend/infra-focused and shared across both apps; a few sections are Android-specific, called out there):

- Colima not mounting an external-drive checkout, causing `otel-collector` to crash-loop (and how to make the mount permanent)
- `astronomy-db` missing its `astronomy_user` role after a broken first boot, causing `product-catalog` to crash-loop and product images to go missing
- A full audit runbook for checking the rest of the stack after a Colima mount fix, so no other services are silently running on bad first-boot state
- Fully purging ClickStack/HyperDX's hidden anonymous data volume when the UI errors out or shows stale data
- Memory requirements, plus Android-specific reference material (Screens list, Project Structure, Architecture diagram, Emulator requirements) and the B3/Zipkin switch

## Container Monitoring (Optional): Portainer

Between the OTel Demo stack (~20 containers), ClickStack, and optionally Zipkin, `docker ps`/`docker logs` gets unwieldy fast. [Portainer CE](https://github.com/portainer/portainer) is an open-source web GUI for monitoring and managing containers, images, volumes, and logs.

Install and run it, skipping Portainer's own first-run setup-token flow so you land straight in the UI:

```bash
docker run -d --name portainer -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer-ce --no-setup-token
```

Open **http://localhost:9000** — no admin account/token step, straight into the dashboard listing all running containers.

> **Local dev only:** `--no-setup-token` skips authentication entirely, and the container has full access to the host's Docker socket — anyone who can reach port 9000 has root-equivalent control over your Docker daemon. Fine for a `localhost`-only dev setup; don't expose this port beyond your own machine.

**Stop it:**

```bash
docker stop portainer
docker rm portainer
```
