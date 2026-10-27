# bitdrift Shop: Shared Spec, Variant Cleanup, and Agent-Realism Plan

> **Status 2026-10-26: Phases 0, 0b, 1, 2, 3 and 4 are done and committed. Start from §8 (handoff) before reading further; it records what changed from this plan. Next up: Phase 5.**

_Date: 2026-10-26 · Repo: `sa-public/bitdrift-shop` (branch `slerner/bit-9050-otel-demo-fixes`) · SDK reference: `capture-sdk` origin/main @ `135ec9e8` (v0.26.0)_

## 0. Where things stand (review findings)

### Variants and SDK versions

| Variant | Lines (approx) | SDK pinned | Latest available | State |
|---|---|---|---|---|
| android | 5.8k Kotlin | capture 0.25.1 (uncommitted bump) | **0.26.0** | Reference implementation |
| ios | 6.0k Swift | capture-ios 0.24.2 (exactVersion) | **0.26.0** | Port of Android; still uses deprecated `sessionStrategy:` / `fieldProviders:` |
| reactnative | 7.6k TS | @bitdrift/react-native ^0.14.0 | **0.15.0** | Probability table matches Android; spans are paired logs; missing 8 crash types and sub-phase spans |
| flutter | 5.4k Dart | capture_flutter `flutter-prototype-0.0.4` (native 0.24.1) | same | Heavily reduced sim; **different event names** (`journey_start`, `order_completed`, …) and screen names (`Card`, `Diagnostics`) |
| wip-kotlin-multiplatform | 6k | 0.24.2 | 0.26.0 | iOS side sends **no sim telemetry** (logging actuals are `println`); flags set to variant name; field keys differ (`method` vs `payment_method`) |
| ios-clean / android-clean | — | none | — | Both deleted in the working tree (uncommitted). They were hand-maintained copies with no generator, and had already drifted (~1,250 diff lines vs ios) |
| bitdrift-shop-opentelemetry | ~3.5k | local AAR | — | Hand-diverged copy of the Android and iOS apps (SimulationManager differs by 623 lines) pointing at the OTel Demo backend |

### Bugs and hygiene issues found

1. **Android sim control-flow bug.** In `android/.../SimulationManager.kt:1018-1101` the retry `if` closes after `return`, so **Step 7 (Confirmation) sits inside `if (willPaymentFail)`**. Successful payments never log `confirmation_reached` and leave the `checkout` and `journey` spans open. Failed payments that skip the retry are recorded as successes. Every Android funnel and conversion workflow is currently wrong. Fix this first.
2. **Workflow numbers mean different things per platform.** `bd-shop-13/14/15` are foreground-session workflows on Android but hang, force-quit and crash-by-screen workflows on iOS. Scripts and READMEs cite them inconsistently.
3. **Dashboards hard-code workflow IDs from one account** (`RLXS`, `0pTX`, …). Only one dashboard uses a placeholder.
4. **The same config key has different names:** `BITDRIFT_SDK_KEY` (Android) vs `BITDRIFT_API_KEY` (iOS); `app_variant` is `sdk-demo` vs `ios-sdk-demo`; ANR prefs are `anr_a` vs `app_hang`.
5. **README drift:** "16-screen" vs "19 screens"; links to `kotlin-multiplatform/` (the folder is `wip-…`); wrong category list; still lists ios-clean.
6. `android/.local.properties.prod` holds a plaintext SDK key. It is untracked, but confirm it's in `.gitignore`.
7. Android `libs.versions.toml` says Kotlin 2.0.21 while `build.gradle.kts` pins 2.2.10.
8. The backend README category list is wrong, and `misc-demos/backend-ddtrace/shopping_server.py` is a 27-line-diff fork of the backend.

### How much is duplicated

All of the following are hand-copied as string and number literals in Android, iOS, RN, KMP and (partially) Flutter:
- the 19 screen names and routes;
- about 45 event names and about 60 field keys;
- about 25 span names;
- 8 feature flags with per-persona values;
- about 20 per-persona probabilities;
- 10 search terms, the entity pool, and the ANR, force-quit and crash timings;
- the API paths and path templates;
- the fake vendor-SDK URLs;
- the metrics-demo waveforms.

The crash catalog is 28 entries on Android and 35 on iOS, with 16 shared. The workflows and dashboards are also duplicated per platform with small diffs.

---

## 1. Goal: one spec, thin per-language variants

**Principle:** anything that is *data* (names, probabilities, flows, timings, catalog) lives once, in `spec/`. Each language variant contains only what's genuinely platform-specific: UI, navigation, how a crash is physically triggered, and SDK calls.

