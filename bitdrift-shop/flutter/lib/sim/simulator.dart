import 'dart:math';
import 'package:flutter/widgets.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../crash.dart';
import '../generated/journey.dart';
import '../generated/spec.dart';
import 'journey_engine.dart';

/// Persona presets (spec/personas.yaml ids).
enum SimVariant {
  control('control'),
  variantA('variant_a'),
  variantB('variant_b');

  const SimVariant(this.id);
  final String id;
}

String simVariantLabel(SimVariant v) => switch (v) {
      SimVariant.control => 'Control',
      SimVariant.variantA => 'Variant A',
      SimVariant.variantB => 'Variant B',
    };

/// Journey driver: runs the shared journey (spec/journey.yaml) through [JourneyEngine] and
/// maps each step onto this app: the root navigator, [Api], and the [Bd] wrapper (which
/// also feeds the harness recorder). The alpha SDK has no ANR / force-quit bridge, so
/// those toggles are never passed. Crash loop: when the loop property is set
/// (scripts/crash-loop.sh) the `crash_loop` toggle is on and [fireCrash] raises a random
/// native-signal crash at the journey point the engine chose. Screen views are logged by
/// the screens themselves, not here.
class Simulator extends ChangeNotifier implements JourneyAdapter {
  final GlobalKey<NavigatorState> _navKey;
  late final JourneyEngine _engine = JourneyEngine(specJourneyJson, this);

  SimVariant _variant = SimVariant.control;
  bool _running = false;
  bool _infinite = false;
  int _currentRun = 0;
  int _totalRuns = 0;
  int _simSeed = 0;
  bool _crashLoop = false;
  bool _cancelled = false;

  Simulator(this._navKey);

  // ── UI-facing state ─────────────────────────────────────────────────────
  bool get running => _running;
  bool get infinite => _infinite;
  int get currentRun => _currentRun;
  int get totalRuns => _totalRuns;
  SimVariant get variant => _variant;

  void setVariant(SimVariant v) => _variant = v;

  /// Runs [runs] journeys (or until stopped when [infinite]). [seed] (0..2^31-1) fixes the
  /// simulation's journeys; without one each simulation draws a random seed.
  Future<void> start({int runs = 3, bool infinite = false, int? seed}) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    _infinite = infinite;
    _totalRuns = infinite ? 0 : runs;
    _currentRun = 0;
    _simSeed = (seed ?? Random().nextInt(1 << 31)) & 0x7FFFFFFF;
    _crashLoop = await Crash.loopActive();
    notifyListeners();

    await Bd.info(
      infinite ? SpecEvents.infiniteSimulationStart : SpecEvents.simulationStart,
      fields: infinite ? null : {SpecFields.totalRuns: '$runs'},
    );
    try {
      while (_running && (_infinite || _currentRun < _totalRuns)) {
        _currentRun++;
        notifyListeners();
        final outcome = await _engine.run(
            _variant.id, _currentRun, _simSeed, {if (_crashLoop) 'crash_loop'}, _infinite);
        debugPrint('journey $_currentRun (${simVariantLabel(_variant)}, seed=$_simSeed): $outcome');
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } finally {
      _running = false;
      notifyListeners();
      // If a journey was interrupted by stop(), the stack may not be back at
      // the welcome screen — bring it back so the app is in a clean state.
      await _resetStack();
      if (_cancelled) {
        await Bd.info(SpecEvents.simulationCancelled, fields: {
          SpecFields.completedRuns: '${_currentRun - 1}',
          SpecFields.totalRuns: '$_totalRuns',
        });
      } else {
        await Bd.info(
          infinite ? SpecEvents.infiniteSimulationEnd : SpecEvents.simulationEnd,
          fields: {SpecFields.totalRuns: '$_currentRun'},
        );
      }
    }
  }

  void stop() {
    _cancelled = _running;
    _running = false;
    notifyListeners();
  }

  // ── JourneyAdapter ──────────────────────────────────────────────────────
  @override
  bool isCancelled() => !_running;

  @override
  Future<void> startNewSession() => Bd.startNewSession();

  @override
  Future<void> applyExposures(String persona) async {
    // The alpha SDK has no exposure API: flags are `ff_*` global fields only.
    final flags = switch (_variant) {
      SimVariant.control => {
          SpecFlags.checkoutFlow: SpecFlags.checkoutFlowControl,
          SpecFlags.paymentUi: SpecFlags.paymentUiControl,
          SpecFlags.cartAbandonRate: SpecFlags.cartAbandonRateControl,
          SpecFlags.paymentAndroidPay: SpecFlags.paymentAndroidPayControl,
        },
      SimVariant.variantA => {
          SpecFlags.checkoutFlow: SpecFlags.checkoutFlowVariantA,
          SpecFlags.paymentUi: SpecFlags.paymentUiVariantA,
          SpecFlags.cartAbandonRate: SpecFlags.cartAbandonRateVariantA,
          SpecFlags.paymentAndroidPay: SpecFlags.paymentAndroidPayVariantA,
        },
      SimVariant.variantB => {
          SpecFlags.checkoutFlow: SpecFlags.checkoutFlowVariantB,
          SpecFlags.paymentUi: SpecFlags.paymentUiVariantB,
          SpecFlags.cartAbandonRate: SpecFlags.cartAbandonRateVariantB,
          SpecFlags.paymentAndroidPay: SpecFlags.paymentAndroidPayVariantB,
        },
    };
    for (final e in flags.entries) {
      await Bd.setFlag(e.key, e.value);
    }
    await Bd.field(SpecFields.ffVariant, simVariantLabel(_variant));
    await Bd.info(SpecEvents.featureFlagExposureSet);
  }

