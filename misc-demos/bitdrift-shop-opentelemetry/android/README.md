# Bitdrift Shop - OpenTelemetry (Android)

Kotlin/Jetpack Compose client for the bitdrift-shop-opentelemetry demo. See the
[root README](../README.md) first for backend prerequisites (Colima/Docker) and the Quick Start
that gets ClickStack + the OTel Demo backend running — this doc picks up from there: SDK
configuration, tracing wiring, and how to run this app.

## Local Config

Copy `.local.properties.example` to `.local.properties` (gitignored) and fill in
real values — the example file documents every flag below, plus its default and env-var fallback.

```properties
BITDRIFT_SDK_KEY=your_key_here
BITDRIFT_API_HOST=api.bitdrift.io
```

The OTel Demo backend in this setup runs on **8081**, not the default 8080 (8080 is left free for ClickStack — see [root README](../README.md#1-set-up-clickstack)). Add these to the same `.local.properties` file so the app points at it (defaults to Android emulator → host):

```properties
OTEL_DEMO_HOST=10.0.2.2
OTEL_DEMO_PORT=8081
```

To also export bitdrift-side spans to ClickStack (see [OTel span export](#otel-span-export-experimental) below), add:

```properties
BITDRIFT_USE_LOCAL_AAR=/absolute/path/to/libs/capture-release.aar
BITDRIFT_ENABLE_OTEL_EXPORT=true
CLICKSTACK_ENDPOINT=http://10.0.2.2:4318/v1/traces
CLICKSTACK_INGESTION_API_KEY=your_clickstack_ingestion_key
```

`CLICKSTACK_INGESTION_API_KEY` is minted per ClickStack team on signup (Team Settings → API Keys in the ClickStack UI, [root README step 1](../README.md#1-set-up-clickstack)) — it changes if the ClickStack container is ever removed and recreated (a `docker stop`/`start` keeps it; `docker rm` does not), so re-check it here if spans stop showing up.

`BITDRIFT_ENABLE_OTEL_EXPORT` defaults to whatever `BITDRIFT_USE_LOCAL_AAR` resolves to (on when
using the local AAR, off otherwise), so most setups never need to set it explicitly. It exists
because `OtelExportConfiguration` only exists in the local AAR, not the published
`io.bitdrift:capture` Maven Central artifact — so this flag picks between two Gradle source sets
(`app/src/otelExportEnabled`/`app/src/otelExportDisabled`) at build time rather than being a plain
runtime toggle. Set it to `false` to build against the local AAR *without* the OTel wiring (e.g.
testing the AAR as a drop-in replacement), or leave everything above unset/commented to build
against the published SDK — either way the build fails fast with a clear error if you set it to
`true` without also setting `BITDRIFT_USE_LOCAL_AAR`.

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

This isn't in a published `io.bitdrift:capture` release yet, so this repo bundles a locally
built AAR from the `slerner/bit-9050-otel-span-poc` branch of
[capture-sdk](https://github.com/bitdriftlabs/capture-sdk) directly under `libs/`
(tracked in git, despite the general `*.aar` gitignore rule — see the exception in the repo root's `.gitignore`)
so you don't need a capture-sdk checkout just to try this out.

**(Optional) Refreshing the bundled AARs**, e.g. after a capture-sdk change on that branch:

```bash
git clone https://github.com/bitdriftlabs/capture-sdk
cd capture-sdk
git checkout slerner/bit-9050-otel-span-poc
cd platform/jvm
./gradlew :capture:assembleRelease :replay:assembleRelease :common:assembleRelease
cp capture/build/outputs/aar/capture-release.aar \
   replay/build/outputs/aar/replay-release.aar \
   common/build/outputs/aar/common-release.aar \
   /path/to/bitdrift-shop-opentelemetry/android/libs/
```

Then set `BITDRIFT_USE_LOCAL_AAR`/`BITDRIFT_ENABLE_OTEL_EXPORT`/`CLICKSTACK_ENDPOINT`/`CLICKSTACK_INGESTION_API_KEY` in
`.local.properties` as shown in [Local Config](#local-config) — `:replay` and `:common` are
capture-sdk's own internal Gradle modules, not published Maven coordinates, so all three AARs
are required together or the app crashes at startup with `NoClassDefFoundError` on
`io.bitdrift.capture.replay.SessionReplayConfiguration`.

A span only exports once tracing is actually active for the session — the
[Deploy the session-capture workflow](#deploy-the-session-capture-workflow) step below already
covers this, since [capture-all-sessions.json](workflows/README.md) includes a
`start_tracing_rule` alongside the capture/flush rule.

## Deploy the session-capture workflow

Before running the live demo, publish the workflow that guarantees every session gets fully
captured — a capture workflow only sees sessions that start *after* it deploys, so this needs to
happen before you start driving traffic through the app, not mid-demo.

Run from this `android/` directory. This step needs the `bd` CLI, authenticated:

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

## Run the Android app

Set `OTEL_DEMO_PORT=8081` in `.local.properties` (see [Local Config](#local-config)), then open the project in Android Studio and run on an emulator. The app connects via `http://10.0.2.2:8081`. See [Emulator Requirements](../APPENDIX.md#emulator-requirements) in the appendix for supported configs.

**(Optional) No Android Studio?** `scripts/android-{1..5}-*.sh` set up the SDK/AVD, boot the emulator, and build+install+launch from the command line instead — modeled on [bitdrift-shop/android's own no-Studio scripts](../../../bitdrift-shop/android/scripts/):

```bash
./scripts/android-1-setup.sh          # one-time: cmdline-tools, SDK packages, AVD
./scripts/android-2-start-emulator.sh # boot and wait for it to come up
./scripts/android-3-start-app.sh      # gradlew install<Variant> + launch
./scripts/android-4-stop-app.sh       # force-stop, leaves the emulator running
./scripts/android-5-stop-emulator.sh  # kill the emulator
```

## Further reading

- [../APPENDIX.md](../APPENDIX.md) — troubleshooting notes and reference material, including several Android-specific sections (Screens list, Project Structure, Architecture diagram, Emulator Requirements)
- [readme-anr.md](readme-anr.md) — a worked `bd` CLI investigation correlating the ANR simulation with Sankey funnel data
- [workflows/README.md](workflows/README.md) — the session-capture workflow JSON and how to deploy it by hand
