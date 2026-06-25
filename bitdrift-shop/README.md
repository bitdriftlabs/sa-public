# bitdrift Shop

**Version 1.0**

A full-stack e-commerce demo that generates realistic mobile shopping traffic — browsing, searching, cart management, checkout, and payment — with built-in journey simulation and chaos testing. It exists to exercise the **bitdrift Capture SDK** across platforms with lifelike sessions.

Each app implements the same 16-screen shopping flow and the same probabilistic simulation logic, and all of them talk to one shared backend.

## Apps and OS versions

| App | Folder | Stack | Platforms / minimum OS |
|-----|--------|-------|------------------------|
| **Android** | [android/sdk/](android/sdk/) | Kotlin, Jetpack Compose, Material 3 (Kotlin 2.x, AGP 8.x) | Android — `minSdk 26` (Android 8.0), compiled against SDK 36 |
| **React Native** | [reactnative/sdk/](reactnative/sdk/) | TypeScript, React Native 0.77, React 18, React Navigation | Android and iOS (iOS deployment target 13.4) |
| **Kotlin Multiplatform** | [kotlin-multiplatform/sdk/](kotlin-multiplatform/sdk/) | Kotlin 2.1 shared logic; Jetpack Compose (Android) + SwiftUI (iOS) | Android — `minSdk 26`; iOS app — deployment target 16.0 |
| **Backend** | [backend/](backend/) | Python 3.10+, FastAPI, Uvicorn | Runs locally (tested on macOS) |

> **iOS** ships through the React Native app and the Kotlin Multiplatform iOS app; there is no separate native Swift app in this repository. All apps included here are the **SDK-instrumented** variants.

## The backend (shared by every app)

A single FastAPI server is the common element across all the apps. It serves a catalog of 18 products across categories (Electronics, Clothing, Home & Kitchen, Sports, Books) and exposes the browse, search, cart, checkout, and payment endpoints each app calls. Every app points at the same locally-run server, so behavior and traffic stay consistent regardless of platform.

The backend also supports a **chaos mode** that injects faults (latency, 4xx/5xx, truncated payloads, payment failures, rate limiting) for resilience testing. See [backend/README.md](backend/README.md) for endpoints, configuration, and chaos controls.

## Simulation

Each app's Welcome screen can drive automated user journeys via a probabilistic state machine, producing varied, lifelike sessions (browsing, cart add/remove, wishlist, guest vs. member checkout, multiple payment methods, and cart abandonment). The Android app additionally offers persona presets (Variant A / Variant B / Control) that bias the simulator. Details live in each app's own README.

## Instrumenting an app

The bitdrift Capture SDK integration shown across these apps is documented platform-neutrally in the repository's **[instrumentation-guide/](../instrumentation-guide/)** — a step-by-step guide that works for any app, plus a matching cleanup guide. Use that as the reference for what each SDK feature unlocks and how to wire it up.

## Where to look

Build and run instructions live in each app's own folder. Start with the README in the app you're interested in:

- [android/sdk/](android/sdk/) — Android app
- [reactnative/sdk/](reactnative/sdk/) — React Native app (Android + iOS)
- [kotlin-multiplatform/sdk/](kotlin-multiplatform/sdk/) — Kotlin Multiplatform app (Android + iOS)
- [backend/](backend/) — FastAPI server, API endpoints, and chaos mode
