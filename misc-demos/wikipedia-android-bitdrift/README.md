# Wikipedia Android app instrumented with bitdrift Capture

This is the official [Wikipedia Android app](https://github.com/wikimedia/apps-android-wikipedia),
instrumented with the [bitdrift Capture SDK](https://docs.bitdrift.io/) for mobile observability.
It backs the [hands-on blog post](https://blog.bitdrift.io/post/hands-on-wikipedia-android) and
bitdrift demos: logs, sessions, network and WebView instrumentation, crash and ANR reporting,
device commands and profiling.

Everything bitdrift adds is listed in [What's customized](#whats-customized). The rest is upstream
Wikipedia code, last synced with upstream `main` at
[`a4d1a30a77`](https://github.com/wikimedia/apps-android-wikipedia/commit/a4d1a30a77) (2026-11-18).

## Quick start

1. Create `local.properties` in this directory (Android Studio creates it; it is gitignored) and add
   your SDK key:

   ```properties
   BITDRIFT_API_KEY=<your SDK key>
   # Optional. Defaults to api.bitdrift.io. bitdrift-internal: api.bitdrift.dev for dev.
   BITDRIFT_API_HOST=api.bitdrift.io
   # Optional. The entity ID to report under. Defaults to demo.
   ENTITY_ID=<entity ID>
   # Optional. Overrides the Capture SDK version; see "Testing other SDK versions".
   BITDRIFT_CAPTURE_VERSION=<version>
   # Optional. A throwaway Wikipedia test account for the log_in_user command (compiled into the build).
   BITDRIFT_DEMO_USERNAME=<test account>
   BITDRIFT_DEMO_PASSWORD=<test password>
   ```

2. Build and install the `dev` flavor:

   ```sh
   ./gradlew :app:installDevDebug
   ```

3. Open the app. It starts Capture on launch; find the device under **Entities** in bitdrift.

Profiling commands need Android 15 (API 35) or later. ANR crash profiles need Android 16 (API 36)
and OOM crash profiles Android 17 (API 37). Emulators work; give them 16 GB of data storage, since
heap dumps are written to the device before upload.

> **Capture SDK version.** Crash profiling (below) uses `CrashProfilingMode`, which arrives in
> Capture 0.52.0. Until 0.52.0 is published, build with `BITDRIFT_CAPTURE_VERSION=SNAPSHOT` from a
> local SDK build.

## What's customized

All bitdrift changes are in the files below. Code written for this demo lives in
`app/src/main/java/org/wikipedia/bitdriftdev/`; everything else is a small change to an upstream
file.

| Area | Files | What it does |
| --- | --- | --- |
| SDK setup | `WikipediaApp.kt` | Starts Capture, sets the entity ID, turns on crash profiling, registers device commands |
| Build | `app/build.gradle`, `gradle/libs.versions.toml` | Capture SDK and Gradle plugin, `local.properties` settings, automatic instrumentation |
| Logs | `util/log/L.kt` | Forwards the app's own logging to Capture |
| Screen views | `analytics/eventplatform/BreadCrumbLogEvent.kt` | Logs a screen view whenever a screen is shown |
| Analytics events | `analytics/eventplatform/EventPlatformClient.kt`, `analytics/testkitchen/TestKitchenAdapter.kt` | Copies Wikipedia's own analytics events into Capture logs |
| App launch time | `main/MainActivity.kt` | Reports time to interactive on the first frame |
| Debug menu | `bitdriftdev/GlobalDebugGesture.kt`, `DebugLeaker.kt`, `DebugCrasher.kt` | Hidden menu that simulates leaks, crashes and ANRs |
| Device commands | `bitdriftdev/BitdriftCommands.kt`, `AppProfiler.kt` | Handlers for commands sent from the Device Console |
| Repo housekeeping | `.gitignore`, `gradle/gradle-daemon-jvm.properties`, `gradle.properties` | Keeps upstream's public debug keystore tracked, pins the Gradle daemon JVM |

### SDK setup

`WikipediaApp.onCreate` calls `Logger.start` with the key and host from `local.properties`, a
`SessionConfiguration()` that starts a new session on every launch, and
`Configuration(crashProfilingMode = CrashProfilingMode.AUTOMATIC)`. It then sets the entity ID
(`ENTITY_ID`, default `demo`) and registers the device command handlers.

### Automatic instrumentation

The Capture Gradle plugin (`bitdrift { … }` block in `app/build.gradle`) instruments every OkHttp
client and every WebView with JavaScript enabled, which is all of the app's WebViews (articles,
link previews and the rest). `androidx.webkit` is added because the WebView instrumentation needs
it. No call sites were changed.

### Logs, screen views and analytics

- **App logs:** `L.kt` is Wikipedia's logging wrapper. Each level also logs to Capture at the
  matching level, with the tag as a `tag` field and throwables attached to errors.
- **Screen views:** the screen-shown breadcrumb also calls `Logger.logScreenView` with the readable
  screen name, so session timelines and journeys show screen changes.
- **Analytics:** events sent to Wikimedia's Event Platform are also logged to Capture as
  `analytics_event`, with `event_stream`, `event_type` and the event's top-level fields. Test
  Kitchen events are logged as `testkitchen_event` with the instrument name, action and interaction
  fields. These make good workflow match conditions.
- **App launch:** `MainActivity` reports `Logger.logAppLaunchTTI` when its first frame is about to
  draw.

### Debug menu

Hold one finger in the **bottom-right corner of any screen for 3 seconds** to open it. Each option
logs a warning to Capture first, so the session shows what was triggered.

| Option | What happens |
| --- | --- |
| Start Slow Leak (+256 KB / 500ms) | Adds 256 KB to a static list every half second until the app restarts. Use before a heap dump. |
| Force OOM Now | Allocates 1 MB every 50 ms until an `OutOfMemoryError` crashes the app |
| Native Crash (SIGSEGV) | Kills the process with a native signal, reported on the next launch |
| Force ANR (block main thread 60s) | Blocks the main thread. Tap the screen again, then choose **Close app** on the dialog for a fatal ANR. |

### Device commands

Device commands run code on one device from the Device Console or `bd command invoke`. A command
needs an entry in your bitdrift command catalog **and** a handler in the app with the same key.
Built-in commands such as `stack_sampling_trace` and `take_screenshot` are handled by the SDK and
need no app code. This app registers handlers for these commands:

| Command | Arguments | What it does |
| --- | --- | --- |
| `heap_profile_demo` | `buffer_size_kb`, `duration_ms`, `sampling_interval_bytes`, `track_java_allocations` | Perfetto heap profile: Java allocations (`true`) or native (`false`) |
| `java_heap_dump_demo` | `buffer_size_kb` | Perfetto Java heap dump: one snapshot of every object |
| `system_trace_iain` | `duration_ms` | Perfetto system trace: CPU scheduling, thread states and frames |
| `system_trace` | `duration_ms`, optional `profiling_type` | Stack sample by default; other types only if the catalog defines `profiling_type` |
| `flip_flag` | `flag` | Toggles a named feature flag and reports the exposure |
| `memory_dump` | optional `is_attachment` | Java heap usage numbers (not a dump) |
| `ui_state_slow` | optional `duration_ms` | Waits, for testing cancellation |
| `open_settings` | none | Opens the Settings screen |
| `log_out_user` | none | Logs out at once, as Settings does after its confirmation, and shows a toast. Returns the account type, never the username. |
| `log_in_user` | none | Logs in with `BITDRIFT_DEMO_USERNAME` and `BITDRIFT_DEMO_PASSWORD` from `local.properties`, never from arguments. Returns `logging_in` and logs the outcome as `log_in_user` (for example `logged_in`, `needs_email_code`). |

The profiling commands use Android's ProfilingManager (API 35+) and return the trace as a file
attachment, which opens in the embedded Perfetto viewer. In the Device Console, arguments are
positional: required ones first, each group alphabetical (run `help <command>` to check).
`system_trace_iain` is registered in bitdrift's internal dev catalog for this app only; register
your own copy with `bd command register` to use it elsewhere.

Things to know:

- **Android rate limit.** Android allows about one profiling capture per app per hour. Later
  commands fail at once with `profiling_failed`. On a test device, turn the limiter off with
  `adb shell device_config put profiling_testing rate_limiter.disabled true` (undo with
  `device_config delete`).
- **Attachment size.** Capture 0.51.0 uploads attachments up to 5 MB, which is too small for a heap
  dump (about 20 to 26 MB here). Chunked uploads for larger files are on capture-sdk `main` for
  the next release; until then, heap dumps need a `SNAPSHOT` build.
- **Errors.** Handlers put the failure reason in the error description. On failure the SDK writes
  its own `error` field, replacing any context field of that name.

### Crash profiles

With `CrashProfilingMode.AUTOMATIC`, Capture attaches Android's ANR system trace (API 36+) and Java
OOM heap graph (API 37+) to the matching fatal issue, shown on the issue's **Profile** tab. Android
only saves an ANR profile if a background trace happened to be running, so in production only some
ANRs get one. To make every ANR get a profile on a test device:

```sh
adb shell device_config put profiling_testing system_triggered_profiling.testing_package_name org.wikipedia.dev
```

Wait about a minute after launching the app, force an ANR from the debug menu, choose **Close app**,
then reopen the app so the profile can upload. Turn test tracing off while running profiling
commands, since a continuous trace can block them:

```sh
adb shell device_config delete profiling_testing system_triggered_profiling.testing_package_name
```

See [Android Crash Profiling](https://docs.bitdrift.io/sdk/features/android-crash-profiling) and
its [testing guide](https://docs.bitdrift.io/sdk/features/android-crash-profiling-testing).

## Testing other SDK versions

`BITDRIFT_CAPTURE_VERSION` in `local.properties` changes the Capture SDK for your local builds only:

- **A published version**, e.g. `0.50.0`, to compare releases.
- **`SNAPSHOT`**, for an unreleased SDK. In a
  [capture-sdk](https://github.com/bitdriftlabs/capture-sdk) checkout, run
  `tools/local_maven_deploy.sh`; it installs the build into `~/.m2`.

Each build prints the SDK it uses, e.g.
`bitdrift capture dependency: io.bitdrift:capture:SNAPSHOT (local build from ~/.m2)`. Remove the
line to return to the version in `gradle/libs.versions.toml`. To upgrade the demo for everyone,
change `bitdriftCapture` and `bitdriftCapturePlugin` there instead.

If the Kotlin compiler crashes with `Backend Internal error: Exception during IR lowering` after
changing SDK versions, its incremental cache is stale: run `./gradlew --stop` and a clean build.

## Build notes

- **Android Gradle Plugin** is pinned to 9.4.1 in `libs.versions.toml`, below upstream's 9.5.x,
  because current Android Studio doesn't support AGP 9.5 yet. Restore upstream's version once it
  does.
- **`.gitignore`** has exceptions so upstream's public debug keystore (`repo.keystore`) and
  `app/src/release/` stay tracked.

## Syncing with upstream

Upstream history is not kept here. To sync, start from the upstream commit above, copy this
directory over it so one commit holds every bitdrift change, then merge upstream `main` into that
commit. Conflicts are limited to the files in [What's customized](#whats-customized), usually
`gradle/libs.versions.toml`. Copy the result back, leaving out upstream's `.github/`, `fastlane/`
and Gemfiles, and update the commit and date at the top of this README.

## Help

[bitdrift docs](https://docs.bitdrift.io/) ·
[hands-on guide](https://blog.bitdrift.io/post/hands-on-wikipedia-android) ·
[public Slack](https://communityinviter.com/apps/bitdriftpublic/bitdrifters) · info@bitdrift.io
