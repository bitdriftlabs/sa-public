import 'dart:convert';

/// The platform half of the shared journey: everything the interpreter needs from the
/// app. [Simulator] implements it against the SDK, the navigator and [Api]; the unit
/// test implements it as a trace recorder (see tools/journey/golden.json).
abstract class JourneyAdapter {
  bool isCancelled();
  Future<void> startNewSession();
  Future<void> applyExposures(String persona);
  Future<void> setEntity(String entity);
  Future<void> delay(int ms);
  Future<void> navigate(String screen, Map<String, String> args);

  /// The endpoint's JSON response, or null if the call failed.
  Future<Map<String, dynamic>?> callApi(String endpoint, Map<String, String> args);
  Future<void> log(String level, String event, Map<String, String> fields);

  /// Returns a handle passed back to [endSpan] (and as a child's `parent`), or null.
  Future<Object?> startSpan(String name, Object? parent, Map<String, String> fields);
  Future<void> endSpan(Object handle, String result, Map<String, String> fields);
  Future<void> addField(String key, String value);

  /// Perform the fault (may never return).
  Future<void> injectFault(String id);

  /// Fire the next crash-loop crash (log about_to_crash, then crash; may never return).
  Future<void> fireCrash();
}

const int _m32 = 0xFFFFFFFF;

/// 32-bit multiply without relying on 64-bit overflow: split `a` into 16-bit halves.
int _imul(int a, int b) =>
    ((a & 0xFFFF) * b + ((((a >>> 16) * b) & 0xFFFF) << 16)) & _m32;

/// mulberry32, bit-identical to tools/journey/engine.py and the other apps' engines.
class JourneyRng {
  int _s;
  JourneyRng(int seed) : _s = seed & _m32;

  double next() {
    _s = (_s + 0x6D2B79F5) & _m32;
    var t = _s;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = ((t + _imul(t ^ (t >>> 7), t | 61)) & _m32) ^ t;
    return ((t ^ (t >>> 14)) & _m32) / 4294967296.0;
  }

  /// journey_seed = (sim_seed * 1000003 + run) mod 2^32, 0 <= sim_seed < 2^31.
  static int journeySeed(int simSeed, int run) => (simSeed * 1000003 + run) & _m32;
}

class _Stop implements Exception {
  final String outcome;
  _Stop(this.outcome);
}

final RegExp _template = RegExp(r'\{([A-Za-z0-9_.]+)\}');

/// Interprets spec/journey.yaml (compiled into `specJourneyJson`). A line-for-line port of
/// tools/journey/engine.py: change the journey there and in the YAML, never here. One engine
/// per simulator, because the fault counters persist across journeys.
class JourneyEngine {
  final Map<String, dynamic> _b;
  final JourneyAdapter _a;
  final Map<String, int> _eligible = {};

  String _persona = '';
  Set<String> _toggles = const {};
  bool _infinite = false;
  JourneyRng _rng = JourneyRng(0);
  final Map<String, Object> _vars = {};
  final Map<String, Object> _spans = {};
  bool _crashFired = false;

  JourneyEngine(String bundleJson, this._a)
      : _b = jsonDecode(bundleJson) as Map<String, dynamic>;

