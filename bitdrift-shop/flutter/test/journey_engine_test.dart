import 'dart:convert';
import 'dart:io';

import 'package:bitdrift_shop_flutter/generated/journey.dart';
import 'package:bitdrift_shop_flutter/sim/journey_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays tools/journey/golden.json (written by the Python reference engine from
/// spec/journey.yaml): for every seeded case the Dart engine must make exactly the same
/// adapter calls, in the same order, as tools/journey/engine.py.
class _TraceAdapter implements JourneyAdapter {
  final Map<String, dynamic> fixture;
  final List<String> lines = [];
  _TraceAdapter(this.fixture);

  static String _f(Map<String, String> m) =>
      '{${(m.keys.toList()..sort()).map((k) => '$k=${m[k]}').join(', ')}}';

  @override
  bool isCancelled() => false;
  @override
  Future<void> startNewSession() async => lines.add('new_session');
  @override
  Future<void> applyExposures(String persona) async => lines.add('exposures $persona');
  @override
  Future<void> setEntity(String entity) async => lines.add('entity $entity');
  @override
  Future<void> delay(int ms) async => lines.add('wait $ms');
  @override
  Future<void> navigate(String screen, Map<String, String> args) async =>
      lines.add('nav $screen ${_f(args)}');
  @override
  Future<Map<String, dynamic>?> callApi(String endpoint, Map<String, String> args) async {
    lines.add('api $endpoint ${_f(args)}');
    if (((fixture['fail'] as List?) ?? const []).contains(endpoint)) return null;
    return (fixture[endpoint] as Map<String, dynamic>?) ?? {};
  }

  @override
  Future<void> log(String level, String event, Map<String, String> fields) async =>
      lines.add('log $level $event ${_f(fields)}');
  @override
  Future<Object?> startSpan(String name, Object? parent, Map<String, String> fields) async {
    lines.add('span_start $name ${parent ?? '-'} ${_f(fields)}');
    return name;
  }

  @override
  Future<void> endSpan(Object handle, String result, Map<String, String> fields) async =>
      lines.add('span_end $handle $result ${_f(fields)}');
  @override
  Future<void> addField(String key, String value) async => lines.add('field $key=$value');
  @override
  Future<void> injectFault(String id) async => lines.add('fault $id');
  @override
  Future<void> fireCrash() async => lines.add('crash');
}

void main() {
  test('mulberry32 matches the reference', () {
    final rng = JourneyRng(42);
    expect(rng.next(), 0.6011037519201636);
    expect(rng.next(), 0.44829055899754167);
    expect(JourneyRng.journeySeed(2147483647, 4), (2147483647 * 1000003 + 4) & 0xFFFFFFFF);
  });

  test('replays golden traces', () async {
    final golden = jsonDecode(File('../tools/journey/golden.json').readAsStringSync())
        as Map<String, dynamic>;
    final cases = golden['cases'] as List;
    expect(cases, isNotEmpty);
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final adapter = _TraceAdapter(golden['fixture'] as Map<String, dynamic>);
      final engine = JourneyEngine(specJourneyJson, adapter);
      final toggles = Set<String>.from(c['toggles'] as List);
      for (var run = 1; run <= (c['runs'] as int); run++) {
        final outcome = await engine.run(
            c['persona'] as String, run, c['sim_seed'] as int, toggles, c['infinite'] as bool);
        adapter.lines.add('outcome $outcome');
      }
      final want = (c['trace'] as List).cast<String>();
      final got = adapter.lines;
      var diff = -1;
      for (var i = 0; i < want.length && diff < 0; i++) {
        if (i >= got.length || want[i] != got[i]) diff = i;
      }
      if (diff < 0 && got.length != want.length) diff = want.length;
      expect(diff, -1,
          reason: 'case ${c['name']}: first difference at line $diff: want '
              "'${diff >= 0 && diff < want.length ? want[diff] : null}', "
              "got '${diff >= 0 && diff < got.length ? got[diff] : null}'");
    }
  });
}