### Supported matrix (decided)
- **Fully supported:** android, ios, reactnative, flutter. All four consume `spec/` and must pass conformance.
- **Best effort:** wip-kotlin-multiplatform. It consumes the generated Kotlin constants (cheap, because the Kotlin codegen output is reused) and gets SDK bumps when convenient. It is excluded from the conformance gate. Fixing the no-op iOS logging actuals is a nice-to-have.

### Why not KMP or a shared runtime core as *the base*?
- **KMP** reaches only Android and iOS, not RN or Flutter. Its iOS logging is already a no-op, and the UI still has to be written twice.
- **A shared Rust/JS core** would make the demo stop looking like a normal customer app. Customers need to see idiomatic Kotlin, Swift, TS and Dart SDK usage, so keep the code native and share the data.

### Proposed layout

```
bitdrift-shop/
  spec/                          # SINGLE SOURCE OF TRUTH
    screens.yaml                 # id, display name, route template, screen-load span name
    telemetry.yaml               # events (name, level, required/optional fields), field keys, global fields, span tree
    flags.yaml                   # feature flags + per-persona values
    personas.yaml                # Control / Variant A / Variant B probability tables
    journey.yaml                 # journey graph: steps, branches (prob refs), spans to open/close, events to emit
    crashes.yaml                 # logical crash ids → per-platform impl key, category, fg/bg, expected bitdrift issue type
    faults.yaml                  # ANR/hang, force-quit, crash-loop, slow-mode knobs + timings + persisted keys
    api.yaml                     # endpoints, path templates, fake vendor URLs (shared with backend)
    workflows/                   # templated workflow JSON (one file, platform-parameterized)
    dashboards/                  # templated dashboards using __WF_<slug>__ placeholders
  tools/
    codegen/                     # spec → Kotlin/Swift/TS/Dart constants + bundled journey JSON
    conformance/                 # golden event-stream checker
    bd-deploy.sh                 # deploy workflows+dashboards for a given app_id, substitutes IDs
  scripts/lib/                   # shared shell helpers (watchdog core, state check, foreground cycle)
  android/ ios/ reactnative/ flutter/   # thin variants
  backend/
```

### Two layers of sharing

**Layer A: generated constants** (low risk; do this first)
- `tools/codegen` (a small Python script, since the backend already uses Python) reads `spec/*.yaml` and writes:
  - Kotlin: `Telemetry.kt` (`object Events { const val CHECKOUT_STARTED = "checkout_started" }`, `object Fields`, `object Spans`), `Screens.kt` (enum with route and name), `Flags.kt`, `Personas.kt`.
  - Swift: equivalent `enum`s with `static let`.
  - TS and Dart: the same.
- Generated files are checked in under a `generated/` folder in each variant and carry a "DO NOT EDIT" header. A CI check runs codegen and fails on any diff.
- Typed event helpers can come later (`Events.paymentFailed(method:, session:, variant:)`). They prevent the field-key drift we see today (`method` vs `payment_method`).

**Layer B: data-driven journey engine** (removes most of the sync work)
- `journey.yaml` describes the state machine as a graph of steps. Each step names its screen, API call, span open/close, events, and outgoing branches whose probabilities are looked up from `personas.yaml`. Fault injection points (ANR target screen, force-quit screen, crash journey point) are also declared there.
- Codegen bundles this as `journey.json` into each app (Android asset, iOS bundle resource, RN JSON import, Flutter asset).
- Each platform implements a **small interpreter** (about 300 lines) plus a **platform adapter** with `navigate(screen)`, `callApi(endpoint)`, `log(event)`, `startSpan`/`endSpan`, `triggerCrash(id)` and `persist(key)`. This replaces Android's 1,150-line and iOS's 1,377-line `SimulationManager`.
- **Seeded RNG:** every journey takes a seed, logged as field `sim_seed`. That makes runs reproducible across platforms and is what the conformance tests rely on.
- **Deferred to the backend phase (decision: apps first):** the backend serves `GET /api/sim/config`, returning the same JSON, so probabilities can be tuned live. The first cut uses only the bundled JSON.

### Conformance testing (makes "no syncing" true)
- Each variant gets a headless "record mode", where the adapter's log, span and navigation calls write to an in-memory recorder instead of bitdrift. A unit test runs N seeded journeys per persona and dumps the event stream as JSONL.
- `tools/conformance` validates every event against `telemetry.yaml`: known name, required fields present, legal values, spans closed. Once the journey engine exists (Phase 4), it also diffs **Android vs iOS vs RN vs Flutter** streams for the same seed. They should be identical apart from fields marked `platform_specific` and Flutter's `optional_on` items. (Seeding is not retrofitted into the old hand-written simulators, since Phase 4 deletes them.)
- This would have caught the Confirmation bug, Flutter's renamed events, and KMP's flag values.

### "Clean" (no-SDK) variants: dropped
Decision: no clean variants. android-clean and ios-clean stay deleted. Remove their references from the root README, `instrumentation-guide/`, and any scripts. No flavor or generator is needed.

