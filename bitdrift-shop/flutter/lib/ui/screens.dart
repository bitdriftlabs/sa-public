import 'package:flutter/material.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../config.dart';
import '../models/models.dart';
import '../generated/spec.dart';
import '../crash.dart';
import '../sim/simulator.dart';
import 'container.dart';
import 'welcome.dart' show kVariantColors;
import 'widgets.dart';

String _payLabel(String m) => switch (m) {
      'card' => SpecScreen.paymentCard.screenName,
      'applePay' => SpecScreen.paymentApplePay.screenName,
      'paypal' => SpecScreen.paymentPaypal.screenName,
      _ => SpecScreen.paymentAndroidPay.screenName,
    };

// ── Discovery ─────────────────────────────────────────────────────────────

void _openProduct(BuildContext context, Product p) =>
    Navigator.of(context).pushNamed('product', arguments: p.id);

VoidCallback _onCart(BuildContext context) =>
    () => Navigator.of(context).pushNamed('cart');

VoidCallback _onBack(BuildContext context) =>
    () => Navigator.of(context).maybePop();

/// "View Featured" / "Shop by Category" pair shown on the discovery screens.
List<Widget> _discoveryButtons(BuildContext context) => [
      PrimaryButton(
        title: 'View Featured',
        icon: Icons.star,
        onPressed: () => Navigator.of(context).pushNamed('featured'),
      ),
      SecondaryButton(
        title: 'Shop by Category',
        icon: Icons.list,
        onPressed: () => Navigator.of(context).pushNamed('categories'),
      ),
    ];

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});
  @override
  Widget build(BuildContext context) => LoadScreen(
        title: 'Browse',
        screenView: SpecScreen.browse.screenName,
        fetch: Api.browse,
        builder: (context, d) {
          final products = Product.list(d['products']);
          final total = d['total'] ?? d['total_products'] ?? products.length;
          return ScreenContainer(
            title: 'Browse',
            subtitle: 'Showing ${products.length} of $total products',
            step: 2,
            icon: Icons.menu,
            color: const Color(0xFF9C27B0),
            onBack: _onBack(context),
            onCart: _onCart(context),
            children: [
              ProductRows(products: products, onTap: (p) => _openProduct(context, p)),
              ..._discoveryButtons(context),
            ],
          );
        },
      );
}

