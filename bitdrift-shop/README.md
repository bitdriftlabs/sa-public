# bitdrift Shop

**Version 1.0**

A full-stack e-commerce demo that generates realistic mobile shopping traffic — browsing, searching, cart management, checkout, and payment — with built-in journey simulation and chaos testing. The apps are instrumented with the bitdrift Capture SDK.

Each app implements the same 19-screen shopping flow and the same probabilistic simulation logic, and all of them talk to one shared backend.

## Apps and OS versions

| App | Folder | Stack | Platforms / minimum OS |
|-----|--------|-------|------------------------|
| **Android** | [android/](android/) | Kotlin, Jetpack Compose, Material 3 (Kotlin 2.x, AGP 8.x) | Android — `minSdk 26` (Android 8.0), compiled against SDK 36 |
| **iOS** | [ios/](ios/) | Native Swift + SwiftUI, SDK-instrumented | iOS — deployment target 16.0 |
| **React Native** | [reactnative/](reactnative/) | TypeScript, React Native 0.77, React 18, React Navigation | Android and iOS (iOS deployment target 13.4) |
| **Kotlin Multiplatform- Work in Process** | [wip-kotlin-multiplatform/](wip-kotlin-multiplatform/) | Kotlin 2.1 shared logic; Jetpack Compose (Android) + SwiftUI (iOS) | Android — `minSdk 26`; iOS app — deployment target 16.0 |
| **Backend** | [backend/](backend/) | Python 3.10+, FastAPI, Uvicorn | Runs locally (tested on macOS) |

> **iOS** has an SDK-instrumented native SwiftUI app in [ios/](ios/). React Native and Kotlin Multiplatform remain separate app variants.
>
> The native iOS app is a direct port of the Android one — same 19 screens, same probabilistic simulation, and the same event, field, screen, and span names — so both feed the same `bd-shop-*` workflows and can be compared side by side. Where the platform left no choice (self-relaunch after a crash, ANR, frame-jank detection), [ios/README.md](ios/README.md#how-this-differs-from-the-android-app) documents the deviation.

## Testing (command line, no IDE)

```bash
./test.sh all unit      # seconds: codegen drift, spec validation, conformance self-test, each app's compile/unit tests
./test.sh all smoke     # ~5 min: build, install and launch every app, auto-run 5 journeys, validate what it emitted
./test.sh android smoke # one app: android | ios | rn-android | rn-ios | flutter-android | flutter-ios
```

`smoke` needs a running (or bootable) Android emulator and iOS simulator, and runs the sim with no taps.
Tune it with `SIM_RUNS`, `SIM_SEED` and `PERSONA` (`control`, `variant_a`, `variant_b`). Each app records the
logs, spans and screen views it emits, and [`tools/conformance`](tools/conformance/conformance.py) checks them
against [`spec/`](spec/): known names, required fields, levels, closed spans, one `sim_autorun_complete` marker.

- Android and iOS take launch arguments (`sim_runs`, `sim_seed`, `persona`, `record_file`) and write the record on the device.
- React Native and Flutter can't without native code, so in debug builds they ask a local collector
  (`tools/conformance/collector.py`, started by `test.sh`) for the autorun config and POST their records to it.
- `tools/codegen/generate.sh` regenerates every app's constants from `spec/`; `tools/codegen/check.sh` fails if they drift.

## The backend (shared by every app)

A single FastAPI server is the common element across all the apps. It serves a catalog of 18 products across categories (Electronics, Clothing, Home & Garden, Sports) and exposes the browse, search, cart, checkout, and payment endpoints each app calls. Every app points at the same locally-run server, so behavior and traffic stay consistent regardless of platform.

The backend also supports a **chaos mode** that injects faults (latency, 4xx/5xx, truncated payloads, payment failures, rate limiting) for resilience testing. See [backend/README.md](backend/README.md) for endpoints, configuration, and chaos controls.

## Simulation

Each app's Welcome screen can drive automated user journeys, producing varied, lifelike sessions (browsing, cart add/remove, wishlist, guest vs. member checkout, multiple payment methods, cart and checkout abandonment, payment failure and retry). The journey is defined once, in [`spec/journey.yaml`](spec/journey.yaml), and every app runs it through the same small interpreter ([tools/journey](tools/journey/README.md)). Persona presets (Control / Variant A / Variant B) bias the choices, and a seed makes a run reproducible: the same persona and seed give the same journey on every app. Details live in each app's own README.

## Instrumenting an app

The bitdrift Capture SDK integration shown across these apps is documented platform-neutrally in the repository's **[instrumentation-guide/](../instrumentation-guide/)** — a step-by-step guide that works for any app, plus a matching cleanup guide. Use that as the reference for what each SDK feature unlocks and how to wire it up.

## Where to look

Build and run instructions live in each app's own folder. Start with the README in the app you're interested in:

- [android/](android/) — Android app
- [ios/](ios/) — native SwiftUI iOS app
- [reactnative/](reactnative/) — React Native app (Android + iOS)
- [flutter/](flutter/) — Flutter app (Android + iOS)
- [wip-kotlin-multiplatform/](wip-kotlin-multiplatform/) — Work in process- Kotlin Multiplatform app (Android + iOS)
- [backend/](backend/) — FastAPI server, API endpoints, and chaos mode
- [sessionmetricsdemo/](sessionmetricsdemo/) — portable session count/duration/crash-rate workflows (work in process)

## One spec, four apps

The apps share data, not code. [`spec/`](spec/README.md) holds the screens, event, field and span names, feature flags, persona probabilities, and the journey itself. Each app is built from it:

- **Generated constants:** every name an app logs comes from `spec/` (`tools/codegen`), so the platforms cannot drift apart.
- **One journey, run everywhere:** each app interprets [`spec/journey.yaml`](spec/journey.yaml) with a small engine. Change a probability or a step once, run `tools/codegen/generate.sh`, and all four apps behave differently together.
- **Reproducible and checked:** the same persona and seed give the same journey on every app. `./test.sh all unit` replays golden traces on every engine. `./test.sh all smoke` runs each app on a device, checks its recording against the reference engine, and diffs the apps against each other.

The apps themselves stay idiomatic Kotlin, Swift, TypeScript and Dart, so each one still reads like a normal customer app.
