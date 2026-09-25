# Bitdrift Shop - OpenTelemetry (Android — SDK)

A demo Android app simulating an e-commerce shopping experience, instrumented with the **bitdrift Capture SDK** and backed by the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) Telescope Store.

## Quick Links

Once the stack is running ([Quick Start](#quick-start) below), these are the local URLs you'll come back to most:

| Service | URL | What it's for |
|---|---|---|
| **HyperDX / ClickStack** | [http://localhost:8080](http://localhost:8080) | Logs, traces, metrics, session replay |
| **OTel Demo (app backend)** | [http://localhost:8081](http://localhost:8081) | The frontend proxy the Android app talks to |
| **Portainer** (optional) | [http://localhost:9000](http://localhost:9000) | Container manager/dashboard — see [Container Monitoring](#container-monitoring-optional-portainer) |
| **Zipkin** (if using B3 instead of ClickStack) | [http://localhost:9411](http://localhost:9411) | See [B3_ZIPKIN.md](B3_ZIPKIN.md) |

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

To also export bitdrift-side spans to ClickStack (see [OTel span export](#otel-span-export-experimental) below), add:

```properties
BITDRIFT_USE_LOCAL_AAR=/absolute/path/to/libs/capture-release.aar
CLICKSTACK_ENDPOINT=http://10.0.2.2:4318/v1/traces
CLICKSTACK_INGESTION_API_KEY=your_clickstack_ingestion_key
```

`CLICKSTACK_INGESTION_API_KEY` is minted per ClickStack team on signup (Team Settings → API Keys in the ClickStack UI, step 1 below) — it changes if the ClickStack container is ever removed and recreated (a `docker stop`/`start` keeps it; `docker rm` does not), so re-check it here if spans stop showing up.

## Tracing (bitdrift)

`ApiClient.kt` uses bitdrift's manual OkHttp tracing integration:

- `CaptureOkHttpTracingInterceptor()` — injects trace context headers
- `CaptureOkHttpEventListenerFactory()` — records network spans

Gradle auto OkHttp instrumentation is disabled (`automaticOkHttpInstrumentation=false`) to avoid duplicate paths. Trace propagation format and sampling are controlled remotely via the bitdrift dashboard.

Reference: [Tracing: Network integration](https://docs.bitdrift.io/sdk/features/tracing.html#network-integration)

### OTel span export (experimental)

On top of the trace-header injection above, the SDK can also emit an OpenTelemetry `CLIENT`
span for each traced network request — same trace ID and span ID already in the header — and
export it directly to an OTLP/HTTP endpoint (ClickStack here). This turns the mobile app into
the root of the trace instead of an invisible caller ahead of the OTel Demo backend's own spans.

This isn't in a published `io.bitdrift:capture` release yet — it needs a locally built AAR from
the `slerner/bit-9050-otel-span-poc` branch of
[capture-sdk](https://github.com/bitdriftlabs/capture-sdk):

```bash
git clone https://github.com/bitdriftlabs/capture-sdk
cd capture-sdk
git checkout slerner/bit-9050-otel-span-poc
cd platform/jvm
./gradlew :capture:assembleRelease :replay:assembleRelease :common:assembleRelease
```

Copy the three resulting AARs into this project's `android/libs/` (gitignored, not committed):

```bash
cp capture/build/outputs/aar/capture-release.aar \
   replay/build/outputs/aar/replay-release.aar \
   common/build/outputs/aar/common-release.aar \
   /path/to/bitdrift-shop-opentelemetry/android/libs/
```

Then set `BITDRIFT_USE_LOCAL_AAR`/`CLICKSTACK_ENDPOINT`/`CLICKSTACK_INGESTION_API_KEY` in
`.local.properties` as shown in [Local Config](#local-config) — `:replay` and `:common` are
capture-sdk's own internal Gradle modules, not published Maven coordinates, so all three AARs
are required together or the app crashes at startup with `NoClassDefFoundError` on
`io.bitdrift.capture.replay.SessionReplayConfiguration`.

A span only exports once tracing is actually active for the session — the "Deploy the
session-capture workflow" step below already covers this, since
[capture-all-sessions.json](android/workflows/README.md) includes a `start_tracing_rule`
alongside the capture/flush rule.

## Prerequisites (macOS)

The OTel Demo backend is a `docker compose` stack, so it needs a Docker daemon — but
**not Docker Desktop**. Like the rest of `bitdrift-shop` in this repo (see
[bitdrift-shop/backend/README.md#prerequisites-macos](../../bitdrift-shop/backend/README.md#prerequisites-macos)),
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
needs more RAM than Colima's default VM — see [Memory Requirements](APPENDIX.md#memory-requirements)
in the appendix.

### Container Monitoring (Optional): Portainer

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
[Switch to B3 Propagation and Zipkin (Optional)](APPENDIX.md#switch-to-b3-propagation-and-zipkin-optional).)

[ClickStack](https://github.com/ClickHouse/ClickStack) is ClickHouse's open-source observability stack for OpenTelemetry — logs, traces, metrics, and session replay in one UI. (Formerly branded standalone as "HyperDX" — same image, ports, and API, just repackaged/renamed under ClickHouse.) It's an export target for the OTel Collector — no B3 override or propagation change required, it works with the stock W3C setup from step 2.

> **Memory requirement:** the ClickStack container needs significantly more RAM than Colima's/Docker Desktop's default VM — see [Memory Requirements](APPENDIX.md#memory-requirements) in the appendix before proceeding.

Run the ClickStack all-in-one container standalone (it does **not** join the `opentelemetry-demo` docker network — it's just a container on your host). Name it so it's easy to manage/restart later:

Make sure Colima is running first — with the memory bump from [Memory Requirements](APPENDIX.md#memory-requirements) if you haven't already applied it:

```bash
colima start
docker run -d --name clickstack -p 8080:8080 -p 4317:4317 -p 4318:4318 docker.hyperdx.io/hyperdx/hyperdx-all-in-one
```

> The image itself is still published under the `hyperdx` Docker namespace (`docker.hyperdx.io/hyperdx/hyperdx-all-in-one`) — that's just the registry path and is current/correct. Everywhere else in this doc refers to it as ClickStack.

> **Port note:** ClickStack's UI defaults to host port 8080 — the same port the OTel Demo `frontend-proxy` normally wants. Step 2 moves the frontend proxy to `8081` via `ENVOY_PORT` so both can run at once.

Open **http://localhost:8080** and sign up (any email/password works locally) — this auto-creates a team and an ingestion API key. Grab the key from **Team Settings → API Keys** in the UI.

> **Grab the key now and hold onto it** — the next step (starting the OTel Demo backend) uses it to configure the collector's ClickStack exporter before the backend's first boot.

> **Persistence:** this container is run without an explicit `-v` volume flag, but the image itself declares an internal `VOLUME` for `/var/lib/clickhouse`, so Docker silently creates an anonymous volume for it — data survives a `docker stop`/`start` or a Colima/Docker VM restart. It's only lost if the container is removed (`docker rm`) without also removing that volume. If you need a true reset (e.g. after corrupted state), see [Fully purging ClickStack / HyperDX](APPENDIX.md#fully-purging-clickstack--hyperdx) in the appendix — that also creates a **new** team + API key on next signup, so re-check the key if traces stop showing up after a purge.

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

- **Stop the whole demo** (OTel Demo stack + ClickStack + Portainer) — use this before a Colima/Docker restart if you don't want everything auto-relaunching:

```bash
android/scripts/stop-backend.sh
```

The OTel Demo stack's services all use `restart: unless-stopped`, so a plain `colima stop && colima start` brings them back on its own — Docker only respects that policy once a container has been explicitly stopped first. This script stops everything (without removing containers/volumes) so a subsequent Colima restart leaves them down until you deliberately bring them back up.

> Colima itself only needs restarting if you changed its VM resources (see [Memory Requirements](APPENDIX.md#memory-requirements)) or it's not running (`colima status`) — the backend restart commands above don't touch the VM.

> **Troubleshooting — `frontend-proxy` restart-looping:** if `docker ps` shows `frontend-proxy` stuck in a restart loop, check `docker logs frontend-proxy` for an Envoy `Proto constraint validation failed` error on a socket address. This means the image you pulled (`ghcr.io/open-telemetry/demo:latest-frontend-proxy`) is newer than your local `opentelemetry-demo` checkout — its baked-in `envoy.tmpl.yaml` references env vars (e.g. `OPAMP_HOST`/`OPAMP_PORT`) that your local `compose.yaml`/`.env` don't set, so they render empty and Envoy rejects the config. Fix by building the image from your local source instead of the stale pulled one:
>
> ```bash
> ENVOY_PORT=8081 docker compose -f compose.yaml build frontend-proxy
> ```
>
> then re-run the `up` command above.

To view traces once the app (next step) is running and you've generated some traffic:

- Open **http://localhost:8080**
- Tap **Sim 10** in the app
- Search or browse traces/logs/metrics in the ClickStack UI — data lands within a few seconds
- To sanity-check ingestion directly in ClickHouse: `docker exec clickstack sh -c "curl -s 'http://localhost:8123/?query=SELECT+count()+FROM+otel_traces'"`

### 3. Deploy the session-capture workflow

Before running the live demo, publish the workflow that guarantees every session gets fully
captured — a capture workflow only sees sessions that start *after* it deploys, so this needs to
happen before you start driving traffic through the app, not mid-demo.

Run from the `android/` directory. This step needs the `bd` CLI, authenticated:

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
[android/workflows/README.md](android/workflows/README.md) for what it deploys and how to do it by hand with `bd`.

### 4. Run the Android app

Set `OTEL_DEMO_PORT=8081` in `.local.properties` (see [Local Config](#local-config)), then open the project in Android Studio and run on an emulator. The app connects via `http://10.0.2.2:8081`. See [Emulator Requirements](APPENDIX.md#emulator-requirements) in the appendix for supported configs.

**(Optional) No Android Studio?** `scripts/android-{1..5}-*.sh` set up the SDK/AVD, boot the emulator, and build+install+launch from the command line instead — modeled on [bitdrift-shop/android's own no-Studio scripts](../../bitdrift-shop/android/scripts/):

```bash
cd android
./scripts/android-1-setup.sh          # one-time: cmdline-tools, SDK packages, AVD
./scripts/android-2-start-emulator.sh # boot and wait for it to come up
./scripts/android-3-start-app.sh      # gradlew install<Variant> + launch
./scripts/android-4-stop-app.sh       # force-stop, leaves the emulator running
./scripts/android-5-stop-emulator.sh  # kill the emulator
```

### 5. Appendix

See [APPENDIX.md](APPENDIX.md) for troubleshooting notes and reference material that don't fit the quick-start flow above:

- Colima not mounting an external-drive checkout, causing `otel-collector` to crash-loop (and how to make the mount permanent)
- `astronomy-db` missing its `astronomy_user` role after a broken first boot, causing `product-catalog` to crash-loop and product images to go missing
- A full audit runbook for checking the rest of the stack after a Colima mount fix, so no other services are silently running on bad first-boot state
- A missing `OTEL_DEMO_HOST`/`OTEL_DEMO_PORT` in `.local.properties` silently pointing the app at ClickStack's port instead of the backend — looks exactly like a backend bug but never reaches the OTel Demo stack at all
- Fully purging ClickStack/HyperDX's hidden anonymous data volume when the UI errors out or shows stale data
- The Screens list, Project Structure, Architecture diagram, and the B3/Zipkin, Memory, and Emulator requirements reference material