class FeaturedScreen extends StatelessWidget {
  const FeaturedScreen({super.key});
  @override
  Widget build(BuildContext context) => LoadScreen(
        title: 'Featured Products',
        screenView: SpecScreen.featured.screenName,
        step: 3,
        icon: Icons.star,
        color: const Color(0xFFFFEB3B),
        fetch: Api.featured,
        builder: (context, d) {
          final banner = (d['banner'] is Map)
              ? (d['banner'] as Map)['text']?.toString() ?? ''
              : '';
          final products = Product.list(d['featured_products']);
          final first = products.isEmpty ? null : products.first;
          return ScreenContainer(
            title: 'Featured Products',
            subtitle: banner.isEmpty ? 'Hand-picked for you' : banner,
            step: 3,
            icon: Icons.star,
            color: const Color(0xFFFFB300),
            onBack: _onBack(context),
            onCart: _onCart(context),
            children: [
              ProductRows(products: products, onTap: (p) => _openProduct(context, p)),
              PrimaryButton(
                title: 'View Product Details',
                icon: Icons.info_outline,
                onPressed: first == null ? null : () => _openProduct(context, first),
              ),
              SecondaryButton(
                title: 'Read Reviews First',
                icon: Icons.star_outline,
                onPressed: first == null
                    ? null
                    : () => Navigator.of(context).pushNamed('reviews', arguments: first.id),
              ),
            ],
          );
        },
      );
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context) => LoadScreen(
        title: 'Categories',
        screenView: SpecScreen.categories.screenName,
        step: 3,
        icon: Icons.list,
        color: const Color(0xFF4CAF50),
        fetch: Api.categories,
        builder: (context, d) {
          final cats = Category.list(d['categories']);
          return ScreenContainer(
            title: 'Categories',
            subtitle: '${cats.length} categories',
            step: 3,
            icon: Icons.list,
            color: const Color(0xFF4CAF50),
            onBack: _onBack(context),
            onCart: _onCart(context),
            children: [
              if (cats.isEmpty)
                const Text('No categories', style: TextStyle(color: Colors.grey))
              else
                CategoryRows(
                  categories: cats,
                  colorOf: categoryColor,
                  iconOf: categoryIcon,
                  onTap: (c) => Navigator.of(context).pushNamed('category', arguments: c.name),
                ),
            ],
          );
        },
      );
}

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final name =
        (ModalRoute.of(context)?.settings.arguments as String?) ?? 'Electronics';
    return LoadScreen(
      title: name,
      screenView: SpecScreen.categoryBrowse.screenName,
      step: 3,
      icon: Icons.list,
      color: const Color(0xFF4CAF50),
      fetch: () => Api.categoryProducts(name),
      builder: (context, d) {
        final products = Product.list(d['products']);
        final first = products.isEmpty ? null : products.first;
        return ScreenContainer(
          title: name,
          subtitle: '${products.length} products',
          step: 3,
          icon: categoryIcon(name),
          color: categoryColor(name),
          onBack: _onBack(context),
          onCart: _onCart(context),
          children: [
            ProductRows(products: products, onTap: (p) => _openProduct(context, p)),
            PrimaryButton(
              title: 'View Product Details',
              icon: Icons.info_outline,
              onPressed: first == null ? null : () => _openProduct(context, first),
            ),
            SecondaryButton(
              title: 'Read Reviews First',
              icon: Icons.star_outline,
              onPressed: first == null
                  ? null
                  : () => Navigator.of(context).pushNamed('reviews', arguments: first.id),
            ),
          ],
        );
      },
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Product> _results = const [];
  bool _loading = false;
  String _error = '';
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    Bd.screenView(SpecScreen.search.screenName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search([String? q]) async {
    final query = (q ?? _ctrl.text).trim();
    setState(() {
      _loading = true;
      _error = '';
      _searched = true;
    });
    try {
      final d = query.isEmpty ? await Api.browse() : await Api.search(query);
      if (!mounted) return;
      setState(() => _results = Product.list(d['products']));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenContainer(
      title: 'Search',
      subtitle: _searched ? '${_results.length} results' : 'Find the products you are looking for',
      step: 2,
      icon: Icons.search,
      color: const Color(0xFFFF9800),
      onBack: _onBack(context),
      onCart: _onCart(context),
      children: [
        TextField(
          controller: _ctrl,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Search products',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
          ),
        ),
        if (_loading)
          const LinearProgressIndicator()
        else if (_error.isNotEmpty)
          Text(_error, style: const TextStyle(color: Colors.redAccent))
        else if (_results.isNotEmpty)
          ProductRows(products: _results, onTap: (p) => _openProduct(context, p))
        else if (_searched)
          const Text('No results found.', style: TextStyle(color: Colors.grey)),
        ..._discoveryButtons(context),
      ],
    );
  }
}

// ── Product ───────────────────────────────────────────────────────────────

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final id = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return LoadScreen(
      title: 'Product',
      screenView: SpecScreen.productDetail.screenName,
      step: 4,
      icon: Icons.notifications,
      color: const Color(0xFF00BCD4),
      fetch: () => Api.product(id),
      builder: (context, d) {
        dynamic imgs = d['images'];
        final img = (imgs is List && imgs.isNotEmpty)
            ? imgs[0]?.toString() ?? ''
            : (d['image_url']?.toString() ?? '');
        final meta = [
          (d['brand'] ?? '').toString(),
          (d['category'] ?? '').toString(),
          money(d['price']),
        ].where((s) => s.isNotEmpty).join(' · ');
        return ScreenContainer(
          title: (d['name'] ?? 'Product').toString(),
          subtitle: meta,
          step: 4,
          icon: Icons.notifications,
          color: const Color(0xFF00BCD4),
          imageUrl: img.isEmpty ? null : Config.resolveImageUrl(img),
          onBack: _onBack(context),
          onCart: _onCart(context),
          children: [
            PrimaryButton(
              title: 'Add to Cart',
              icon: Icons.add_shopping_cart,
              onPressed: () => _addToCart(context, id),
            ),
            SecondaryButton(
              title: 'Customer Reviews',
              icon: Icons.star_outline,
              onPressed: () => Navigator.of(context).pushNamed('reviews', arguments: id),
            ),
            SecondaryButton(
              title: 'Save to Wishlist',
              icon: Icons.favorite_outline,
              onPressed: () => _wishlist(context, id),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addToCart(BuildContext context, String id) async {
    await Bd.info(SpecEvents.addToCart,
        fields: {SpecFields.productId: id, SpecFields.sourceScreen: 'unknown'});
    try {
      await Api.addToCart(id);
      if (context.mounted) Navigator.of(context).pushNamed('cart');
    } catch (e) {
      await Bd.error(SpecEvents.cartFailed,
          fields: {SpecFields.productId: id, SpecFields.reason: '$e'});
    }
  }

  Future<void> _wishlist(BuildContext context, String id) async {
    await Bd.info(SpecEvents.addToWishlist,
        fields: {SpecFields.productId: id, SpecFields.sourceScreen: 'unknown'});
    try {
      await Api.wishlist(id);
      if (context.mounted) {
        Navigator.of(context).pushNamed('wishlist', arguments: id);
      }
    } catch (e) {
      // No Android equivalent event; the failure is visible as the API error (spec D-EVT-F13).
      debugPrint('wishlist add failed for $id: $e');
    }
  }
}

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final id = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return LoadScreen(
      title: 'Customer Reviews',
      screenView: SpecScreen.reviews.screenName,
      step: 4,
      icon: Icons.email,
      color: const Color(0xFF00E5BD),
      fetch: () => Api.reviews(id),
      builder: (context, d) {
        final list = d['reviews'];
        final rows = <({String title, String subtitle, String trailing})>[
          if (list is List)
            for (final r in list.whereType<Map<String, dynamic>>())
              (
                title: (r['title'] ?? '').toString(),
                subtitle: (r['body'] ?? '').toString(),
                trailing: '${r['rating'] ?? ''}★',
              ),
        ];
        return ScreenContainer(
          title: 'Customer Reviews',
          subtitle: '${d['average_rating'] ?? '—'} ★ · ${d['total_reviews'] ?? 0} reviews',
          step: 4,
          icon: Icons.email,
          color: const Color(0xFF00BFA5),
          onBack: _onBack(context),
          onCart: _onCart(context),
          children: [
            if (rows.isEmpty)
              const Text('No reviews', style: TextStyle(color: Colors.grey))
            else
              InfoRows(rows: rows),
            PrimaryButton(
              title: 'Add to Cart',
              icon: Icons.add_shopping_cart,
              onPressed: id.isEmpty
                  ? null
                  : () async {
                      await Bd.info(SpecEvents.addToCart, fields: {
                        SpecFields.productId: id,
                        SpecFields.sourceScreen: 'unknown'
                      });
                      try {
                        await Api.addToCart(id);
                        if (context.mounted) Navigator.of(context).pushNamed('cart');
                      } catch (e) {
                        await Bd.error(SpecEvents.cartFailed,
                            fields: {SpecFields.productId: id, SpecFields.reason: '$e'});
                      }
                    },
            ),
          ],
        );
      },
    );
  }
}

// ── Cart / Wishlist ───────────────────────────────────────────────────────

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) => LoadScreen(
        title: 'Shopping Cart',
        screenView: SpecScreen.cart.screenName,
        step: 5,
        icon: Icons.shopping_cart,
        color: const Color(0xFF2196F3),
        fetch: Api.cart,
        builder: (context, d) {
          final items = d['items'];
          final empty = items is! List || items.isEmpty;
          final rows = <({String title, String subtitle, String trailing})>[
            if (!empty)
              for (final m in items.whereType<Map<String, dynamic>>())
                (
                  title: (m['name'] ?? '').toString(),
                  subtitle: '${m['quantity']} × ${money(m['unit_price'])}',
                  trailing: money(m['line_total']),
                ),
          ];
          return ScreenContainer(
            title: 'Shopping Cart',
            subtitle: empty ? 'Your cart is empty' : '${rows.length} ${rows.length == 1 ? 'item' : 'items'} · Total ${money(d['total'])}',
            step: 5,
            icon: Icons.shopping_cart,
            color: const Color(0xFF2196F3),
            onBack: _onBack(context),
            children: [
              if (!empty) InfoRows(rows: rows),
              PrimaryButton(
                title: 'Checkout as Guest',
                icon: Icons.person,
                onPressed: () => _checkout(context, empty, 'checkout_guest'),
              ),
              SecondaryButton(
                title: 'Sign In to Checkout',
                icon: Icons.lock,
                onPressed: () => _checkout(context, empty, 'checkout_signin'),
              ),
              SecondaryButton(
                title: 'Keep Shopping',
                icon: Icons.menu,
                onPressed: () => Navigator.of(context).pushNamed('browse'),
              ),
            ],
          );
        },
      );

  void _checkout(BuildContext context, bool empty, String route) {
    if (empty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add something to the cart first')));
      return;
    }
    Navigator.of(context).pushNamed(route);
  }
}

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});
  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  @override
  void initState() {
    super.initState();
    Bd.screenView(SpecScreen.wishlist.screenName);
  }

  @override
  Widget build(BuildContext context) {
    final id = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return ScreenContainer(
      title: 'Wishlist',
      subtitle: id.isEmpty ? 'Your wishlist' : 'Saved to wishlist',
      step: 5,
      icon: Icons.favorite,
      color: const Color(0xFFE91E63),
      onBack: _onBack(context),
      onCart: _onCart(context),
      children: [
        PrimaryButton(
          title: 'Checkout as Guest',
          icon: Icons.person,
          onPressed: () => Navigator.of(context).pushNamed('checkout_guest'),
        ),
        SecondaryButton(
          title: 'Sign In to Checkout',
          icon: Icons.lock,
          onPressed: () => Navigator.of(context).pushNamed('checkout_signin'),
        ),
        SecondaryButton(
          title: 'Back to shop',
          icon: Icons.home,
          onPressed: () => Navigator.of(context).popUntil((r) => r.settings.name == '/'),
        ),
      ],
    );
  }
}