### Workflows, dashboards and scripts
- Use **one templated workflow per concept**, parameterized by `{{platform}}` and `{{app_id}}`, and renumber so each slug is globally unique (for example `bd-shop-fg-session-count`). Drop the number collisions.
- Dashboards use `__WF_<slug>__` placeholders only. `tools/bd-deploy.sh <app_id>` creates or updates the workflows, captures their IDs and substitutes them. This replaces `ios/scripts/deploy-workflows.sh` and the Android README's manual steps.
- Shared shell logic (state check, watchdog loop, foreground cycle) moves to `scripts/lib/`, with per-platform drivers for adb and simctl. Persisted key names come from `faults.yaml`.

### Folding in bitdrift-shop-opentelemetry
Once the adapter layer exists, the OTel demo becomes a **backend flavor** (`ApiClient` target: FastAPI shop or OTel-demo Telescope Store) plus the `otelExport` source set, not a separate copy. Deferred (see §3 "Later").

---

## 2. SDK catch-up (latest artifacts)

| Item | Action |
|---|---|
| Android → **0.26.0** | Bump the Maven dependency and the Gradle plugin to 0.26.0. The default build must use Maven Central, with `BITDRIFT_USE_LOCAL_AAR` unset and the OTel export toggle off (it defaults on only when a local AAR is used). Keep the local-AAR and OTel wiring in `build.gradle.kts` intact but don't touch it. The OTel branch `slerner/otel-span-export-shared-core` is 52 commits behind main and lacks Commands. Rebasing it is **not** part of this plan; OTel work is deferred. |
| iOS → **0.26.0** | Move from `sessionStrategy: .fixed()` + `fieldProviders:` (both deprecated) to `SessionConfiguration` + `initialFields`. Keep today's behaviour: a new session per launch, with the sim still calling `startNewSession()` per journey. Session shape changes only in Phase 6. |
| RN → **0.15.0** | Check the changelog in `capture-es` for a span API. If one exists, retire the paired-log span shim. |
| Flutter | Stays on `flutter-prototype-0.0.4` (native 0.24.1) until a newer tag ships. It has no feature-flag, TTI or Commands API, so `telemetry.yaml` marks those items `optional_on: [flutter]`, and Flutter keeps the `ff_*` field fallback. It must still use the spec's event and screen names: rename `journey_start`, `order_completed`, `Card`, `Diagnostics` and so on. It also gets the full journey graph back (featured, cart edits, abandon, dropout, payment failure and retry). |
| KMP | Best effort: bump to 0.26.0 and adopt generated constants when touched. |
| New APIs not yet exercised anywhere | `logCritical`, `SessionConfiguration(inactivityTimeout, onSessionIdChanged)`, `getPreviousRunInfo()` on Android (iOS already uses it), `IssueCallbackConfiguration`, `getSdkStatus()`, `clearEntityId`, Commands, WebView instrumentation, JSON-path workflow metrics, distributed-tracing headers (`traceparent` + `x-bitdrift-initiated-trace`), the Pre-Init buffer, Compose `captureIgnore`, `RetrofitUrlPathProvider`/`HttpUrlPath` templates. |

---

## 3. Realism for session and crash agents (simple version, now)

Scope: **Android and iOS** in this plan. RN and Flutter pick these up later through the shared spec where their SDKs support them.

Today's crashes are *announced*: they come from a crash catalog, are preceded by an `about_to_crash: …` log, and (on Android) always fire right after Confirmation. Nothing in the session explains *why* a crash happened. The near-term goal is to make sessions look more like a real app's, using only app-side changes.

1. **Crashes in realistic code.** Add a few crashes inside real-looking app classes (for example `CartPricing.applyCoupon` on an empty cart, or `PromoBannerParser` on a bad payload), so stack traces point at plausible app code. Before each one, log a normal precursor (a handled `logError` with the exception, a retry, a slow span) instead of `about_to_crash`. Keep the existing crash catalog on the Advanced screen for SDK demos.
2. **Realistic sessions.** Use `SessionConfiguration(inactivityTimeout = …)` so one session spans several journeys and background/foreground transitions, as a real user's does. **Caution:** existing funnel, sankey and A/B workflows may assume one journey per session. Make this a toggle in the Advanced screen (`session_mode`: `per_journey` | `realistic`) and keep `per_journey` as the default until every workflow that depends on it has been checked with `bd workflow`. Log `previousRunInfo` at launch on both platforms, so the session after a crash shows what happened last time.
3. **Correlation fields.** Add `journey_id` and `step` to every journey event.
4. **New 0.26 features:**
   - **Commands:** register a couple of handlers, such as `dump_cart_state` (returns cart JSON) and `flip_flag`, so an agent or SE can pull state from a live device. Copy the pattern from the SDK's gradle-test-app `SampleCommands.kt` and the iOS `hello_world/Commands`.
   - **`logCritical`** for a business-critical failure (for example "order lost").
   - **`cart_json` field** on `checkout_started`, to show JSON-path workflow metrics (revenue by category).
