import 'dart:math';
import 'package:flutter/widgets.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../crash.dart';
import '../models/models.dart';


/// Persona presets — exact ports of the other demos' variant profiles.
enum SimVariant { control, variantA, variantB }

String simVariantLabel(SimVariant v) => switch (v) {
      SimVariant.control => 'Control',
      SimVariant.variantA => 'Variant A',
      SimVariant.variantB => 'Variant B',
    };

class SimProfile {
  final double discoveryBrowseMax;
  final double discoverySearchMax;
  final double reviewsProb;
  final double wishlistProb;
  final int extraCartMin;
  final int extraCartMax;
  final double guestProb;
  final double paymentCard;
  final double paymentApplePay;
  final double paymentPayPal;
  final double paymentAndroidPay;

  SimProfile({
    required this.discoveryBrowseMax,
    required this.discoverySearchMax,
    required this.reviewsProb,
    required this.wishlistProb,
    required this.extraCartMin,
    required this.extraCartMax,
    required this.guestProb,
    required this.paymentCard,
    required this.paymentApplePay,
    required this.paymentPayPal,
    required this.paymentAndroidPay,
  });
}

final Map<SimVariant, SimProfile> kProfiles = {
  // CONTROL — baseline, mostly uniform.
  SimVariant.control: SimProfile(
    discoveryBrowseMax: 0.3333,
    discoverySearchMax: 0.6666,
    reviewsProb: 0.5,
    wishlistProb: 0.4,
    extraCartMin: 1,
    extraCartMax: 3,
    guestProb: 0.5,
    paymentCard: 0.25,
    paymentApplePay: 0.25,
    paymentPayPal: 0.25,
    paymentAndroidPay: 0.25,
  ),
  // VARIANT A — digital native: guest + digital pay, more friction.
  SimVariant.variantA: SimProfile(
    discoveryBrowseMax: 0.4,
    discoverySearchMax: 0.85,
    reviewsProb: 0.1,
    wishlistProb: 0.05,
    extraCartMin: 0,
    extraCartMax: 1,
    guestProb: 0.95,
    paymentCard: 0.05,
    paymentApplePay: 0.4,
    paymentPayPal: 0.35,
    paymentAndroidPay: 0.2,
  ),
  // VARIANT B — deliberate shopper: signin + card, low friction.
  SimVariant.variantB: SimProfile(
    discoveryBrowseMax: 0.25,
    discoverySearchMax: 0.5,
    reviewsProb: 0.9,
    wishlistProb: 0.75,
    extraCartMin: 2,
    extraCartMax: 4,
    guestProb: 0.05,
    paymentCard: 0.95,
    paymentApplePay: 0.03,
    paymentPayPal: 0.02,
    paymentAndroidPay: 0.0,
  ),
};

const List<String> kEntities = [
  'Groucho', 'Harpo', 'Chico', 'Gummo', 'Zeppo',
  'Moe', 'Larry', 'Curly', 'Abbott', 'Costello',
];

const List<String> kSearchTerms = [
  'headphones', 'running shoes', 'coffee maker', 'yoga mat', 'backpack',
];

/// Simplified, variant-driven journey driver.
///
/// Best-effort port of the React Native simulation: it drives the real screens
/// (via the app's root navigator) while emitting the same structured bitdrift
/// signal — feature-flag fields, entity, and spans (journey / discovery /
/// checkout). Deliberately **omits** ANR and force-quit (the alpha SDK has no
/// Dart→native bridge for those). Crash loop: when the loop property is set
/// (scripts/crash-loop.sh), the journey crashes at payment with a random
/// native-signal crash, like the Android demo's "crash on payment". Screen
/// views are logged by the app's route observer, not here.
class Simulator extends ChangeNotifier {
  final GlobalKey<NavigatorState> _navKey;
  final Random _rng = Random();

  SimVariant _variant = SimVariant.control;
  bool _running = false;
  bool _infinite = false;
  int _currentRun = 0;
  int _totalRuns = 0;
  String _lastEntity = '';

  Simulator(this._navKey);

  // ── UI-facing state ─────────────────────────────────────────────────────
  bool get running => _running;
  bool get infinite => _infinite;
  int get currentRun => _currentRun;
  int get totalRuns => _totalRuns;
  SimVariant get variant => _variant;
  String get lastEntity => _lastEntity;

  void setVariant(SimVariant v) => _variant = v;

