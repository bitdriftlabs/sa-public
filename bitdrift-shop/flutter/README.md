# Bitdrift Shop — Flutter (alpha)

A Flutter port of the Bitdrift Shop demo. It talks to the same shared backend
and emits the same structured bitdrift signal (screen views, spans, feature-flag
fields, entity) so its sessions land in the same dashboards as the
Android / iOS / React Native apps.

> **Alpha, best-effort.** This uses the `capture_flutter` alpha prototype
> (git tag `flutter-prototype-0.0.3`). The API may change and some native
> Capture features are not exposed yet — see
> [What this wires vs. doesn't](#what-this-wires-vs-doesnt).

## What this is and is not

- ✅ Same shopping flow: browse / search / featured / categories → product /
  reviews → cart / wishlist → guest / signin checkout → 4 payment methods →
  confirmation, a Diagnostics screen (session id/url/device id, new session),
  and a device-code button on the welcome screen (label becomes the code,
  like the Android app).
- ✅ bitdrift `Capture.start` + logging, screen views, global fields, native
  spans, and the session/device APIs.
- ✅ Variant-driven simulation (Control / Variant A / Variant B) that drives the
  real screens while logging journey spans and `ff_*` feature-flag fields.
- ✅ Android *and* iOS build & run **entirely via CLI/scripts — no Android
  Studio, no opening Xcode**.
- ✅ Crash injection (native signals via libc — see Crash mode below).
- ❌ ANR / force-quit injection — the alpha SDK has no Dart→native
  crash bridge for those, so they wouldn't be reported (intentionally omitted).
- ⚠️ Network-instrumentation and session-replay parity — the alpha exposes a
  subset; we still send `x-capture-path-template` and structured `api_*` logs.

## Prerequisites

- macOS (Apple Silicon) — matches the committed `arm64-v8a` system image.
- JDK 21+ (needed by the Android `cmdline-tools` and the Gradle build), e.g.
  `brew install openjdk@21`.
- A local backend (next step). Docker/Colima or Python.
- **For Android:** just the JDK above — `scripts/android-1-setup.sh` handles the
  rest (no Android Studio needed).
- **For iOS:** the *full* Xcode.app (not just command-line tools) from the App
  Store or developer.apple.com — `xcode-select --install` alone isn't enough.
  Requires its license accepted and (once) `sudo xcodebuild -runFirstLaunch`,
  both one-time interactive/`sudo` steps `scripts/ios-1-setup.sh` can't do for
  you but will tell you about. Also needs ~8.5 GB free disk space the first
  time a simulator runtime is downloaded.

## 1. Start the backend (from `../backend`)

```bash
./start-backend-docker.sh          # or ./start-backend-chaos-docker.sh for faults
```

Serves `http://localhost:5173`. From the Android emulator the app reaches it via
the host alias `10.0.2.2:5173` (handled automatically).

## 2. Install Flutter (one-time)

```bash
bash scripts/0-install-flutter.sh
```

Clones Flutter (stable) to `~/development/flutter` and runs `flutter doctor`.
Add the printed `PATH` line to your shell profile.

## 3. Set up the platform toolchain (one-time)

**Android:**
```bash
bash scripts/android-1-setup.sh
```
Installs the command-line tools (no Studio), ensures the packages Flutter
needs (licenses are accepted automatically by the newer `android` CLI), and
creates the `bitdrift_shop` AVD.

**iOS:**
```bash
bash scripts/ios-1-setup.sh
```
Checks Xcode is fully installed (not just command-line tools), its license is
accepted, and a simulator runtime is downloaded — installs CocoaPods
automatically, but reports the rest as manual steps if missing (they require
`sudo`/interactive prompts this script can't issue for you). Re-run any time
to check status.

## 4. Build & run

Copy `env.example` to `.env` and fill in your key (empty is fine — the app
still runs, just without uploading to bitdrift):
```bash
cp env.example .env   # then edit .env and set BITDRIFT_SDK_KEY
```

**Android:**
```bash
# Windowed by default (software rendering on macOS, where the GPU backend
# crashes). Headless: EMULATOR_WINDOW=0 bash scripts/android-2-start-emulator.sh
bash scripts/android-2-start-emulator.sh

bash scripts/android-3-start-app.sh   # build + install + launch
```

**iOS:**
```bash
bash scripts/ios-2-start-simulator.sh   # override device: DEVICE_NAME="iPhone 16e" ...

bash scripts/ios-3-start-app.sh   # build + install + launch
```

In the app: pick a persona, then **Start (3 runs)** / **Infinite** to drive a
full journey, or tap **Browse** to navigate manually. **Diagnostics** (top
right) shows the session id/url and lets you generate a temporary device code.

## Config

Values are compile-time `--dart-define`s. Set them in `flutter/.env` (copy
from `env.example` — see step 4 above); `scripts/android-3-start-app.sh`
(Android) and `scripts/ios-3-start-app.sh` (iOS) both load it automatically.
A shell-exported variable of the same name overrides `.env` if you ever need
that (e.g. CI), but `.env` is the recommended way to set these:

| Var                | Default                  | Notes                                    |
|--------------------|--------------------------|------------------------------------------|
| `BITDRIFT_SDK_KEY` | empty                    | Empty runs the app locally, no upload    |
| `BITDRIFT_API_HOST`| `https://api.bitdrift.io`| Capture API host                         |
| `BACKEND_PORT`     | `5173`                   | Local FastAPI shop backend               |

## Layout

```
flutter/
├── README.md
├── env.example
├── pubspec.yaml                 # capture_flutter (git alpha) + flutter_lints
├── android/                     # Android app scaffold (generated by `flutter create .`)
│   └── app/build.gradle.kts     # app's own Java/Kotlin target: 21 (independent of the plugin's own 17)
├── ios/                         # iOS app scaffold (generated by `flutter create .`)
├── lib/
│   ├── main.dart                # Capture.start early, global fields, cold-start spans
│   ├── app.dart                 # MaterialApp + routes
│   ├── config.dart              # build-time config + backend base URL
│   ├── crash.dart               # native-signal crash injection + crash-loop flag
│   ├── generated/key.dart       # committed empty stub; *-3-start-app.sh bakes the key per build
│   ├── bd/capture.dart          # single-seam wrapper over the alpha SDK
│   ├── api/client.dart          # typed endpoints + x-capture-path-template + logging
│   ├── models/models.dart       # Product / Category views
│   ├── sim/simulator.dart       # variant profiles + simplified journey driver
│   └── ui/{welcome,screens,widgets}.dart
├── scripts/                          # per-platform, numbered by order-of-use
│   ├── 0-install-flutter.sh          # one-time Flutter install (shared)
│   ├── android-1-setup.sh            # one-time Android SDK/AVD setup
│   ├── android-2-start-emulator.sh   # start the emulator
│   ├── android-3-start-app.sh        # build + install + launch
│   ├── android-4-stop-app.sh         # stop the app (emulator keeps running)
│   ├── android-5-stop-emulator.sh    # stop the emulator
│   ├── ios-1-setup.sh                # one-time iOS toolchain check (Xcode/CocoaPods/runtime)
│   ├── ios-2-start-simulator.sh      # boot the simulator
│   ├── ios-3-start-app.sh            # build + install + launch
│   ├── ios-4-stop-app.sh             # stop the app (simulator keeps running)
│   ├── ios-5-stop-simulator.sh       # shut down the simulator
│   └── crash-loop.sh                 # Android crash-on-payment loop
└── test/models_test.dart
```

## What this wires vs. doesn't

| Area                                | Status in this port                          |
|-------------------------------------|----------------------------------------------|
| `Capture.start` (activity session, replay on Android) | ✅ used in `main.dart` |
| `logTrace/Debug/Info/Warning/Error`, `logScreenView`  | ✅ via `bd/capture.dart` |
| `addField` / `removeField`          | ✅ `app_variant`, `platform`, `ff_*` |
| `startSpan` / `endSpan`             | ✅ journey / discovery / checkout spans |
| `sessionId` / `sessionUrl` / `deviceId` | ✅ Diagnostics screen |
| `getSdkStatus` | ⚠️ exposed in alpha, not surfaced in the port |
| `createTemporaryDeviceCode` | ✅ welcome screen (label becomes the code, like Android) |
| `startNewSession` | ✅ Diagnostics screen ("New session") |
| `setEntityId` / `clearEntityId`     | ✅ real API as of 0.0.3 (previously faked as an `entity_id` field on 0.0.1). `sim/simulator.dart`: signed-in journeys get a fresh, unique entity every run (`Name-runN`, never reused); guest journeys call `clearEntityId` — a real anonymous session, which 0.0.1 had no way to represent |
| Feature-flag exposure API           | ⚠️ not in alpha → recorded as `ff_*` fields |
| App-launch TTI API                  | ⚠️ not in alpha → emitted as completed-span pair |
| Network request/response capture    | ⚠️ not exposed → `x-capture-path-template` header + `api_*` structured logs |
| Dart/Flutter exception → crash      | ⚠️ not prototyped → native-signal crashes instead (see Crash mode) |

## Tests

```bash
flutter analyze    # clean (no errors)
flutter test       # 6/7 passing — see known issue below
```

Verified end-to-end: builds and runs on the arm64 `sdk gphone64` Android
emulator and an iPhone 17 Pro iOS Simulator via the scripts above.

**Known issue (pre-existing, unrelated to the SDK version):** `LoadScreen
shows error + retry when fetch fails, then renders on retry` in
`test/widgets_test.dart` fails — its `MaterialApp` test harness never
provides a `SimulatorScope` ancestor, which `ScreenShell.build()` requires via
`SimulatorScope.of(context)`. Confirmed present before any of the SDK 0.0.3
migration changes in this PR; not fixed here to keep the PR scoped.

## Crash mode (alpha — best effort)

The alpha SDK has no Dart exception bridge, so uncaught Dart exceptions are
not offered (the VM logs them and the app keeps running). Instead the app uses
the crash shapes that do work — native signals raised in our own process via
libc, mirroring the Android demo's native entries:

- **Crash: random** (welcome screen) — one-shot, a random shape.
- Shapes: `SIGABRT` / `SIGSEGV` / `SIGBUS` (real native crashes — verified:
  each kills the app with the matching signal in logcat) and `exit`
  (`exit(1)`, a hard exit with no signal).

Crash loop (like the Android demo's "crash on payment"): the loop flag lives
in the `debug.bd_shop_crash` property, so it persists across crashes. The loop
is script-driven (like `android/scripts/watchdog.sh`) because the app can read
the property but cannot write it (SELinux denies `untrusted_app` the
property-service socket on this device). While the loop is active, each launch
runs one shopping journey and crashes with a random shape when it reaches
payment:

```bash
bash scripts/crash-loop.sh    # each pass: fresh journey ending in a random crash at payment
# Ctrl-C to stop (clears the property)
```

Whether bitdrift groups these as crash issues is best-effort in the alpha SDK
— check your account after running one.

## Troubleshooting

- **Emulator window flashes and dies (CoreGraphics / `Failed to restore
  previous context` error)** — the windowed GPU backend is unstable on this
  machine. `android-2-start-emulator.sh` already defaults to software rendering on
  macOS (`swiftshader_indirect`); if you overrode it with `EMU_GPU=host`,
  drop the override to get the default back.
- **`No application found for TargetPlatform.android_arm64`** — the `android/`
  scaffold is missing. Regenerate it (does not touch `lib/`):
  `flutter create . --platforms=android`
- **`Inconsistent JVM Target Compatibility` gradle failure** — `capture_flutter`
  0.0.3+ sets its own Java *and* Kotlin targets to 17 internally, and the app
  targets 21 (`android/app/build.gradle.kts`). These don't need to match
  across modules; if you see this error, check that nothing in
  `android/build.gradle.kts` is force-overriding the plugin's Kotlin target
  (an old `flutter-prototype-0.0.1`-era workaround did this and was removed —
  it clobbered only the Kotlin side of the plugin's config, not the Java side,
  causing exactly this mismatch).
- **`No application found for TargetPlatform.iOS` / no `ios/` folder** —
  regenerate it (does not touch `lib/`): `flutter create . --platforms=ios`
- **`Xcode installation is incomplete` / `xcodebuild requires Xcode`** — only
  the command-line tools are installed. Install the full Xcode.app, then:
  `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
- **`You have not agreed to the Xcode license agreements`** — run
  `sudo xcodebuild -license` (interactive) and/or
  `sudo xcodebuild -runFirstLaunch`. Note plain `xcodebuild -license` with no
  subcommand can misreport "not agreed" when run non-interactively even after
  you've accepted it — check real status with
  `xcodebuild -checkFirstLaunchStatus` (exit code 0 = fine).
- **`Insufficient space available` downloading a simulator platform** — the
  iOS simulator runtime is ~8.5 GB; free up space, then
  `xcodebuild -downloadPlatform iOS`.
- **Xcode SPM error: `the manifest is backward-incompatible with Swift < 6.0
  because the tools-version was specified in a subsequent line`** — an
  upstream bug in `capture_flutter`'s `ios/capture_flutter/Package.swift`
  (`swift-tools-version` wasn't on line 1). Fixed upstream in
  [capture-sdk#1194](https://github.com/bitdriftlabs/capture-sdk/pull/1194) —
  make sure your `pubspec.yaml` git ref includes that fix.

## Stopping

**Android:**
```bash
bash scripts/android-4-stop-app.sh        # stop the app
bash scripts/android-5-stop-emulator.sh   # stop the emulator
```

**iOS:**
```bash
bash scripts/ios-4-stop-app.sh        # stop the app
bash scripts/ios-5-stop-simulator.sh  # stop the simulator
```