// ── Checkout / Payment ────────────────────────────────────────────────────

class CheckoutScreen extends StatefulWidget {
  final bool guest;
  const CheckoutScreen({super.key, required this.guest});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String _error = '';
  double _total = 0;

  @override
  void initState() {
    super.initState();
    Bd.screenView(widget.guest
        ? SpecScreen.checkoutGuest.screenName
        : SpecScreen.checkoutSignin.screenName);
    _loadTotal();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _loadTotal() async {
    try {
      final d = await Api.cart();
      _total = double.tryParse((d['total'] ?? '0').toString()) ?? 0;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _place() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final type = widget.guest ? 'guest' : 'signin';
    try {
      final resp = widget.guest
          ? await Api.checkoutGuest(_email.text)
          : await Api.checkoutSignIn(_email.text);
      final session = (resp['checkout_session'] ?? '').toString();
      await Bd.info(SpecEvents.checkoutStarted,
          fields: {SpecFields.checkoutType: type});
      if (!mounted) return;
      Navigator.of(context)
          .pushNamed('payment_card', arguments: {'session': session, 'amount': _total});
    } catch (e) {
      await Bd.error(SpecEvents.checkoutFailed,
          fields: {SpecFields.checkoutType: type, SpecFields.reason: '$e'});
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenContainer(
      title: widget.guest ? 'Guest Checkout' : 'Member Checkout',
      subtitle: 'Order total: ${money(_total)}',
      step: 6,
      icon: widget.guest ? Icons.person : Icons.lock,
      color: widget.guest ? const Color(0xFF3F51B5) : const Color(0xFF009688),
      onBack: _onBack(context),
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.redAccent)),
        PrimaryButton(
          title: _busy ? 'Placing order…' : 'Place order',
          icon: Icons.credit_card,
          onPressed: _busy ? null : _place,
        ),
        SecondaryButton(
          title: widget.guest ? 'Have an account? Sign in' : 'Checking out as guest instead',
          icon: widget.guest ? Icons.lock : Icons.person,
          onPressed: () => Navigator.of(context)
              .pushNamed(widget.guest ? 'checkout_signin' : 'checkout_guest'),
        ),
      ],
    );
  }
}

