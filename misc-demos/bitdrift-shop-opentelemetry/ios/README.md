# Bitdrift Shop - OpenTelemetry (iOS)

Swift/SwiftUI client for the bitdrift-shop-opentelemetry demo — a port of `android/` (same
screens, same probabilistic simulation logic) used to test the iOS Capture SDK's OTel span
export. See the [root README](../README.md) first for backend prerequisites (Colima/Docker) and
the Quick Start that gets ClickStack + the OTel Demo backend running — this doc picks up from
there: SDK configuration, tracing wiring, and how to build/run this app.

**Status:** working end to end — verified via direct ClickHouse queries that a traced request's
bitdrift-emitted span is the correlating root of the OTel Demo backend's own distributed trace
(same trace ID, backend spans' `ParentSpanId` matching the bitdrift span's ID).

## Local Config

Copy `local.xcconfig`'s companion gitignored file — create `.local.xcconfig` in this directory —
and fill in real values. `local.xcconfig` (committed) documents every key and `#include?`s
`.local.xcconfig` at the bottom, mirroring `android/`'s `.local.properties.example`/`.local.properties`
split (and `bitdrift-shop/ios-clean/local.xcconfig`'s precedent).

```
BITDRIFT_SDK_KEY = your_key_here
BITDRIFT_API_HOST = api.bitdrift.io
```

The OTel Demo backend runs on **8081** (8080 is left free for ClickStack — see
[root README](../README.md#1-set-up-clickstack)). Unlike Android's emulator (which needs the
`10.0.2.2` NAT alias), the iOS Simulator shares the Mac's network directly, so `localhost` just
works:

```
OTEL_DEMO_HOST = localhost
OTEL_DEMO_PORT = 8081
```

**On a physical device**, `localhost` won't resolve to your Mac — set `OTEL_DEMO_HOST` to your
Mac's LAN address instead (`ipconfig getifaddr en0`).

To also export bitdrift-side spans to ClickStack (see [OTel span export](#otel-span-export-experimental) below), add:

```
CLICKSTACK_ENDPOINT = http:/$()/localhost:4318/v1/traces
CLICKSTACK_INGESTION_API_KEY = your_clickstack_ingestion_key
```

`xcconfig` treats `//` as a comment, so a URL needs the empty-variable trick above
(`http:/$()/...`) to keep the double slash from being parsed as one. `CLICKSTACK_INGESTION_API_KEY`
is minted per ClickStack team on signup (Team Settings → API Keys in the ClickStack UI,
[root README step 1](../README.md#1-set-up-clickstack)) — it changes if the ClickStack container
is ever removed and recreated (`docker rm`, not `docker stop`/`start`), so re-check it here if
spans stop showing up.

Unlike Android's `BITDRIFT_USE_LOCAL_AAR`, there's no local-vs-published SDK toggle here — see the
note in `local.xcconfig` for why (Xcode resolves `project.yml`'s framework dependency once at
`xcodegen generate` time, not at build time) and what it'd take to add one.

## Tracing (bitdrift)

Unlike Android's per-client OkHttp interceptor (a deliberate manual-wiring teaching step in that
app), iOS's `URLSession` integration is a single process-wide swizzle with no per-client
opt-out — `integrator?.enableIntegrations([.urlSession()])` in `ShoppingDemoApp.swift` turns on
tracing for every `URLSession.shared` request in the process. There's no manual/automatic
distinction to preserve on this platform.

Reference: [Tracing: Network integration](https://docs.bitdrift.io/sdk/features/tracing.html#network-integration)

### OTel span export (experimental)

On top of the trace-header injection above, the SDK emits an OpenTelemetry `CLIENT` span for
each traced network request — same trace ID and span ID already in the header — and exports it
directly to an OTLP/HTTP endpoint (ClickStack here). This is the same feature as Android's, built
against a Rust FFI bridge shared with the JNI implementation (`bd-otlp-traces` in `shared-core`),
but the Swift bridge encodes attributes as a delimited string rather than an `NSArray`, since no
existing marshaling template for that existed in this codebase's C bridge.

This isn't in a published `Capture` release yet, and — unlike Android's committed AAR — the
built `Capture.xcframework` is **not** checked into this repo; it's a local build artifact only.
Build it from a `capture-sdk` checkout (defaults to `/Users/slerner/Code/repos/capture-sdk`,
override with `CAPTURE_SDK_DIR`):

```bash
./scripts/ios-1-build-sdk.sh
```

This runs `./bazelw build //:ios_dist` in that checkout and unzips the resulting
`Capture.xcframework` into `Frameworks/`. Re-run it any time the SDK changes.

`Capture.xcframework` is a **static** framework (an `ar` archive, not a dynamic Mach-O) — it's
linked but not embedded (`embed: false` in `project.yml`); embedding it produces an
"Framework did not contain an Info.plist" link error.

A span only exports once `OtelExportConfiguration` is non-nil (both `CLICKSTACK_ENDPOINT` and
`CLICKSTACK_INGESTION_API_KEY` set in `.local.xcconfig`, see [Local Config](#local-config)) **and**
tracing is actually active for the session — see
[Deploy the session-capture workflow](#deploy-the-session-capture-workflow) below.

Trace-header injection is done via a registered `URLProtocol` (`CaptureURLProtocol`), not by
mutating the request after a `URLSessionTask` already exists — the latter doesn't affect the
actual wire request on current iOS (confirmed via a standalone repro; see
`capture-sdk/docs/agent-tasks/otel-span-export-plan.md`'s "What we learned building iOS" for the
full writeup, including why `URLSession.data(for:)` needed this and not a simpler swizzle). This
app's `Capture.xcframework` also requires `OTHER_LDFLAGS: -ObjC` (already set in `project.yml`) —
without it, the network-capture hook (an Objective-C category in a static framework) never
installs, silently: no network request/response logs, no spans, no error at build or launch time.

## Deploy the session-capture workflow

Mirrors [android/README.md's equivalent step](../android/README.md#deploy-the-session-capture-workflow),
scoped to this app's own bundle ID (`ai.bitdrift.oteldemo.ios`) via
[workflows/capture-all-sessions.json](workflows/capture-all-sessions.json). Without this deployed,
`Logger.isTracingActive` stays `false` for every session — screen views and plain logs still get
captured, but trace headers never get injected and no OTel spans ever export, regardless of the
`.local.xcconfig` config above.

```bash
./scripts/deploy-capture-workflow.sh
```

Idempotent — safe to re-run. See [workflows/README.md](workflows/README.md) for details.

## Run the iOS app

Requires [Xcode](https://developer.apple.com/xcode/) and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — this project generates its `.xcodeproj` from `project.yml` rather than committing a hand-edited one.

```bash
./scripts/ios-1-build-sdk.sh          # build/refresh Frameworks/Capture.xcframework (see above)
./scripts/ios-2-generate-project.sh   # xcodegen generate -> BitdriftShopOtel.xcodeproj
open BitdriftShopOtel.xcodeproj
```

Then build and run on a simulator or device from Xcode. Re-run `ios-2-generate-project.sh` any
time you edit `project.yml` (it fully regenerates the project, including `Info.plist` from
`project.yml`'s `info.properties` — hand-editing `Info.plist` directly gets clobbered on the next
`generate`).

Deployment target is iOS 16.0 (this app's `NavigationStack`/`NavigationPath` usage requires it;
the SDK itself supports back to iOS 15.0 per `capture-sdk/CLAUDE.md`).

**(Optional) No Xcode UI?** `scripts/ios-{3..6}-*.sh` boot a simulator and build+install+launch
from the command line instead — modeled on
[bitdrift-shop/ios's own no-Xcode scripts](../../../bitdrift-shop/ios/scripts/), after the two steps
above have built the SDK and generated the project:

```bash
./scripts/ios-3-start-simulator.sh # boot a simulator (default: iPhone 18 Pro) and open its window
./scripts/ios-4-start-app.sh       # xcodebuild + simctl install/launch
./scripts/ios-5-stop-app.sh        # terminate the app, leaves the simulator running
./scripts/ios-6-stop-simulator.sh  # shut down the simulator
```

Command-line equivalent of a plain compile check (e.g. for CI), without installing/launching:

```bash
xcodebuild -project BitdriftShopOtel.xcodeproj -scheme BitdriftShopOtel \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -configuration Debug build
```