5. **Symbolication:** make release builds upload the R8 mapping and dSYMs, so crash stack traces are readable. (Verified on Android; the iOS dSYM upload exists but cannot be verified on a simulator.)

### Later (deferred, not in this plan)
- Planted incident scenarios with answer keys and agent evals (including the public vs. private question)
- Multiple real app versions and a varied device fleet
- WebView (help page / 3-D Secure), user-friction signals (rage taps, real jank)
- Backend work: `/api/sim/config`, per-request fault headers, trace linkage to the backend's OTel, merging the `backend-ddtrace` fork
- Folding `bitdrift-shop-opentelemetry` into the main apps

---

## 4. Phases

| Phase | Scope | Done when (`./test.sh <apps touched> smoke` passes **and** the live check in bitdrift passes; all from the CLI, no IDE) |
|---|---|---|
| **0. Stabilize** (about 1 day) | **Ask the user first** how to handle the current branch (`slerner/bit-9050-otel-demo-fixes`) and the uncommitted work (whether to commit it there or branch fresh from `main`). Never discard uncommitted changes without asking. Then: fix the Android Confirmation bug; commit the clean-dir deletions and remove clean references from the READMEs and the instrumentation guide; commit the 0.25.1 bump, `PersistentFeatureFlags` and `SupportMode`; README fixes; gitignore check for `.local.properties.prod`; Kotlin version mismatch | Clean `git status`. **Offline check:** unit-test or log-trace the payment branch for success, fail→retry and fail→no-retry. **Live check:** an Android sim session in `bd timeline` shows `confirmation_reached` and closed `checkout`/`journey` spans on successful payments, and a funnel workflow shows confirmations again |
| **0b. CLI test harness** | `test.sh` with the `unit` and `smoke` tiers (§7) for android and ios first, then RN and Flutter; launch-argument autorun, record file and exit marker in each app; replace the placeholder `ExampleUnitTest`/`ExampleInstrumentedTest` | `./test.sh all smoke` passes with no IDE open. **Live check:** the same run shows in `bd tail` |
| **1. SDK catch-up** | Android and iOS to 0.26.0 (iOS off deprecated APIs), RN to 0.15.0, KMP to 0.26.0 (best effort) | Apps build and run on 0.26.0. **Live check:** `bd tail` shows each app's logs arriving with SDK version 0.26.0, and iOS session behaviour is unchanged (a new session per launch and per journey) with no deprecated APIs left |
| **2. Shared spec + generated constants** | Write `spec/` from the Android values (resolving drift in `spec/DECISIONS.md`, including config-key names `BITDRIFT_SDK_KEY`/`BITDRIFT_API_KEY` and `app_variant` values); generate Kotlin/Swift/TS/Dart constants; replace string literals in android, ios, reactnative and flutter (Flutter renames its events and screens to match) | No event/field/span/screen literals outside `generated/`. **Live check:** `bd tail` on each app (including Flutter) shows only spec names; existing `bd-shop` workflows still match. Any rename that a workflow matches on must update that workflow JSON in the same phase |
| **3. Spec check** | Record mode in each app + `tools/conformance` validating recorded streams against `telemetry.yaml` (known names, required fields, spans closed); no seeding yet | Every app's recorded run passes validation. **Live check:** one run per app in `bd timeline` shows the same names and fields |
| **4. Shared journey engine** | `journey.yaml` + seeded RNG + a small interpreter per language; delete the hand-written simulators; extend `tools/conformance` to diff same-seed streams across apps | Same-seed streams match across all four apps, and one YAML change alters behaviour everywhere. **Live check:** after a probability change, the per-app funnel/sankey workflows shift as expected |
| **5. Workflows/dashboards/scripts** | Templated workflows with unique names, one deploy script, shared script helpers | A fresh account is deployable with one command per app. Existing live `bd-shop` workflows are listed first and updated or replaced only after confirmation, never duplicated. **Live check:** `bd workflow list` / `bd dashboard` show one set per app, with charts populating |
| **6. Realism (simple)** | §3 items 1–5 (Android + iOS) | **Live check:** on Android, `bd issue` shows the new crashes symbolicated, with precursor logs in the session (iOS: the crash fires in the app code, but symbolication is not a criterion, because the simulator cannot produce symbolicated crash reports; the dSYM upload path stays in `ios/scripts/release-build.sh` for device builds); `bd command` runs `dump_cart_state` and `flip_flag` successfully on Android and iOS |

## 5. Decisions
1. No-SDK clean variants: **dropped.**
2. **Flutter fully supported; KMP best effort.**
3. **Apps first.** Backend work comes later.
4. **Scenarios and answer keys deferred.**

