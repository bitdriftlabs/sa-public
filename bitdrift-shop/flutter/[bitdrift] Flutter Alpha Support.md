# \[bitdrift\] Flutter Alpha Support

## TLDR

Flutter alpha support prototype is currently available for Android and iOS.

Open PR: [https://github.com/bitdriftlabs/capture-sdk/pull/996](https://github.com/bitdriftlabs/capture-sdk/pull/996)

Customers interested in testing can use the `flutter-prototype-0.0.1` tag directly from Git.

```
dependencies:
  capture_flutter:
    git:
      url: https://github.com/bitdriftlabs/capture-sdk.git
      ref: flutter-prototype-0.0.1
      path: platform/capture_flutter
```

| *This is an alpha prototype, not a production-ready Flutter SDK release. The API shape may change, and some native Capture features are not exposed yet. For Android, session replay currently uses Flutter-side wireframe capture and forwards encoded screen updates to the native SDK. For iOS, session replay is not ready for customer testing yet. The expectation is to reuse the same Flutter-side wireframe capture logic once the iOS native bridge is finalized. Check the support section below.* |
| :---- |

## Support Matrix

| Area | Android | iOS | Notes |
| :---- | :---- | :---- | :---- |
| SDK start | Supported | Supported | `Capture.start(...)` with API key, API URL, session strategy, and optional session replay flag. |
| Main `Capture.Logger` APIs | Supported | Supported | Logging, sessions, fields, screen views, spans, temporary device code, and SDK status. |
| Session Replay | Supported | Not supported yet | Android uses Flutter wireframe capture. iOS should reuse the same Dart-side logic once native bridging is finished. |
| Native fatal issues | Supported | Supported | Native platform fatal issue reporting comes from the underlying Android/iOS Capture SDKs. |
| Dart exceptions | Not supported | Not supported | Not prototyped yet. Dart/Flutter exceptions do not automatically surface as native JVM/iOS crashes, so flutter client will need to install explicit Dart/Flutter error handlers and bridge those errors into Capture. We will also need a Dart/Flutter symbolication pipeline for obfuscated stack traces in release builds. |
| Webview | Not supported | Not supported | To get existing Android support in native it just requires to pass the WebConfig options to Capture.Logger.start and enable via gradle plugin  |

### Supported APIs

| API | Status | Notes |
| :---- | :---- | :---- |
| `Capture.start(...)` | Supported | Supports `apiKey`, `apiUrl`, `sessionStrategy`, and `enableSessionReplay`. |
| `Capture.logTrace(...)` | Supported | Supports optional `Map<String, String>` fields. |
| `Capture.logDebug(...)` | Supported | Supports optional `Map<String, String>` fields. |
| `Capture.logInfo(...)` | Supported | Supports optional `Map<String, String>` fields. |
| `Capture.logWarning(...)` | Supported | Supports optional `Map<String, String>` fields. |
| `Capture.logError(...)` | Supported | Supports optional `Map<String, String>` fields. Does not yet accept Dart `Object error` / `StackTrace`. |
| `Capture.log(...)` | Supported | Generic level-based logging. |
| `Capture.logScreenView(...)` | Supported | Manual screen-view logging. |
| `Capture.sessionId` | Supported | Async getter. |
| `Capture.sessionUrl` | Supported | Async getter. |
| `Capture.deviceId` | Supported | Async getter. |
| `Capture.startNewSession()` | Supported | Starts a new Capture session. |
| `Capture.createTemporaryDeviceCode()` | Supported | Useful for streaming logs from a test device. |
| `Capture.getSdkStatus()` | Supported | Returns SDK status information. |
| `Capture.addField(...)` | Supported | Adds a persistent field. |
| `Capture.removeField(...)` | Supported | Removes a persistent field. |
| `Capture.startSpan(...)` | Supported | Basic span support. |
| `Capture.endSpan(...)` | Supported | Ends a span with success/failure. |

### Not Supported Yet

| Area | Reason |
| :---- | :---- |
| Session Replay on iOS | Missing finalized native bridge. The Dart-side Flutter wireframe capture logic is expected to be reused. |
| Dart exception reporting | Dart/Flutter errors do not automatically become native crashes. A dedicated Flutter error bridge is needed. |
| Dart `error` / `StackTrace` parameter on `logError` | The current logging API supports message \+ string fields only. |
| Network request/response logging APIs | Native `HttpRequestInfo` / `HttpResponseInfo` equivalents are not exposed in Flutter yet. |
| Feature flag exposure APIs | Not exposed yet but easy addition |
| Entity ID API | Not exposed yet but easy addition |
| App launch TTI API | Not exposed yet but easy addition |
| Sleep mode API | Not exposed yet but easy addition |
| Previous run info API | Not exposed yet but easy addition |
| Full native start configuration | Field providers, date provider, and full native `Configuration` are not exposed yet. |

## Customer Test Instructions

1. Add the dependency to the Flutter app:

```
dependencies:
  capture_flutter:
    git:
      url: https://github.com/bitdriftlabs/capture-sdk.git
      ref: flutter-prototype-0.0.1
      path: platform/capture_flutter
```

2. Initialize Capture:

```
import 'package:capture_flutter/capture_flutter.dart';

await Capture.start(
  apiKey: 'YOUR_API_KEY',
  apiUrl: 'https://api.bitdrift.io',
  enableSessionReplay: true, // For now only effective to Android
);
```

3. Log events:

```
await Capture.logInfo(
  'User tapped checkout',
  fields: {
    'screen': 'checkout',
    'source': 'flutter_alpha_test',
  },
);
```

4. Log screen views:

```
await Capture.logScreenView('Checkout Screen');
```

5. Get session details:

```
final sessionId = await Capture.sessionId;
final sessionUrl = await Capture.sessionUrl;
```

6. Generate a temporary device code:

```
final deviceCode = await Capture.createTemporaryDeviceCode();
```