  @override
  Future<void> setEntity(String entity) => Bd.entity(entity);

  @override
  Future<void> delay(int ms) => Future.delayed(Duration(milliseconds: ms));

  @override
  Future<void> navigate(String screen, Map<String, String> args) async {
    final spec = SpecScreen.values.firstWhere((s) => s.id == screen);
    if (spec == SpecScreen.welcome) return _resetStack();
    try {
      _navKey.currentState?.pushNamed(spec.platformRoute, arguments: _routeArgs(spec, args));
    } catch (e) {
      // Debug-only navigation failure; no telemetry (spec D-EVT-F13).
      debugPrint('sim navigation to ${spec.platformRoute} failed: $e');
    }
  }

  /// The route-argument shape each screen reads from `ModalRoute.settings.arguments`.
  Object? _routeArgs(SpecScreen s, Map<String, String> a) => switch (s) {
        SpecScreen.productDetail || SpecScreen.reviews || SpecScreen.wishlist => a['productId'],
        SpecScreen.categoryBrowse => a['category'],
        SpecScreen.confirmation => a['orderId'],
        SpecScreen.paymentCard ||
        SpecScreen.paymentApplePay ||
        SpecScreen.paymentPaypal ||
        SpecScreen.paymentAndroidPay =>
          {'session': a['checkoutSession']},
        SpecScreen.paymentFailed => {
            'method': _methodKey(a['paymentMethod'] ?? ''),
            'session': a['checkoutSession'],
          },
        _ => null,
      };

  @override
  Future<Map<String, dynamic>?> callApi(String endpoint, Map<String, String> args) async {
    String a(String k) => args[k] ?? '';
    try {
      return await switch (endpoint) {
        'welcome' => Api.welcome(),
        'browse' => Api.browse(),
        'search' => Api.search(a('q')),
        'featured' => Api.featured(),
        'categories' => Api.categories(),
        'category_products' => Api.categoryProducts(a('category')),
        'product' => Api.product(a('id')),
        'reviews' => Api.reviews(a('id')),
        'cart_get' => Api.cart(),
        'cart_add' => Api.addToCart(a('product_id'), int.tryParse(a('quantity')) ?? 1),
        'cart_delete' => Api.removeCartItem(a('id')),
        'wishlist_add' => Api.wishlist(a('product_id')),
        'checkout_guest' => Api.checkoutGuest(),
        'checkout_signin' => Api.checkoutSignIn(),
        'pay_card' => Api.payCard(a('checkout_session'), args['card_last4'] ?? '4242'),
        'pay_apple_pay' => Api.payApplePay(a('checkout_session')),
        'pay_paypal' => Api.payPayPal(a('checkout_session')),
        'pay_android_pay' => Api.payAndroidPay(a('checkout_session')),
        'confirmation' => Api.confirmation(a('id')),
        _ => throw StateError('unknown endpoint $endpoint'),
      };
    } catch (_) {
      return null; // the client already logged the failure
    }
  }

  @override
  Future<void> log(String level, String event, Map<String, String> fields) {
    final f = fields.isEmpty ? null : fields;
    return switch (level) {
      'error' => Bd.error(event, fields: f),
      'warning' => Bd.warning(event, fields: f),
      'debug' => Bd.debug(event, fields: f),
      'trace' => Bd.trace(event, fields: f),
      _ => Bd.info(event, fields: f),
    };
  }

  // The alpha SDK's startSpan has no parent argument: the parent only reaches the recorder.
  @override
  Future<Object?> startSpan(String name, Object? parent, Map<String, String> fields) =>
      Bd.startSpan(name, fields: fields.isEmpty ? null : fields, parent: parent as SpanHandle?);

  @override
  Future<void> endSpan(Object handle, String result, Map<String, String> fields) =>
      (handle as SpanHandle).end(result: result, fields: fields.isEmpty ? null : fields);

  @override
  Future<void> addField(String key, String value) => Bd.field(key, value);

  @override
  Future<void> injectFault(String id) async {} // no fault toggles are ever passed

  @override
  Future<void> fireCrash() async {
    await Crash.injectRandom(); // the engine already set crash_journey_point
  }

  // ── small helpers ───────────────────────────────────────────────────────
  Future<void> _resetStack() async {
    final nav = _navKey.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    await Future.delayed(const Duration(milliseconds: 300)); // let the pop transitions finish
  }
}

/// Internal payment-method key for a telemetry value (inverse of [paymentMethodLabel]).
String _methodKey(String label) => switch (label) {
      'apple_pay' => 'applePay',
      'android_pay' => 'androidPay',
      _ => label,
    };

/// Telemetry value for a Flutter payment-method key (spec: card, apple_pay, paypal, android_pay).
String paymentMethodLabel(String method) => switch (method) {
      'applePay' => 'apple_pay',
      'androidPay' => 'android_pay',
      _ => method,
    };

/// Route name for a payment method (shared with the UI).
String paymentRoute(String method) => switch (method) {
      'card' => 'payment_card',
      'applePay' => 'payment_applepay',
      'paypal' => 'payment_paypal',
      _ => 'payment_androidpay',
    };

/// Exposes the shared [Simulator] to the widget tree.
class SimulatorScope extends InheritedWidget {
  final Simulator sim;
  const SimulatorScope({super.key, required this.sim, required super.child});

  static Simulator of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SimulatorScope>();
    assert(scope != null, 'SimulatorScope not found above this widget');
    return scope!.sim;
  }

  @override
  bool updateShouldNotify(covariant SimulatorScope old) => old.sim != sim;
}