  /// Runs one journey; returns its outcome (completed, cart_abandoned, fault, crash, cancelled, ...).
  Future<String> run(String persona, int run, int simSeed, Set<String> toggles, bool infinite) async {
    _persona = persona;
    _toggles = toggles;
    _infinite = infinite;
    _rng = JourneyRng(JourneyRng.journeySeed(simSeed, run));
    _vars
      ..clear()
      ..addAll(Map<String, Object>.from(_b['personas'][persona]['vars'] as Map))
      ..['run'] = '$run'
      ..['sim_seed'] = '$simSeed'
      ..['persona'] = persona;
    _spans.clear();
    _crashFired = false;
    try {
      await _block(_b['journey'] as List);
    } on _Stop catch (s) {
      return s.outcome;
    }
    return 'completed';
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String _t(String s) => s.replaceAllMapped(_template, (m) {
        final v = _vars[m.group(1)];
        if (v is List) return '${v.length}';
        return (v as String?) ?? '';
      });

  Map<String, String> _tm(Object? o) =>
      {for (final e in (o as Map).entries) e.key as String: _t(e.value as String)};

  List<String> _lst(String name) {
    final v = _vars[name];
    if (v is List<String>) return v;
    final fresh = <String>[];
    _vars[name] = fresh;
    return fresh;
  }

  String _str(String name) => (_vars[name] as String?) ?? '';

  List<String> _strings(Object? a) => [for (final x in a as List) x as String];

  double _p(Map chance) {
    var table = chance['default'] as Map;
    final by = chance['by'];
    if (by != null) {
      table = ((chance['cases'] as Map)[_str(by as String)] as Map?) ?? table;
    }
    return (table[_persona] as num).toDouble();
  }

  /// Draws for `chance` first (always), then checks every other condition.
  bool _condOk(Map op) {
    var ok = true;
    if (op.containsKey('chance')) ok = _rng.next() < _p(op['chance'] as Map);
    if (op.containsKey('toggle') && !_toggles.contains(op['toggle'])) ok = false;
    if (op.containsKey('not_toggle') && _toggles.contains(op['not_toggle'])) ok = false;
    if (op.containsKey('eq')) {
      final eq = op['eq'] as List;
      if (_str(eq[0] as String) != eq[1]) ok = false;
    }
    if (op.containsKey('min_len')) {
      final ml = op['min_len'] as List;
      if (_lst(ml[0] as String).length < (ml[1] as num)) ok = false;
    }
    return ok;
  }

  // ── interpreter ──────────────────────────────────────────────────────────

  Future<void> _block(List ops) async {
    for (final op in ops) {
      if (_a.isCancelled()) throw _Stop('cancelled');
      await _step(op as Map<String, dynamic>);
    }
  }

  Future<void> _step(Map<String, dynamic> op) async {
    switch (op['op'] as String) {
      case 'new_session':
        await _a.startNewSession();
      case 'exposures':
        await _a.applyExposures(_persona);
      case 'entity':
        final ents = _strings(_b['entities']);
        final e = ents[(int.parse(_str('run')) - 1) % ents.length];
        _vars['entity'] = e;
        await _a.setEntity(e);
      case 'wait':
        await _a.delay((op['ms'] as num).toInt());
      case 'nav':
        await _a.navigate(op['screen'] as String, _tm(op['args']));
        await _a.delay((_b['step_delay_ms'] as num).toInt());
      case 'api':
        final res = await _a.callApi(op['endpoint'] as String, _tm(op['args']));
        for (final s in op['save'] as List) {
          final v = res?[s['key']];
          if (s.containsKey('item')) {
            final item = s['item'];
            final items = <String>[
              if (v is List)
                for (final x in v)
                  if (x is Map && x.containsKey(item)) '${x[item]}',
            ];
            _vars[s['var'] as String] = items.isNotEmpty ? items : _strings(s['default']);
          } else {
            _vars[s['var'] as String] =
                (v == null || '$v'.isEmpty) ? _t(s['default'] as String) : '$v';
          }
        }
      case 'log':
        await _a.log(op['level'] as String, op['event'] as String, _tm(op['fields']));
      case 'span_start':
        await _startSpan(op);
      case 'span_end':
        final h = _spans.remove(op['span']);
        if (h != null) await _a.endSpan(h, op['result'] as String, _tm(op['fields']));
      case 'span':
        // Scoped span: success when the block finishes or the journey stops inside it
        // (fault / crash / outcome); canceled when the run is cancelled.
        await _startSpan(op);
        var result = 'canceled';
        try {
          await _block(op['do'] as List);
          result = 'success';
        } on _Stop catch (s) {
          result = s.outcome == 'cancelled' ? 'canceled' : 'success';
          rethrow;
        } finally {
          final h = _spans.remove(op['span']);
          if (h != null) await _a.endSpan(h, result, const {});
        }
      case 'set':
        for (final e in (op['values'] as Map).entries) {
          _vars[e.key as String] = _t(e.value as String);
        }
      case 'pick':
        var items = op.containsKey('values')
            ? _strings(op['values'])
            : List<String>.of(_lst(op['from'] as String));
        if (op.containsKey('exclude')) {
          final ex = _t(op['exclude'] as String);
          items = items.where((x) => x != ex).toList();
        }
        final r = _rng.next();
        _vars[op['into'] as String] = items.isEmpty ? '' : items[(r * items.length).floor()];
      case 'rand_int':
        final lo = (op['min'] as num).toInt();
        final hi = (op['max'] as num).toInt();
        _vars[op['into'] as String] = '${lo + (_rng.next() * (hi - lo + 1)).floor()}';
      case 'choose':
        final weights = (op['weights'] as Map)[_persona] as List;
        var total = 0.0;
        for (final w in weights) {
          total += (w[1] as num).toDouble();
        }
        final x = _rng.next() * total;
        var pick = weights.last[0] as String;
        var acc = 0.0;
        for (final w in weights) {
          acc += (w[1] as num).toDouble();
          if (x < acc) {
            pick = w[0] as String;
            break;
          }
        }
        if (op['into'] != null) _vars[op['into'] as String] = pick;
        await _block(((op['branches'] as Map)[pick] as List?) ?? const []);
      case 'if':
        await _block((_condOk(op) ? op['then'] : op['else']) as List);
      case 'switch':
        await _block(((op['cases'] as Map)[_str(op['var'] as String)] ?? op['default']) as List);
      case 'repeat':
        final range = (op['ranges'] as Map)[_persona] as List;
        final lo = (range[0] as num).toInt();
        final hi = (range[1] as num).toInt();
        final n = lo + (_rng.next() * (hi - lo + 1)).floor();
        for (var i = 0; i < n; i++) {
          await _block(op['do'] as List);
        }
      case 'for_each':
        for (final item in List<String>.of(_lst(op['list'] as String))) {
          _vars[op['as'] as String] = item;
          await _block(op['do'] as List);
        }
      case 'list_add':
        _lst(op['list'] as String).add(_t(op['value'] as String));
      case 'list_remove_random':
        final items = _lst(op['list'] as String);
        final r = _rng.next();
        _vars[op['into'] as String] = items.isEmpty ? '' : items.removeAt((r * items.length).floor());
      case 'list_clear':
        _lst(op['list'] as String).clear();
      case 'last':
        final items = _lst(op['list'] as String);
        _vars[op['into'] as String] = items.isNotEmpty ? items.last : _t(op['default'] as String);
      case 'fault':
        await _fault(op);
      case 'crash_point':
        final point = op['point'] as String;
        if (_toggles.contains('crash_loop') &&
            !_crashFired &&
            (point == _vars['crash_point'] || point == 'confirmation')) {
          _crashFired = true;
          await _a.addField('crash_journey_point', point);
          await _a.fireCrash();
          throw _Stop('crash');
        }
      case 'stop':
        throw _Stop(op['outcome'] as String);
      default:
        throw StateError('unknown journey op ${op['op']}');
    }
  }

  Future<void> _startSpan(Map op) async {
    final parent = op['parent'] == null ? null : _spans[op['parent']];
    final h = await _a.startSpan(op['span'] as String, parent, _tm(op['fields']));
    if (h != null) _spans[op['span'] as String] = h;
  }

  Future<void> _fault(Map op) async {
    final id = op['fault'] as String;
    if (!_toggles.contains(id)) return;
    final n = (_eligible[id] ?? 0) + 1;
    _eligible[id] = n;
    final randomHit = _rng.next() < (op['probability'] as num).toDouble();
    final forced = _infinite && n >= (op['force_after'] as num).toInt();
    if (!randomHit && !forced) return;
    _eligible[id] = 0;
    _vars['trigger_mode'] = randomHit ? 'random' : 'forced_infinite';
    await _a.log(op['level'] as String, op['event'] as String, _tm(op['fields']));
    await _a.injectFault(id);
    throw _Stop('fault');
  }
}