class PaymentScreen extends StatefulWidget {
  final String method;
  const PaymentScreen({super.key, required this.method});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic> _args = const {};
  bool _busy = false;
  String _error = '';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of(context) depends on an InheritedWidget, so it can't be
    // called from initState() — do it here instead, guarded to run once.
    if (_initialized) return;
    _initialized = true;
    final a = ModalRoute.of(context)?.settings.arguments;
    if (a is Map) _args = a.map((k, v) => MapEntry(k.toString(), v));
    Bd.screenView(_payLabel(widget.method));
  }

  String get _session => _args['session']?.toString() ?? '';

  void _switchTo(String m) => Navigator.of(context).pushNamed(
        paymentRoute(m),
        arguments: {'session': _session, 'amount': _args['amount']},
      );

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final resp = switch (widget.method) {
        'card' => await Api.payCard(_session),
        'applePay' => await Api.payApplePay(_session),
        'paypal' => await Api.payPayPal(_session),
        _ => await Api.payAndroidPay(_session),
      };
      final orderId = (resp['order_id'] ?? '').toString();
      await Bd.info(SpecEvents.paymentCompleted, fields: {
        SpecFields.paymentMethod: paymentMethodLabel(widget.method),
        SpecFields.orderId: orderId,
      });
      if (mounted) Navigator.of(context).pushNamed('confirmation', arguments: orderId);
    } catch (e) {
      await Bd.error(SpecEvents.paymentFailed, fields: {
        SpecFields.paymentMethod: paymentMethodLabel(widget.method),
        SpecFields.reason: '$e',
      });
      if (mounted) {
        Navigator.of(context).pushNamed('payment_failed',
            arguments: {'method': widget.method, 'reason': '$e'});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, icon, color) = switch (widget.method) {
      'card' => ('Card Payment', Icons.credit_card, const Color(0xFF2196F3)),
      'applePay' => ('Apple Pay', Icons.phone_iphone, Colors.black),
      'paypal' => ('PayPal', Icons.send, const Color(0xFF2196F3)),
      _ => ('Android Pay', Icons.phone_android, const Color(0xFF4CAF50)),
    };
    return ScreenContainer(
      title: title,
      subtitle: 'Charging ${money(_args['amount'])}',
      step: 6,
      icon: icon,
      color: color,
      onBack: _onBack(context),
      children: [
        if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.redAccent)),
        PrimaryButton(
          title: _busy ? 'Processing…' : 'Pay with ${_payLabel(widget.method)}',
          icon: Icons.check,
          onPressed: _busy ? null : _pay,
        ),
        for (final m in const ['card', 'applePay', 'paypal', 'androidPay'])
          if (m != widget.method)
            SecondaryButton(
              title: _payLabel(m),
              icon: Icons.swap_horiz,
              onPressed: () => _switchTo(m),
            ),
      ],
    );
  }
}

