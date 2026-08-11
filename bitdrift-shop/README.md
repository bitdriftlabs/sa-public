# bitdrift Shop

**Version 1.0**

A full-stack e-commerce demo that generates realistic mobile shopping traffic — browsing, searching, cart management, checkout, and payment — with built-in journey simulation and chaos testing. It exists to exercise the **bitdrift Capture SDK** across platforms with lifelike sessions.

Each app implements the same 16-screen shopping flow and the same probabilistic simulation logic, and all of them talk to one shared backend.

## Apps and OS versions

| App | Folder | Stack | Platforms / minimum OS |
|-----|--------|-------|------------------------|
| **Android** | [android/](android/) | Kotlin, Jetpack Compose, Material 3 (Kotlin 2.x, AGP 8.x) | Android — `minSdk 26` (Android 8.0), compiled against SDK 36 |
| **iOS** | [ios/](ios/) | 100% native Swift + SwiftUI (capture-ios 0.23.11 via SPM; no ObjC, no KMP) | iOS — deployment target 16.0 |
| **React Native** | [reactnative/](reactnative/) | TypeScript, React Native 0.77, React 18, React Navigation | Android and iOS (iOS deployment target 13.4) |
| **Kotlin Multiplatform- Work in Process** | [kotlin-multiplatform/](kotlin-multiplatform/) | Kotlin 2.1 shared logic; Jetpack Compose (Android) + SwiftUI (iOS) | Android — `minSdk 26`; iOS app — deployment target 16.0 |
| **Backend** | [backend/](backend/) | Python 3.10+, FastAPI, Uvicorn | Runs locally (tested on macOS) |

> **iOS** has a native SwiftUI app in [ios/](ios/), and also ships through the React Native app and the Kotlin Multiplatform iOS app. All apps included here are the **SDK-instrumented** variants.
>
> The native iOS app is a direct port of the Android one — same 19 screens, same probabilistic simulation, and the same event, field, screen, and span names — so both feed the same `bd-shop-*` workflows and can be compared side by side. Where the platform left no choice (self-relaunch after a crash, ANR, frame-jank detection), [ios/README.md](ios/README.md#how-this-differs-from-the-android-app) documents the deviation.

## The backend (shared by every app)

A single FastAPI server is the common element across all the apps. It serves a catalog of 18 products across categories (Electronics, Clothing, Home & Kitchen, Sports, Books) and exposes the browse, search, cart, checkout, and payment endpoints each app calls. Every app points at the same locally-run server, so behavior and traffic stay consistent regardless of platform.

The backend also supports a **chaos mode** that injects faults (latency, 4xx/5xx, truncated payloads, payment failures, rate limiting) for resilience testing. See [backend/README.md](backend/README.md) for endpoints, configuration, and chaos controls.

## Simulation

Each app's Welcome screen can drive automated user journeys via a probabilistic state machine, producing varied, lifelike sessions (browsing, cart add/remove, wishlist, guest vs. member checkout, multiple payment methods, and cart abandonment). The Android and iOS apps additionally offer persona presets (Variant A / Variant B / Control) that bias the simulator. Details live in each app's own README.

## Instrumenting an app

The bitdrift Capture SDK integration shown across these apps is documented platform-neutrally in the repository's **[instrumentation-guide/](../instrumentation-guide/)** — a step-by-step guide that works for any app, plus a matching cleanup guide. Use that as the reference for what each SDK feature unlocks and how to wire it up.

## Where to look

Build and run instructions live in each app's own folder. Start with the README in the app you're interested in:

- [android/](android/) — Android app
- [ios/](ios/) — native SwiftUI iOS app
- [reactnative/](reactnative/) — React Native app (Android + iOS)
- [kotlin-multiplatform/](kotlin-multiplatform/) — Work in process- Kotlin Multiplatform app (Android + iOS)
- [backend/](backend/) — FastAPI server, API endpoints, and chaos mode