---

## 6. Execution guidance (model and process)

Run **one phase per session**, starting each session with this plan file. Work entirely from the terminal (see §7): never open or ask the user to open Android Studio or Xcode. End each phase with `./test.sh <apps touched> smoke` passing (`unit` too, once it exists), and **commit after each phase** so a bad run is easy to revert.

| Phase | Model | Notes |
|---|---|---|
| 0. Stabilize | Sonnet | The Confirmation fix is a brace move (around `SimulationManager.kt:1018-1101`; line numbers may shift); the rest is housekeeping. |
| 0b. CLI test harness | Sonnet | Build on the existing `scripts/*-1..5` scripts. If a device step fails, read the device logs (`adb logcat`, `xcrun simctl spawn booted log stream`) rather than guessing. |
| 1. SDK catch-up | Sonnet | Read the SDK source in `/Users/slerner/code/repos/capture-sdk` (origin/main, v0.26.0) for exact APIs; don't rely on memory. iOS: move from `sessionStrategy:`/`fieldProviders:` to `SessionConfiguration` + `initialFields`. |
| 2a. Write `spec/` (resolve the drift) | **Opus** | Every mismatch (field names, flag values, crash lists, Flutter's renamed events) needs a decision about which version wins. Record each decision in `spec/DECISIONS.md`. |
| 2b. Codegen + replace literals | Sonnet | Repetitive swap of string literals for generated constants across four apps. |
| 3. Cross-platform check | **Opus** (rules) → Sonnet (wiring) | Opus defines what counts as "the same" and what Flutter is exempt from; Sonnet wires up the record mode in each app. |
| 4. Journey engine | **Opus** (YAML schema + Android reference interpreter) → Sonnet (iOS, RN, Flutter ports) | The schema is the riskiest design choice in the plan. Port only after the Android interpreter passes the Phase 3 spec check. |
| 5. Workflows/dashboards/scripts | Sonnet | Mostly mechanical (templating, `__WF_<slug>__` placeholders, `bd-deploy.sh`, `scripts/lib/`). One checkpoint: write the old→new mapping table (step 1 under §8 "Phase 5 starting point") and **stop for the user's review** (optionally an Opus review) before deploying, replacing or deleting anything live. |
| 6. Realism (simple) | Sonnet | For Commands, copy the pattern from `platform/jvm/gradle-test-app/.../init/SampleCommands.kt` and `examples/swift/hello_world/Commands/`. Have Opus review the realistic crash sites. |

**Checking telemetry in bitdrift (both paths work, verified 2026-10-26):** the bitdrift MCP connector is connected (tenant `InfrArc`), and the `bd` CLI 0.2.44 is authenticated. Every phase that touches telemetry ends with a live check, not just a build:
- `bd tail` streams logs from a running simulator or emulator, to confirm event, field and span names match `spec/` (Phases 1–4, 6).
- `bd timeline` / MCP `bd_sessions_logs` / `bd_sessions_spans` inspect a finished session, to confirm journey spans close and `confirmation_reached` fires (Phase 0 bug fix, Phase 4).
- `bd issue` / MCP `bd_issues_list` confirm realistic crashes arrive symbolicated, with the expected precursor logs (Phase 6, Android; not checked on the iOS simulator, which cannot produce symbolicated crash reports).
- `bd command` invokes the new Commands (`dump_cart_state`, `flip_flag`) on a live device (Phase 6).
- `bd workflow` / `bd dashboard` deploy and verify the templated workflows (Phase 5). The account already has live `bd-shop` workflows, so the deploy script must update or replace them, not create duplicates. List them first and confirm before deleting any.

---

## 7. Testing without Android Studio or Xcode (command line only)

**Rule for every phase:** build, install, run and verify everything from the terminal. Never ask the user to open Android Studio or Xcode. Xcode stays installed (verified 2026-10-26: Xcode 27.1 at `/Applications/Xcode.app`, iOS 26.2–27.0 simulator runtimes). It provides `xcodebuild`, `xcrun simctl` and the simulators, and is a requirement for the iOS, RN-iOS and Flutter-iOS tiers, but the Xcode app is never opened. Android needs only the SDK command-line tools (`sdkmanager`, `avdmanager`, `emulator`, `adb`) and JDK 21; it currently uses the Studio-managed SDK at `~/Library/Android/sdk`, which works without the IDE.

The existing per-app scripts are already CLI-based (`android-1..5`, `ios-1..5` via xcodebuild/simctl, and the RN and Flutter equivalents). The plan builds on them instead of replacing them.

### One entry point
`bitdrift-shop/test.sh <app|all> <tier>`, where `app` is `android`, `ios`, `rn-android`, `rn-ios`, `flutter-android`, `flutter-ios` or `kmp` (best effort), and `tier` is `unit`, `smoke` or `live`. It exits non-zero on failure and prints a one-line summary per app.

| Tier | Needs | What runs | Tools |
|---|---|---|---|
| **unit** | No emulator or simulator | Codegen diff check; spec validation of `spec/*.yaml`; journey interpreter unit tests with seeded runs; recorded streams checked by `tools/conformance` | Android `./gradlew testDebugUnitTest` (JVM); iOS: the interpreter and generated constants live in a local **Swift package**, so `swift test` runs on the Mac host with no simulator; RN `npx jest`; Flutter `flutter test`; `python3 tools/conformance` |
| **smoke** | Headless emulator / booted simulator | Build, install and launch, then **auto-run N seeded journeys from launch arguments**; pull the recorded JSONL off the device and run `tools/conformance` on it; check that the app didn't crash unexpectedly | Android: `emulator -no-window -no-audio`, `./gradlew installDebug`, `adb shell am start … --ei sim_runs 5 --el sim_seed 42 --es persona variant_a`, `adb pull` / `adb logcat`. iOS: `xcrun simctl boot`, `xcodebuild -scheme … -destination 'platform=iOS Simulator,…' build`, `xcrun simctl install/launch booted <bundle> -simRuns 5 -simSeed 42 -persona variant_a`, `xcrun simctl get_app_container` to read the file |
| **live** | Smoke tier + bitdrift | Same seeded run, then confirm in bitdrift that logs, spans, crashes and commands arrived as expected | `bd tail`, `bd timeline`, `bd issue`, `bd command`, or the bitdrift MCP tools |

### Hooks the apps need (added in Phase 0b)
- **Launch-argument autorun.** Each app accepts `sim_runs`, `sim_seed`, `persona` and `record_file` from launch arguments (Android intent extras, iOS launch arguments, RN via the native launch props, Flutter via `--dart-define` or intent/launch args), and starts the simulator without any taps. Until Phase 4, `sim_seed` is accepted and logged but the old simulators stay unseeded (no retrofitting); exact same-seed runs begin with the shared engine. iOS already reads some launch-argument flags; extend that, and mirror it on the other apps.
- **Record file.** In record mode the adapter also appends each event to a JSONL file in the app's sandbox, which the smoke tier pulls off the device.
- **Exit marker.** The app logs `sim_autorun_complete` (and writes it to the record file) so scripts know when to stop waiting, with a timeout as a fallback.
- **Crash tests.** Crash flows are smoke-tested by launching with `crash=<id>` and then checking that the next launch's `previousRunInfo` / `bd issue` shows the crash. Re-use the existing `watchdog.sh` relaunch logic.

### Optional UI flows
For flows that need real taps (the Advanced screen toggles, the Commands UI), use **Maestro** (`brew install maestro`; it is not installed yet). It drives Android emulators and iOS simulators from YAML flows in `tests/maestro/` with no IDE, which is the same approach the capture-sdk repo uses (`tools/maestro/`). Keep this optional; the launch-argument hooks cover the core checks.

### Later
GitHub Actions on macOS runners running `./test.sh all unit` on every PR, and `smoke` nightly.

---

## 8. Status and handoff (2026-10-26)

**Repo/branch:** `/Users/slerner/code/sa-public` (git root), app folder `bitdrift-shop/`, branch `slerner/bit-9050-otel-demo-fixes` (not pushed, no PR yet). Commits from `8c873da` (Phase 0) to `b93fab3` (Phase 3 Flutter); Phase 4 is `f398c70` (spec + Android + tooling), `58fab1a` (iOS/RN/Flutter ports) and `2609b70` (cruft removal + docs). Unrelated uncommitted changes exist outside `bitdrift-shop/` (`misc-demos/bitdrift-shop-opentelemetry` deletions, an untracked `bitdrift-shop-opentelemetry/`, `bitdrift-statsig-integration-ideas.md`); leave them alone.

### Done

| Phase | State | Notes |
|---|---|---|
| 0 Stabilize | done | Android Confirmation bug fixed; clean variants deleted; READMEs fixed; Kotlin pinned to 2.2.10. KMP deferred. |
| 0b CLI test harness | done | `./test.sh <app\|all> <unit\|smoke>`; apps: android, ios, rn-android, rn-ios, flutter-android, flutter-ios. `all unit` ~15s, `all smoke` ~5 min, all PASS. |
| 1 SDK catch-up | done | Android/iOS capture 0.26.0 (iOS off deprecated session APIs: `SessionConfiguration()` + `initialFields`), RN 0.15.0, Flutter stays `flutter-prototype-0.0.4` (native 0.24.1, still newest tag; Flutter SDK upgraded to 3.47.8). **KMP is still 0.24.2: deferred by the user until the four apps are settled.** |
| 2 Spec + constants | done | `spec/*.yaml` + `DECISIONS.md` + `validate.py`; `tools/codegen` generates Kotlin/Swift/TS/Dart constants (`generate.sh`, `check.sh`); every event/field/span/flag/screen literal in the four apps replaced. Flutter renamed to spec names (D-EVT-F1..F13). |
| 3 Spec check | done | `tools/conformance/conformance.py` validates recorded streams against the spec; `collector.py` for RN/Flutter. Live check done for Android only (bitdrift received the same run); the others use the same SDK calls. |
| 4 Journey engine | done | `spec/journey.yaml` + `tools/journey/` (`compile.py` validates/normalizes, `engine.py` reference interpreter, `golden.json` per-seed traces; see `tools/journey/README.md`). One interpreter per app (`JourneyEngine.kt`, `JourneyEngine.swift`, `src/sim/journeyEngine.ts`, `lib/sim/journey_engine.dart`) behind a platform adapter; hand-written journeys deleted. Seeded mulberry32 (`journey_seed = sim_seed*1000003 + run`), `sim_seed` on `journey_started`. Unit tier replays the golden traces on every app; smoke checks each recording against the reference engine and `--diff`s the apps: `./test.sh all smoke` PASS, all six recordings identical (124 journey records, control/seed 42). Live check (Android, `MMiD` Checkout Funnel, control seed 1001, 20 runs): baseline 20/20/20/20/18 exactly as predicted; with `cart_abandon.control` 0.05→0.8 the same seed gave Checkout/Payment/Confirmation +3/+3/+3 as predicted (reverted afterwards). |

Also done at the user's request: RN and Flutter restyled to match native Android (white theme, slate primary `#4E5F8D`, ScreenContainer layout); unretried payment failure now ends `journey`/`checkout` spans as `failure` with `reason=payment_failed` on all four apps (spec OPEN-4); iOS `BITDRIFT_SDK_KEY` (fallback to old `BITDRIFT_API_KEY`) and `app_variant=sdk-demo` (OPEN-1/OPEN-2).

### Deviations from this plan (read these)
- **Phase 4 cross-app check compares *journey records* only** (the events and spans journey.yaml emits, with parent span names), ignoring `volatile_fields` (product_id, order_id, checkout_session: the backend samples randomly) and `platform_specific` fields. Screen views and platform-only logs are not diffed (Flutter logs fewer screen views: 38 vs 44 per 5 runs). Each recording is also checked against `engine.py`'s prediction, so a drift shows up per app, not only as a pairwise diff.
- **Phase 4 kept per platform:** run loops (N, infinite, A/B interleaved `i % 3`, cardinality), flag exposure, each fault's and crash's physical mechanism, record mode, and iOS's fixed *simplified journey* mode (still hand-written; it has its own small fault roll mirroring faults.yaml). RN `startNewSession` is a no-op (D-SES-1). Flutter: spans are flat in bitdrift (alpha `startSpan` has no parent/canceled/end fields; the recorder keeps the logical values), crash loop is foreground-only, no fault toggles. The engine's API calls are in addition to the screens' own on-load fetches on every app (as before).
- **`validate.py --fix-refs`** now exists (re-points stale refs to the line holding the name or its generated constant); journey-owned names cite `J:journey.yaml:N`.
- **Phase 3 "record mode" is not seeded and is not a headless adapter.** Android/iOS record via a logging facade (`RecordingLogger`/`RecordedSpan`, `ScreenLogger` hooks) into JSONL on the device, driven by launch arguments `sim_runs/sim_seed/persona/record_file`. RN/Flutter can't take launch args or write files without native code, so in debug builds (Flutter: or `--dart-define=BDSHOP_HARNESS=true`) they ask a local collector (`tools/conformance/collector.py`, port 5599, started by `test.sh`) for `/config` and POST records to `/record`. The exit marker is the spec event `sim_autorun_complete` {total_runs, sim_seed, persona}. (Since Phase 4 `sim_seed` seeds the journey engine.)
- **Conformance rules were derived from the spec's existing semantics** (`platforms`, `optional_on`, `missing_on`, `drift_*`, `long_lived`), not a separate Opus design pass. "Same across platforms" diffing of same-seed streams does not exist yet (needs Phase 4).
- **Spec `source:` citations are file:line and drift when code moves.** `validate.py --strict` checks them; run `validate.py --fix-refs` after moving code.
- **Crash catalog and fault timings other than probability/force-after are still per-app code** (`crashes.yaml` documents them; only the journey consumes spec numbers).
- RN generated file is `src/generated/specConstants.ts` (not `spec.ts`: Jest treated `spec.ts` as a test).
- Unit tier: iOS = compile for the simulator + `ios/scripts/test-journey-engine.sh` (swiftc host build replaying golden.json; no XCTest target); RN = `tsc` + `jest journeyEngine`; Android JVM tests (`SpecConstantsTest`, `RecorderTest`, `JourneyEngineTest`); Flutter `flutter test` (9 pass).

### Decisions
Resolved: OPEN-1 (`BITDRIFT_SDK_KEY`), OPEN-2 (`app_variant=sdk-demo`), OPEN-4 (end spans as failure). **Resolved in Phase 4 by applying the plan's recommendations (confirm or revisit):** OPEN-3 crash loop fires at a random back-half journey point on every app (`crash_journey_point` everywhere, confirmation fallback), OPEN-5 the journey emits `add_to_cart`/`add_to_wishlist`/`cart_item_removed`/`checkout_started`/`payment_completed`, D-JRN-2 retry among the other three methods incl. Android Pay (RN now matches), D-PER-3 A/B interleaved on every app. See D-JRN-5. **Still open:** OPEN-6 cardinality demo (recommendation: Advanced-screen toggle, off by default).

### Phase 5 starting point
Workflows/dashboards/scripts (plan §1 "Workflows, dashboards and scripts", §4 row 5). Inputs: `android/workflows`, `ios/workflows`, `sessionmetricsdemo/workflows` (a deliberately portable copy of bd-shop-13/14/15; its chart metadata is byte-identical to Android's), `*/dashboards`, `ios/scripts/deploy-workflows.sh`, the spec's `used_by` lists. Live account has ~36 `bd-shop` workflows (`bd workflow list | grep bd-shop`); list and confirm before replacing any. Phase 4 changed the journey shape on Android (tap events now in sim sessions, crash point random while the crash loop is on), so re-check funnel/crash workflows when templating them.
Model: **Sonnet** (decided 2026-10-26). Order of work:
1. **Mapping table first, then stop.** Run `bd workflow list` and `bd dashboard` (read-only) and write `spec/workflows/MAPPING.md`: one row per live `bd-shop` workflow and per committed workflow/dashboard JSON (`android/`, `ios/`, `sessionmetricsdemo/`) with its live ID, what it matches, which new globally unique slug (e.g. `bd-shop-fg-session-count`) and template it becomes, or *keep platform-specific* / *retire*, and why. Resolve the number collisions (`bd-shop-13/14/15` mean foreground-session metrics on Android but hang/force-quit/crash-by-screen on iOS). Flag every workflow whose matchers assume the pre-Phase-4 journey shape (one journey per session ending at Confirmation; crashes only after Confirmation; no tap events in sim sessions): `bd-shop-01` funnel, crashes-by-final-screen, journey-vs-crashes, crash-terminal Sankey. **Present the table to the user and wait for approval** before step 3.
2. Templates: `spec/workflows/*.json` parameterized by `{{platform}}`/`{{app_id}}`, `spec/dashboards/*.json` using `__WF_<slug>__` placeholders only; shared shell helpers in `scripts/lib/` reading persisted key names from `faults.yaml`.
3. `tools/bd-deploy.sh <app_id>`: create-or-update by slug (never duplicate), capture IDs, substitute into dashboards. Replaces `ios/scripts/deploy-workflows.sh` and the Android README's manual steps. Retire/delete live workflows only as approved in step 1.
4. Verify: deploy to each app, `bd workflow list` shows one set per app, charts populate after a `./test.sh <app> smoke` run (`bd workflow charts <id> --output json`; human mode needs a TTY).
Changing the journey: edit `spec/journey.yaml` / `personas.yaml`, run `tools/codegen/generate.sh`, then `./test.sh all unit` (see `tools/journey/README.md`).

### How to verify the current state
```
cd /Users/slerner/code/sa-public/bitdrift-shop
./test.sh all unit && ./test.sh all smoke      # needs an Android emulator (AVD Medium_Phone) and an iOS simulator
tools/codegen/check.sh                          # generated constants + journey bundles + golden.json match spec/
tools/codegen/.venv/bin/python spec/validate.py --strict
```

### Environment notes
- Never print or commit keys: `android/.local.properties*`, `ios/.local.xcconfig`, `reactnative/.env`, `flutter/.env` are gitignored and hold the (shared) SDK key.
- `tools/codegen/.venv` is created on first use (PyYAML). `test.sh` uses it.
- RN iOS needs `LANG/LC_ALL=en_US.UTF-8` for `pod install` (Ruby 4 locale bug). If the Gradle wrapper times out downloading 8.10.2 for RN-Android, `curl` the zip into `~/.gradle/wrapper/dists/gradle-8.10.2-all/<hash>/` (done once; cached).
- The Flutter iOS build can need `flutter clean` after an SDK upgrade (undefined Flutter symbols at link).
- Flutter on Android is built `--release` by its start script; the harness gate is the `BDSHOP_HARNESS` define.
- bitdrift CLI/MCP: `bd tail --output jsonl android|ios` works; session IDs are masked in tail output.