class PaymentFailedScreen extends StatefulWidget {
  const PaymentFailedScreen({super.key});
  @override
  State<PaymentFailedScreen> createState() => _PaymentFailedScreenState();
}

class _PaymentFailedScreenState extends State<PaymentFailedScreen> {
  Map<String, dynamic> _args = const {};
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of(context) depends on an InheritedWidget, so it can't be
    // called from initState() — do it here instead, guarded to run once.
    if (_initialized) return;
    _initialized = true;
    final a = ModalRoute.of(context)?.settings.arguments;
    if (a is Map) _args = a.map((k, v) => MapEntry(k.toString(), v));
    Bd.screenView(SpecScreen.paymentFailed.screenName);
  }

  @override
  Widget build(BuildContext context) {
    final method = (_args['method'] ?? '').toString();
    return ScreenContainer(
      title: 'Payment Failed',
      subtitle: method.isEmpty
          ? 'Your payment could not be processed.'
          : 'Your ${_payLabel(method)} payment could not be processed.',
      step: 6,
      icon: Icons.warning,
      color: const Color(0xFFE53935),
      onBack: _onBack(context),
      children: [
        PrimaryButton(
          title: 'Try Again',
          icon: Icons.refresh,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final orderId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return LoadScreen(
      title: 'Order Confirmed!',
      screenView: SpecScreen.confirmation.screenName,
      step: 7,
      icon: Icons.check_circle,
      color: const Color(0xFF4CAF50),
      fetch: () => Api.confirmation(orderId.isEmpty ? 'unknown' : orderId),
      builder: (context, d) => ScreenContainer(
        title: 'Order Confirmed!',
        subtitle: 'Order ${d['order_id'] ?? orderId} · ${money(d['total'])}',
        step: 7,
        icon: Icons.check_circle,
        color: const Color(0xFF4CAF50),
        children: [
          PrimaryButton(
            title: 'Back to shop',
            icon: Icons.home,
            onPressed: () => Navigator.of(context).popUntil((r) => r.settings.name == '/'),
          ),
        ],
      ),
    );
  }
}

// ── Diagnostics ───────────────────────────────────────────────────────────

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, dynamic> _info = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Bd.screenView(SpecScreen.advanced.screenName);
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final sessionId = await Bd.sessionId;
    final sessionUrl = await Bd.sessionUrl;
    final deviceId = await Bd.deviceId;
    if (!mounted) return;
    setState(() {
      _info = {
        'session_id': sessionId ?? '—',
        'session_url': sessionUrl ?? '—',
        'device_id': deviceId ?? '—',
      };
      _busy = false;
    });
  }

  Future<void> _newSession() async {
    await Bd.startNewSession();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sim = SimulatorScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) => ScreenContainer(
        title: 'Advanced',
        subtitle: 'Personas, simulation modes, and fault injection',
        step: 1,
        icon: Icons.settings,
        color: const Color(0xFF2196F3),
        onBack: () => Navigator.of(context).pop(),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Simulation Variant',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Row(
            children: [
              for (final v in SimVariant.values) ...[
                if (v != SimVariant.control) const SizedBox(width: 8),
                Expanded(
                  child: ColorButton(
                    title: simVariantLabel(v),
                    color: sim.variant == v ? kVariantColors[v]! : scheme.surfaceContainerHighest,
                    foreground: sim.variant == v ? Colors.white : scheme.onSurfaceVariant,
                    onPressed: () => sim.setVariant(v),
                  ),
                ),
              ],
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Active: ${simVariantLabel(sim.variant)}',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Fault Injection',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          ColorButton(
            title: 'Crash: random',
            color: const Color(0xFFE53935),
            onPressed: () => Crash.injectRandom(),
          ),
          Text(
            'Crash loop: bash scripts/crash-loop.sh (Ctrl-C to stop)',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Debug Tools',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          _InfoRow(label: 'Session ID', value: _info['session_id']?.toString() ?? '—'),
          _InfoRow(label: 'Session URL', value: _info['session_url']?.toString() ?? '—'),
          _InfoRow(label: 'Device ID', value: _info['device_id']?.toString() ?? '—'),
          TonalButton(title: 'New session', onPressed: _busy ? null : _newSession),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child:
                    Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      );
}
