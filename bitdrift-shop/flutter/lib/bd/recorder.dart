import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Record mode for the test harness (debug builds only). The app can't write files without a
/// plugin and can't take launch arguments without native code, so it talks to the local collector
/// that `test.sh` starts (tools/conformance/collector.py):
///   GET  /config  -> {runs, seed, persona}: when answered, the app autoruns and records
///   POST /record  -> JSONL records, same shapes as the native recorders
/// With no collector running the config request fails fast and the app behaves as before.
/// Set by `test.sh` through the start scripts, for builds where `kDebugMode` is false (Android release).
const bool _harness = bool.fromEnvironment('BDSHOP_HARNESS');

class Recorder {
  static final String _host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
  static const int _port = 5599;
  static bool _recording = false;
  static final List<String> _queue = [];
  static Timer? _timer;
  static Future<void> _flushing = Future.value();

  // Spans started but not yet ended, so a recording that begins mid-run can carry them over.
  static final Map<String, _Open> _open = {};

  /// Debug builds only: ask the collector whether to autorun. Null when it isn't there.
  static Future<({int runs, int seed, String persona})?> fetchConfig() async {
    if (!kDebugMode && !_harness) return null;
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
    try {
      final req = await client.getUrl(Uri.parse('http://$_host:$_port/config'));
      final res = await req.close().timeout(const Duration(milliseconds: 2500));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
      return (
        runs: (body['runs'] as num).toInt(),
        seed: (body['seed'] as num?)?.toInt() ?? 0,
        persona: (body['persona'] ?? 'control').toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static void start() {
    _recording = true;
    _open.forEach((id, s) => _enqueue({
          'kind': 'span_start',
          'id': id,
          'name': s.name,
          'parent': null,
          'carried': true,
          'fields': s.fields,
        }));
  }

  static void _enqueue(Map<String, Object?> rec) {
    _queue.add(jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, ...rec}));
    _timer ??= Timer(const Duration(milliseconds: 100), () {
      _timer = null;
      flush();
    });
  }

  static Future<void> flush() {
    _flushing = _flushing.then((_) async {
      if (_queue.isEmpty) return;
      final body = _queue.join('\n');
      _queue.clear();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      try {
        final req = await client.postUrl(Uri.parse('http://$_host:$_port/record'));
        final bytes = utf8.encode(body);
        req.headers.contentType = ContentType.text;
        req.contentLength = bytes.length; // the collector reads by Content-Length, not chunked
        req.add(bytes);
        await (await req.close()).drain<void>();
      } catch (_) {
        // The collector going away must never affect the app.
      } finally {
        client.close(force: true);
      }
    });
    return _flushing;
  }

  static const _spanKeys = {'_span_id', '_span_type', '_result', '_duration_ms'};

  static Map<String, String>? _clean(Map<String, String>? f) {
    if (f == null) return null;
    final out = {for (final e in f.entries) if (!_spanKeys.contains(e.key)) e.key: e.value};
    return out.isEmpty ? null : out;
  }

  /// One hook for every log (and the paired-log spans the Bd wrapper emits for cold start).
  static void log(String level, String message, Map<String, String>? fields) {
    final type = fields?['_span_type'];
    final id = fields?['_span_id'];
    if (type == 'start' && id != null) {
      _open[id] = _Open(message, _clean(fields));
      if (_recording) {
        _enqueue({'kind': 'span_start', 'id': id, 'name': message, 'parent': null, 'fields': _clean(fields)});
      }
      return;
    }
    if (type == 'end' && id != null) {
      _open.remove(id);
      if (_recording) {
        _enqueue({'kind': 'span_end', 'id': id, 'name': message, 'result': fields?['_result'] ?? 'success', 'fields': _clean(fields)});
      }
      return;
    }
    if (_recording) {
      _enqueue({'kind': 'log', 'level': level, 'message': message, 'fields': _clean(fields)});
    }
  }

  static void screen(String name) {
    if (_recording) _enqueue({'kind': 'screen', 'name': name});
  }

  /// [parent] is the logical parent span's id: the alpha SDK cannot parent spans, but the
  /// recording still carries the spec's parent so conformance sees the span tree.
  static void spanStart(String id, String name, Map<String, String>? fields, {String? parent}) {
    _open[id] = _Open(name, fields);
    if (_recording) _enqueue({'kind': 'span_start', 'id': id, 'name': name, 'parent': parent, 'fields': fields});
  }

  static void spanEnd(String id, String name, String result, Map<String, String>? fields) {
    _open.remove(id);
    if (_recording) {
      _enqueue({'kind': 'span_end', 'id': id, 'name': name, 'result': result, 'fields': fields});
    }
  }
}

class _Open {
  final String name;
  final Map<String, String>? fields;
  _Open(this.name, this.fields);
}
