import 'package:capture_flutter/capture_flutter.dart';

import '../config.dart';

/// Thin, single-seam wrapper over the alpha `capture_flutter` SDK.
///
/// Everything the app logs flows through here so the alpha API shape is
/// isolated in one place. Every call is **best-effort**: the alpha SDK is not
/// guaranteed to behave, and a failing plugin must never crash the app or a
/// screen's `initState`, so all platform calls swallow errors.
class Bd {
  static Future<void> _run(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // best-effort: the app keeps working even if the plugin misbehaves.
    }
  }

  /// Start the SDK with an activity-based session and Android session replay.
  static Future<bool> start({bool sessionReplay = true}) async {
    try {
      return await Capture.start(
        apiKey: Config.bitdriftApiKey,
        sessionStrategy: SessionStrategy.activityBased,
        apiUrl: Config.bitdriftApiUrl,
        enableSessionReplay: sessionReplay,
      );
    } catch (_) {
      return false;
    }
  }

  // -- logging ------------------------------------------------------------
  static Future<void> trace(String m, {Map<String, String>? fields}) =>
      _run(() => Capture.logTrace(m, fields: fields));
  static Future<void> debug(String m, {Map<String, String>? fields}) =>
      _run(() => Capture.logDebug(m, fields: fields));
  static Future<void> info(String m, {Map<String, String>? fields}) =>
      _run(() => Capture.logInfo(m, fields: fields));
  static Future<void> warning(String m, {Map<String, String>? fields}) =>
      _run(() => Capture.logWarning(m, fields: fields));
  static Future<void> error(String m, {Map<String, String>? fields}) =>
      _run(() => Capture.logError(m, fields: fields));

  /// Log a screen view.
  static Future<void> screenView(String name) =>
      _run(() => Capture.logScreenView(name));

  // -- fields -------------------------------------------------------------
  static Future<void> field(String k, String v) =>
      _run(() => Capture.addField(k, v));
  static Future<void> removeField(String k) => _run(() => Capture.removeField(k));

  /// Alpha has no first-class feature-flag exposure API; record as an `ff_*`
  /// global field so it stays filterable (matches the other demos).
  static Future<void> setFlag(String name, String value) =>
      _run(() => Capture.addField('ff_$name', value));

  /// Sets the entity identifier used for backend correlation with this device.
  static Future<void> entity(String id) =>
      _run(() => Capture.setEntityId(id));

  /// Clears the entity identifier used for backend correlation with this device.
  static Future<void> clearEntity() => _run(Capture.clearEntityId);

  // -- session ------------------------------------------------------------
  static Future<String?> get sessionId async {
    try {
      return await Capture.sessionId;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> get sessionUrl async {
    try {
      return await Capture.sessionUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> get deviceId async {
    try {
      return await Capture.deviceId;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> createDeviceCode() async {
    try {
      return await Capture.createTemporaryDeviceCode();
    } catch (_) {
      return null;
    }
  }

  static Future<void> startNewSession() => _run(() => Capture.startNewSession());

  static Future<Map<String, dynamic>?> getSdkStatus() async {
    try {
      return await Capture.getSdkStatus();
    } catch (_) {
      return null;
    }
  }

  // -- spans --------------------------------------------------------------
  static Future<SpanHandle?> startSpan(
    String name, {
    Map<String, String>? fields,
  }) async {
    try {
      final s = await Capture.startSpan(name, fields: fields);
      return s == null ? null : SpanHandle(s);
    } catch (_) {
      return null;
    }
  }

  /// Emit a start/end log pair for work that already completed (cold start /
  /// TTI). The alpha SDK has no TTI API, so we reproduce the same signal the
  /// other demos emit with paired logs.
  static Future<void> logCompletedSpan(
    String name,
    int durationMs, {
    Map<String, String>? fields,
  }) async {
    final id = 'span_${DateTime.now().microsecondsSinceEpoch}';
    final base = <String, String>{...?fields};
    await _run(() => Capture.logInfo(
          name,
          fields: {...base, '_span_id': id, '_span_type': 'start'},
        ));
    await _run(() => Capture.logInfo(
          name,
          fields: {
            ...base,
            '_span_id': id,
            '_span_type': 'end',
            '_result': 'success',
            '_duration_ms': '$durationMs',
          },
        ));
  }
}

/// Ergonomic wrapper around the alpha `Span`.
class SpanHandle {
  final Span span;
  SpanHandle(this.span);
  Future<void> end({bool success = true}) async {
    try {
      await Capture.endSpan(span, success: success);
    } catch (_) {
      // best-effort
    }
  }
}
