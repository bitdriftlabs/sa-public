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

## Testing

`./test.sh all unit` (seconds) and `./test.sh all smoke` (about 5 minutes) run from the command line with no IDE. See [docs/TESTING.md](docs/TESTING.md).

## Emulators and simulators (shared by every app)

One set of scripts in `scripts/device/` boots and stops the devices, whichever app you are running:

```bash
scripts/device/android-emulator.sh start|stop     # AVD_NAME, EMULATOR_WINDOW=0 (headless), EMU_GPU
scripts/device/ios-simulator.sh start|stop        # DEVICE_NAME, MIN_IOS_VERSION
scripts/device/stop-app.sh <native|rn|flutter> <android|ios>   # stop the app, leave the device running
```

Each app's `scripts/*-2-start-app.sh` (React Native: `./start.sh ios|android`) then builds, installs and launches
on whatever device is booted. A typical session, from an app directory such as `android/`:

```bash
../scripts/device/android-emulator.sh start     # or ios-simulator.sh start
./scripts/android-2-start-app.sh                # build + install + launch
../scripts/device/stop-app.sh native android    # stop the app, device keeps running
../scripts/device/android-emulator.sh stop      # shut the device down
```

Defaults: Android AVD `Medium_Phone`, software rendering on macOS (the hardware GPU backend hangs or crashes);
iOS device `iPhone 17 Pro`, falling back to any iPhone on iOS 26.0 or newer. `./test.sh <app> smoke` boots what
it needs through these same scripts.

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

The apps share data, not code: one [`spec/`](spec/README.md) holds the screens, event names and the journey, and each app is generated from it. See [docs/SPEC.md](docs/SPEC.md).