  Future<void> start({int runs = 3, bool infinite = false}) async {
    if (_running) return;
    _running = true;
    _infinite = infinite;
    _totalRuns = infinite ? 0 : runs;
    _currentRun = 0;
    notifyListeners();

    await _applyVariant();
    await Bd.info(
      infinite ? 'simulation_start_infinite' : 'simulation_start',
      fields: {'total_runs': '$runs', 'variant': simVariantLabel(_variant)},
    );
    try {
      while (_running && (_infinite || _currentRun < _totalRuns)) {
        _currentRun++;
        notifyListeners();
        await Bd.info('simulation_run_start', fields: {'run': '$_currentRun'});
        await _journey();
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } finally {
      _running = false;
      notifyListeners();
      // If a journey was interrupted by stop(), the stack may not be back at
      // the welcome screen — bring it back so the app is in a clean state.
      await _resetStack();
      await Bd.info(
        'simulation_end',
        fields: {'completed_runs': '$_currentRun', 'total_runs': '$_totalRuns'},
      );
    }
  }

  void stop() {
    _running = false;
    notifyListeners();
  }

  // ── internals ───────────────────────────────────────────────────────────
  Future<void> _applyVariant() async {
    for (final e in _flagsFor(_variant).entries) {
      await Bd.setFlag(e.key, e.value);
    }
    await Bd.setFlag('variant', simVariantLabel(_variant));
    await Bd.info('feature_flag_exposure_set');
  }

  Map<String, String> _flagsFor(SimVariant v) => switch (v) {
        SimVariant.control => {
              'checkout_flow': 'random',
              'payment_ui': 'random',
              'cart_abandon_rate': 'medium',
              'payment_android_pay': 'enabled',
            },
        SimVariant.variantA => {
              'checkout_flow': 'guest',
              'payment_ui': 'digital',
              'cart_abandon_rate': 'high',
              'payment_android_pay': 'enabled',
            },
        SimVariant.variantB => {
              'checkout_flow': 'signin',
              'payment_ui': 'card',
              'cart_abandon_rate': 'low',
              'payment_android_pay': 'disabled',
            },
      };

  Future<void> _journey() async {
    final profile = kProfiles[_variant]!; // every SimVariant has a profile
    final entity = kEntities[_rng.nextInt(kEntities.length)];
    _lastEntity = entity;
    await Bd.entity(entity);
    await Bd.info('journey_start',
        fields: {'variant': simVariantLabel(_variant), 'entity': entity});
    final journeySpan = await Bd.startSpan('journey',
        fields: {'variant': simVariantLabel(_variant)});

    await _resetStack();

    // 1. Discovery (browse / search / categories).
    final discoverySpan = await Bd.startSpan('product_discovery');
    String productId = '';
    var source = '';
    final roll = _rng.nextDouble();
    if (roll < profile.discoveryBrowseMax) {
      source = 'browse';
      await _go('browse');
      final products = Product.list((await _safe(Api.browse))['products']);
      if (products.isNotEmpty) productId = _pickId(products);
    } else if (roll < profile.discoverySearchMax) {
      source = 'search';
      await _go('search');
      final q = kSearchTerms[_rng.nextInt(kSearchTerms.length)];
      final products =
          Product.list((await _safe(() => Api.search(q)))['products']);
      if (products.isNotEmpty) productId = _pickId(products);
    } else {
      source = 'categories';
      await _go('categories');
      final cats = Category.list((await _safe(Api.categories))['categories']);
      if (cats.isNotEmpty) {
        final c = cats[_rng.nextInt(cats.length)].name;
        await _go('category', args: c);
        final products =
            Product.list((await _safe(() => Api.categoryProducts(c)))['products']);
        if (products.isNotEmpty) productId = _pickId(products);
      }
    }
    if (productId.isEmpty) {
      // Fallback so the journey can still reach cart / checkout.
      final products = Product.list((await _safe(Api.browse))['products']);
      if (products.isNotEmpty) productId = _pickId(products);
    }
    await discoverySpan?.end(success: true);
    if (productId.isNotEmpty) {
      await Bd.info('discovery_completed',
          fields: {'source': source, 'product_id': productId});
    }
    if (await _stopped(journeySpan)) return;

    // 2. Product detail (+ optional reviews / wishlist).
    if (productId.isNotEmpty) {
      await _go('product', args: productId);
      await Bd.info('product_viewed',
          fields: {'product_id': productId, 'source': source});
      if (await _stopped(journeySpan)) return;
      if (_rng.nextDouble() < profile.reviewsProb) {
        await _go('reviews', args: productId);
      }
      if (await _stopped(journeySpan)) return;
      if (_rng.nextDouble() < profile.wishlistProb) {
        await _go('wishlist', args: productId);
        await _safe(() => Api.wishlist(productId));
      }
    }

    // 3. Cart.
    await _go('cart');
    if (await _stopped(journeySpan)) return;
    if (productId.isNotEmpty) await _safe(() => Api.addToCart(productId));
    final extra = profile.extraCartMin +
        _rng.nextInt(
            (profile.extraCartMax - profile.extraCartMin + 1).clamp(0, 64));
    final catalog = Product.list((await _safe(Api.browse))['products']);
    for (var i = 0; i < extra && catalog.isNotEmpty; i++) {
      await _safe(() => Api.addToCart(catalog[_rng.nextInt(catalog.length)].id));
    }

    // 4. Checkout (guest vs signin).
    final isGuest = _rng.nextDouble() < profile.guestProb;
    final checkoutType = isGuest ? 'guest' : 'signin';
    final checkoutSpan = await Bd.startSpan('checkout',
        fields: {'checkout_type': checkoutType});
    await _go(isGuest ? 'checkout_guest' : 'checkout_signin');
    if (await _stopped(journeySpan, checkoutSpan)) return;
    String session = '';
    try {
      final resp =
          isGuest ? await Api.checkoutGuest() : await Api.checkoutSignIn();
      session = (resp['checkout_session'] ?? '').toString();
      await checkoutSpan?.end(success: true);
      await Bd.info('checkout_created',
          fields: {
            'checkout_type': checkoutType,
            'variant': simVariantLabel(_variant)
          });
    } catch (e) {
      await checkoutSpan?.end(success: false);
      await journeySpan?.end(success: false);
      await Bd.warning('checkout_failed',
          fields: {'checkout_type': checkoutType, 'reason': '$e'});
      await _resetStack();
      return;
    }

    // 5. Payment (variant-weighted method).
    final method = _pickPayment(profile);
    await _go(paymentRoute(method), args: {'session': session});
    await Bd.info('payment_method_selected',
        fields: {'payment_method': method, 'variant': simVariantLabel(_variant)});
    if (await _stopped(journeySpan)) return;
    // Crash loop (like the Android demo's "crash on payment"): when active,
    // the journey ends here with a random crash. Close the still-open journey
    // span for a chance to flush, then die — the script relaunches the app.
    if (await Crash.loopActive()) {
      await journeySpan?.end(success: false);
      await Crash.injectRandom();
    }
    bool paid = false;
    String orderId = '';
    try {
      final resp = await _pay(method, session);
      orderId = (resp['order_id'] ?? '').toString();
      paid = true;
    } catch (e) {
      await Bd.error('payment_failed',
          fields: {'payment_method': method, 'reason': '$e'});
    }
    if (!paid) {
      await _go('payment_failed', args: {'method': method});
      await journeySpan?.end(success: false);
      await _resetStack();
      return;
    }

    // 6. Confirmation.
    await _go('confirmation', args: orderId);
    await Bd.info('order_completed',
        fields: {
          'payment_method': method,
          'order_id': orderId,
          'variant': simVariantLabel(_variant),
        });
    await journeySpan?.end(success: true);
    await _resetStack();
  }

  /// If [stop] was pressed while a journey was in flight, close any spans still
  /// open and abort the journey. Returns true when the journey was stopped.
  Future<bool> _stopped(SpanHandle? journey, [SpanHandle? child]) async {
    if (_running) return false;
    await Bd.info('journey_stopped');
    await child?.end(success: false);
    await journey?.end(success: false);
    return true;
  }

  // ── small helpers ───────────────────────────────────────────────────────
  Future<void> _go(String name, {Object? args}) async {
    final nav = _navKey.currentState;
    if (nav == null) return;
    try {
      nav.pushNamed(name, arguments: args);
    } catch (e) {
      await Bd.warning('sim_navigation_failed',
          fields: {'route': name, 'reason': '$e'});
    }
    await Future.delayed(const Duration(milliseconds: 900));
  }

  Future<void> _resetStack() async {
    final nav = _navKey.currentState;
    if (nav == null) return;
    while (nav.canPop()) {
      nav.pop();
      await Future.delayed(const Duration(milliseconds: 120));
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<Map<String, dynamic>> _safe(
      Future<Map<String, dynamic>> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return const {};
    }
  }

  String _pickId(List<Product> products) =>
      products[_rng.nextInt(products.length)].id;

  String _pickPayment(SimProfile p) {
    final r = _rng.nextDouble();
    var acc = 0.0;
    acc += p.paymentCard;
    if (r < acc) return 'card';
    acc += p.paymentApplePay;
    if (r < acc) return 'applePay';
    acc += p.paymentPayPal;
    if (r < acc) return 'paypal';
    return 'androidPay';
  }

  Future<Map<String, dynamic>> _pay(String method, String session) =>
      switch (method) {
        'card' => Api.payCard(session),
        'applePay' => Api.payApplePay(session),
        'paypal' => Api.payPayPal(session),
        _ => Api.payAndroidPay(session),
      };
}

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
