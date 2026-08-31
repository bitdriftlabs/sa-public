# HANDOFF — Flutter Shop (bitdrift alpha)

> Context-window checkpoint. Written so a fresh agent can resume without the full
> conversation. **Keep it current as work proceeds.**

## Rule for the next session
- **Pause near ~89% of the token/context budget and stop task work to refresh
  this doc.** Do not let context run out mid-task.
- Working style (user's personal AGENTS.md): restate scope first; no unrequested
  extras; pause after each verified step; smallest diff; *report, don't drive-by
  fix*; ask one question when ambiguous.

## Status
- **What:** best-effort Flutter port of the bitdrift shop (same backend, same
  flow, alpha `capture_flutter`) + CLI-only Android build/run (no Android Studio).
- **State:** app + 4 scripts + README + test + HANDOFF are **written**. **NOT yet
  compiled** — `flutter analyze` / `flutter test` / build have **not** been run
  (Flutter is not installed in this env and it is offline).
- **Key var:** the bitdrift credential is `BITDRIFT_SDK_KEY` (**not**
  `BITDRIFT_API_KEY`) — renamed across config/scripts/docs to match Android/KMP
  and the SDK's own name. `BITDRIFT_API_HOST` is unchanged (consistent repo-wide).
- **Flutter skills:** the initial build did **not** invoke the installed `flutter-*`
  / `dart-*` skills (built from general Flutter knowledge + the RN app as reference).
  **Next step (user):** let's see if we can improve the app using the official
  Flutter skills — see [Candidate improvements](#candidate-improvements-official-flutter-skills).
- **Also pending:** install Flutter + `flutter analyze`/`flutter test` to prove it
  compiles (needs network access + user OK), or the user runs the scripts.

## Files (all under `flutter/`)
- `lib/main.dart` — `Capture.start` early, global fields, cold-start spans
- `lib/app.dart` — `MaterialApp` + 20 routes
- `lib/config.dart` — dart-define config; backend base URL (`10.0.2.2` on Android)
- `lib/bd/capture.dart` — `Bd` seam; **every call is crash-resilient** (swallows errors)
- `lib/api/client.dart` — `dart:io HttpClient`; `x-capture-path-template`; `api_*` logging
- `lib/models/models.dart` — `Product` / `Category`
- `lib/sim/simulator.dart` — `SimVariant`, profiles, journey driver, `SimulatorScope`
- `lib/ui/{welcome,screens,widgets}.dart` — 16 shopping screens + Diagnostics
- `scripts/{install-flutter,setup-android,start-emulator,run-app}.sh` — all `bash -n` clean
- `test/models_test.dart`, `README.md`, `PLAN.md`, `env.example`, `pubspec.yaml`,
  `analysis_options.yaml`

## Key decisions / assumptions
- Deps: only `capture_flutter` (git tag `flutter-prototype-0.0.1`) + `flutter_lints`.
  HTTP via `dart:io` (no `http` package). Icons from Material.
- Session: `SessionStrategy.activityBased`; `enableSessionReplay: true`
  (Android-only effect in the alpha).
- Alpha gaps handled by approximation: feature flags → `ff_*` fields; entity →
  `entity_id` field; TTI → completed-span log pair; network →
  `x-capture-path-template` header + `api_*` structured logs.
- **ANR / force-quit / crash-loop dropped** (user decision) — no Dart→native crash
  bridge in the alpha.
- iOS not targeted (Android emulator only).
- Env: bitdrift key read from `BITDRIFT_SDK_KEY` (compile-time `--dart-define` via
  `String.fromEnvironment`; `run-app.sh` passes it through). A real `flutter/.env`
  with `BITDRIFT_SDK_KEY` + `BITDRIFT_API_HOST` already exists, but `run-app.sh`
  reads the **shell** env, not the `.env` file — a `.env` loader is an open option.

## Gotchas (may surface on first compile/run)
- Dart 3 syntax used: switch expressions, record destructuring in `for`
  (`for (final (a, b) in ...)`), `context.mounted`, `String.fromEnvironment`.
  Needs Dart ≥3.0 / Flutter ≥3.10 (pubspec pins `sdk: >=3.0.0 <4.0.0`,
  `flutter: >=3.10.0`).
- `capture_flutter` resolves from git; I pulled exact signatures from the tag's
  `src/capture.dart` + `src/span.dart` (not guessing).
- Emulator: the machine has an arm64 `google_apis_playstore` image under
  `system-images/android-36.1/`; `setup-android.sh` auto-detects any installed
  arm64 image else installs `android-36`. **No `cmdline-tools` present yet** —
  the script installs them.
- `run-app.sh` passes `BITDRIFT_SDK_KEY` (from the shell env; empty = local-only
  run). It does **not** read `flutter/.env` — add a `.env` loader if you want the
  RN-style "drop it in `.env`" flow.
- `flutter analyze` lints (e.g. `use_build_context_synchronously`) are already
  guarded via `.mounted` / `if (mounted)`.

## To resume (the pending next step)
```bash
# backend first (from ../backend)
./start-backend-docker.sh
# toolchain
bash scripts/install-flutter.sh        # git clone stable → ~/development/flutter; flutter doctor
flutter pub get && flutter analyze && flutter test
bash scripts/setup-android.sh          # cmdline-tools + licenses + AVD 'bitdrift_shop'
bash scripts/start-emulator.sh         # boot (headless; EMULATOR_WINDOW=1 to show)
export BITDRIFT_SDK_KEY=...            # optional; empty = no bitdrift upload
bash scripts/run-app.sh                # flutter run --release on the emulator
```

## Candidate improvements (official Flutter skills)
The initial build did **not** invoke the installed Flutter skills. Candidates to
consider (each adds deps and needs `flutter pub get` + `flutter analyze` to verify,
so they bundle naturally with the "install Flutter + analyze/test" step):

- `flutter-use-http-package` — swap `dart:io HttpClient` (`lib/api/client.dart`)
  for the `http` package (adds a dependency; currently zero extra deps).
- `flutter-setup-declarative-routing` — `MaterialApp.router` + `go_router` instead
  of `routes` + `pushNamed` (adds `go_router`; affects the sim's `NavigatorState` use).
- `flutter-apply-architecture-best-practices` — review the `lib/` layering
  (UI / Logic / Data) — currently a flat `lib/{bd,api,models,sim,ui}`.
- `flutter-add-widget-test` / `dart-add-unit-test` — add widget + API-client tests
  beyond the existing `test/models_test.dart`.

Note the two that add dependencies (`http`, `go_router`) are trade-offs: the
current code deliberately keeps deps to just `capture_flutter`. Decide before
switching.

## Not done / out of scope
- No `flutter-clean` (no-SDK counterpart) — not requested.
- iOS build/run.
- Real session-replay / network-instrumentation parity (alpha-limited).
- Crash / ANR / force-quit (dropped by user).
