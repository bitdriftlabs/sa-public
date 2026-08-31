import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Build-time configuration.
///
/// Values are injected at compile time with `--dart-define=KEY=VALUE`
/// (see `scripts/run-app.sh` and `env.example`). Nothing here reads a runtime
/// `.env` file.
class Config {
  // Kept in step with the other shop demos so sessions slice identically.
  static const String appVersion = '5.0';
  static const String appVariant = 'sdk-demo';
  static const String platform = 'flutter';

  // ── bitdrift ────────────────────────────────────────────────────────────
  static final String bitdriftApiKey =
      String.fromEnvironment('BITDRIFT_SDK_KEY', defaultValue: '');
  static final String bitdriftApiUrl = String.fromEnvironment(
    'BITDRIFT_API_HOST',
    defaultValue: 'https://api.bitdrift.io',
  );

  // ── backend ─────────────────────────────────────────────────────────────
  static final int backendPort = int.tryParse(
    String.fromEnvironment('BACKEND_PORT', defaultValue: '5173'),
  ) ??
      5173;

  /// Android reaches the host loopback via the special alias 10.0.2.2; other
  /// platforms share the host network.
  static String get _backendHost =>
      defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : '127.0.0.1';

  /// Base URL for all shop API calls, from the running app's point of view.
  static String get backendBaseUrl => 'http://${_backendHost}:$backendPort/api';

  /// Resolve a product image URL that may be relative to the backend host.
  static String resolveImageUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = 'http://$_backendHost:$backendPort';
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }
}
