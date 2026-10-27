# bitdrift Shop: status and what is left

Part of the [bitdrift Shop README](../README.md). This replaces the original multi-phase plan (still in git history as
`docs/PLAN.md` at commit `22eaf70`). The work it described is done; this file keeps what is still useful: the decisions,
the deviations from the plan, the environment notes, and what remains.

## Where things stand

One shared spec and thin per-language apps: Android, iOS, React Native and Flutter (all fully supported), with the Kotlin Multiplatform app deferred.
No-SDK "clean" variants were dropped, and the apps came before backend work.

| Phase | Done | Documented in |
|---|---|---|
| 0 Stabilize | Android Confirmation bug fixed, clean variants deleted, READMEs fixed, Kotlin pinned to 2.2.10 | app READMEs |
| 0b CLI test harness | `./test.sh <app\|all> <unit\|smoke>`, launch-argument autorun and record mode in every app | [TESTING.md](TESTING.md) |
| 1 SDK catch-up | Android and iOS on capture 0.26.0 (iOS off the deprecated session APIs), RN 0.15.0; Flutter stays on the newest tag (native 0.24.1) | app READMEs |
| 2 Shared spec and constants | `spec/` plus `tools/codegen` generating Kotlin, Swift, TS and Dart constants | [SPEC.md](SPEC.md), [../spec/DECISIONS.md](../spec/DECISIONS.md) |
| 3 Spec check | `tools/conformance` validates recorded streams against the spec | [TESTING.md](TESTING.md) |
| 4 Shared journey engine | `spec/journey.yaml` plus one interpreter per app; same seed gives the same journey everywhere | [../tools/journey/README.md](../tools/journey/README.md) |
| 5 Workflows, dashboards, scripts | templated workflows and dashboards, `tools/bd-deploy.sh`, shared script helpers | [../workflows/README.md](../workflows/README.md), [../dashboards/README.md](../dashboards/README.md) |
| 6 Realism (Android and iOS) | realistic crashes with precursor logs, session mode, correlation fields, Commands, `logCritical`, `cart_json`, symbolication | [REALISM.md](REALISM.md) |

Also shared by every app: emulator and simulator start/stop in [`scripts/device/`](../README.md#emulators-and-simulators-shared-by-every-app).

## Deviations from the original plan

- **The cross-app diff compares journey records only:** the events and spans `journey.yaml` emits, with parent span names. It ignores `volatile_fields`
  (the backend samples product, order and checkout ids randomly), `platform_specific` fields and `adapter_added` fields (such as `cart_json`). Screen views
  and platform-only logs are not diffed (Flutter logs fewer screen views). Each recording is also checked against the reference engine, so drift shows up per app.
- **Kept per platform:** run loops (N, infinite, A/B interleaved), flag exposure, the physical mechanism of each fault and crash, record mode, and iOS's fixed
  *simplified journey* mode. RN `startNewSession` is a no-op. Flutter's spans are flat (the alpha SDK has no parent or canceled), its crash loop is foreground-only,
  and it has no fault toggles.
- **Record mode is not seeded and is not a headless adapter.** Android and iOS record through a logging facade into JSONL on the device, driven by launch
  arguments. RN and Flutter cannot take launch arguments or write files without native code, so in debug builds they ask a local collector
  (`tools/conformance/collector.py`, port 5599) for their config and POST their records back. The exit marker is the event `sim_autorun_complete`.
- **Spec `source:` citations are `file:line` and drift when code moves.** `validate.py --strict` checks them and `validate.py --fix-refs` repairs them.
- **Crash catalog and fault timings** other than probability and force-after are still per-app code; `spec/crashes.yaml` documents them.
- **RN's generated constants file is `src/generated/specConstants.ts`**, not `spec.ts`, because Jest treated `spec.ts` as a test.
- **iOS has no XCTest target.** Its unit tier compiles for the simulator, replays the golden journey traces with a host `swiftc` build, and runs the host realism checks.
- **iOS crash symbolication is not verified.** The simulator cannot produce symbolicated crash reports, so only the Android crashes were checked as symbolicated.

## Decisions

Resolved: `BITDRIFT_SDK_KEY` on every app, `app_variant=sdk-demo`, unretried payment failure ends `journey` and `checkout` spans as failure, the crash loop fires at a
random back-half journey point everywhere (`crash_journey_point`, confirmation fallback), the journey emits the add-to-cart, wishlist, remove, checkout-started and
payment-completed events, payment retry picks among the other three methods, and the A/B persona split is interleaved on every app. Details and evidence:
[../spec/DECISIONS.md](../spec/DECISIONS.md).

**Still open:** OPEN-6, a cardinality demo (recommendation: an Advanced-screen toggle, off by default).

## What is left

- **Verify iOS crash symbolication on a physical device** (dSYM upload via `ios/scripts/release-build.sh --device`).
- **Create the two workflows missing from the live account** (declined for now).
- **A revenue-by-category workflow** using JSON paths on `cart_json` (the field ships; no workflow uses it yet).
- **Kotlin Multiplatform:** still on SDK 0.24.2 and deferred until the four apps are settled.
- **Realism on RN and Flutter**, where their SDKs support it.

Deferred, not scheduled:

- Planted incident scenarios with answer keys and agent evals.
- Multiple real app versions and a varied device fleet.
- WebView screens and user-friction signals (rage taps, real jank).
- Backend work: `/api/sim/config`, per-request fault headers, trace linkage to the backend's OTel, merging the `backend-ddtrace` fork.
- Folding `bitdrift-shop-opentelemetry` into the main apps.

## Changing the journey

Edit `spec/journey.yaml` or `spec/personas.yaml`, run `tools/codegen/generate.sh`, then `./test.sh all unit` (see [../tools/journey/README.md](../tools/journey/README.md)).

## Environment notes

- Never print or commit keys: `android/.local.properties*`, `ios/.local.xcconfig`, `reactnative/.env` and `flutter/.env` are gitignored and hold the shared SDK key.
- `tools/codegen/.venv` is created on first use (PyYAML), and `test.sh` uses it.
- RN iOS needs `LANG` and `LC_ALL` set to `en_US.UTF-8` for `pod install` (a Ruby 4 locale bug). If Gradle times out downloading 8.10.2 for RN Android, `curl` the zip into `~/.gradle/wrapper/dists/gradle-8.10.2-all/<hash>/`.
- The Flutter iOS build can need `flutter clean` after an SDK upgrade (undefined Flutter symbols at link). On Android Flutter is built `--release` by its start script; the harness gate is the `BDSHOP_HARNESS` define.
- With two simulators booted, `xcrun simctl ... booted` is ambiguous; pass the UDID. Reinstalling an iOS app keeps its UserDefaults, so uninstall to clear a crash loop left armed by a manual run (`./test.sh ios smoke` does this itself).
- `bd tail --output jsonl android|ios` works for watching a run; session ids are masked in tail output.
