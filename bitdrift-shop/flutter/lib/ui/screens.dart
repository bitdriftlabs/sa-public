import 'package:flutter/material.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../models/models.dart';
import '../sim/simulator.dart' show paymentRoute;
import 'widgets.dart';

String _payLabel(String m) => switch (m) {
      'card' => 'Card',
      'applePay' => 'Apple Pay',
      'paypal' => 'PayPal',
      _ => 'Android Pay',
    };

Widget _productListView(BuildContext context, Map<String, dynamic> data,
    {String key = 'products'}) {
  final products = Product.list(data[key]);
  if (products.isEmpty) {
    return const Center(
        child: Text('No products', style: TextStyle(color: Colors.grey)));
  }
  return ListView.builder(
    itemCount: products.length,
    itemBuilder: (context, i) => ProductTile(
      product: products[i],
      onTap: () =>
          Navigator.of(context).pushNamed('product', arguments: products[i].id),
    ),
  );
}

// ── Discovery ─────────────────────────────────────────────────────────────

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});
  @override
  Widget build(BuildContext context) => LoadScreen(
        title: 'Browse',
        screenView: 'Browse',
        fetch: Api.browse,
        builder: (context, d) => _productListView(context, d),
      );
}

class FeaturedScreen extends StatelessWidget {
  const FeaturedScreen({super.key});
  @override
  Widget build(BuildContext context) => LoadScreen(
        title: 'Featured',
        screenView: 'Featured',
        fetch: Api.featured,
        builder: (context, d) {
          final banner = (d['banner'] is Map)
              ? (d['banner'] as Map)['text']?.toString() ?? ''
              : '';
          return Column(
            children: [
              if (banner.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: const Color(0x332196F3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(banner,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              Expanded(child: _productListView(context, d, key: 'featured_products')),
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
        screenView: 'Categories',
        fetch: Api.categories,
        builder: (context, d) {
          final cats = Category.list(d['categories']);
          if (cats.isEmpty) {
            return const Center(
                child:
                    Text('No categories', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              final cColor = categoryColor(c.name);
              return ListTile(
                tileColor: cColor.withValues(alpha: 0.15),
                leading: Icon(categoryIcon(c.name), color: cColor),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.productCount} products'),
                trailing: Icon(Icons.chevron_right, color: cColor),
                onTap: () =>
                    Navigator.of(context).pushNamed('category', arguments: c.name),
              );
            },
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
      screenView: 'CategoryBrowse',
      fetch: () => Api.categoryProducts(name),
      builder: (context, d) => _productListView(context, d),
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
    Bd.screenView('Search');
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
    return ScreenShell(
      title: 'Search',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search products',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon:
                    IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator()
            else if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: Colors.redAccent))
            else if (_results.isEmpty)
              Text(_searched
                  ? 'No results found.'
                  : 'Type a query and search, or pick a product from Browse.',
                  style: const TextStyle(color: Colors.grey))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) => ProductTile(
                    product: _results[i],
                    onTap: () => Navigator.of(context)
                        .pushNamed('product', arguments: _results[i].id),
                  ),
                ),
              ),
          ],
        ),
      ),
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
      screenView: 'ProductDetail',
      fetch: () => Api.product(id),
      builder: (context, d) {
        dynamic imgs = d['images'];
        final img = (imgs is List && imgs.isNotEmpty)
            ? imgs[0]?.toString() ?? ''
            : (d['image_url']?.toString() ?? '');
        final desc = (d['description'] ?? '').toString();
        final meta = [
          (d['brand'] ?? '').toString(),
          (d['category'] ?? '').toString(),
        ].where((s) => s.isNotEmpty).join(' · ');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (img.isNotEmpty)
              Center(child: ProductImage(url: img, size: 160)),
            const SizedBox(height: 16),
            Text((d['name'] ?? '').toString(),
                style: Theme.of(context).textTheme.headlineSmall),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta, style: const TextStyle(color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            Text(money(d['price']),
                style: Theme.of(context).textTheme.headlineMedium),
            if (d['stock_count'] != null) ...[
              const SizedBox(height: 4),
              Text('In stock: ${d['stock_count']}'),
            ],
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(desc),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Add to cart'),
                    onPressed: () => _addToCart(context, id),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Reviews'),
                  onPressed: () =>
                      Navigator.of(context).pushNamed('reviews', arguments: id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.favorite_outline),
              label: const Text('Add to wishlist'),
              onPressed: () => _wishlist(context, id),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addToCart(BuildContext context, String id) async {
    await Bd.info('add_to_cart_tapped', fields: {'product_id': id});
    try {
      await Api.addToCart(id);
      if (context.mounted) Navigator.of(context).pushNamed('cart');
    } catch (e) {
      await Bd.warning('add_to_cart_failed',
          fields: {'product_id': id, 'reason': '$e'});
    }
  }

  Future<void> _wishlist(BuildContext context, String id) async {
    await Bd.info('wishlist_add_tapped', fields: {'product_id': id});
    try {
      await Api.wishlist(id);
      if (context.mounted) {
        Navigator.of(context).pushNamed('wishlist', arguments: id);
      }
    } catch (e) {
      await Bd.warning('wishlist_add_failed',
          fields: {'product_id': id, 'reason': '$e'});
    }
  }
}

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final id = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return LoadScreen(
      title: 'Reviews',
      screenView: 'Reviews',
      fetch: () => Api.reviews(id),
      builder: (context, d) {
        final list = d['reviews'];
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${d['average_rating'] ?? '—'} ★ · ${d['total_reviews'] ?? 0} reviews',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (list is List)
              ...list.whereType<Map<String, dynamic>>().map((r) {
                final author = (r['author'] ?? '?').toString();
                final initial =
                    author.isEmpty ? '?' : author.substring(0, 1).toUpperCase();
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(initial)),
                    title: Text((r['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text((r['body'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    trailing: Text('${r['rating'] ?? ''}★'),
                  ),
                );
              })
            else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No reviews', style: TextStyle(color: Colors.grey)),
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
        title: 'Cart',
        screenView: 'Cart',
        fetch: Api.cart,
        builder: (context, d) {
          final items = d['items'];
          final empty = items is! List || items.isEmpty;
          return Column(
            children: [
              Expanded(
                child: empty
                    ? const Center(
                        child: Text('Your cart is empty',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final m = (items as List)[i] as Map<String, dynamic>;
                          return ListTile(
                            title: Text((m['name'] ?? '').toString()),
                            subtitle:
                                Text('${m['quantity']} × ${money(m['unit_price'])}'),
                            trailing: Text(money(m['line_total']),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Total',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Text(money(d['total']),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: () => _checkout(context, empty),
                        child: const Text('Checkout'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );

  void _checkout(BuildContext context, bool empty) {
    if (empty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add something to the cart first')));
      return;
    }
    Navigator.of(context).pushNamed('checkout_guest');
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
    Bd.screenView('Wishlist');
  }

  @override
  Widget build(BuildContext context) {
    final id = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return ScreenShell(
      title: 'Wishlist',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite, size: 56, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(id.isEmpty ? 'Your wishlist' : 'Saved to wishlist',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.settings.name == '/'),
                child: const Text('Back to shop'),
              ),
            ],
          ),
        ),
      ),
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
    Bd.screenView(widget.guest ? 'CheckoutGuest' : 'CheckoutSignIn');
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
      await Bd.info('checkout_created',
          fields: {'checkout_type': type, 'amount': _total.toString()});
      if (!mounted) return;
      Navigator.of(context)
          .pushNamed('payment_card', arguments: {'session': session, 'amount': _total});
    } catch (e) {
      await Bd.error('checkout_failed', fields: {'checkout_type': type, 'reason': '$e'});
      if (mounted) setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenShell(
      title: widget.guest ? 'Guest checkout' : 'Sign in & checkout',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Order total: ${money(_total)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushNamed(widget.guest ? 'checkout_signin' : 'checkout_guest'),
              child: Text(widget.guest
                  ? 'Have an account? Sign in'
                  : 'Checking out as guest instead'),
            ),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: Colors.redAccent)),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _place,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Place order'),
            ),
          ],
        ),
      ),
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

  @override
  void initState() {
    super.initState();
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
    await Bd.info('payment_attempted', fields: {'payment_method': widget.method});
    try {
      final resp = switch (widget.method) {
        'card' => await Api.payCard(_session),
        'applePay' => await Api.payApplePay(_session),
        'paypal' => await Api.payPayPal(_session),
        _ => await Api.payAndroidPay(_session),
      };
      final orderId = (resp['order_id'] ?? '').toString();
      await Bd.info('payment_succeeded',
          fields: {'payment_method': widget.method, 'order_id': orderId});
      if (mounted) Navigator.of(context).pushNamed('confirmation', arguments: orderId);
    } catch (e) {
      await Bd.error('payment_failed',
          fields: {'payment_method': widget.method, 'reason': '$e'});
      if (mounted) {
        Navigator.of(context).pushNamed('payment_failed',
            arguments: {'method': widget.method, 'reason': '$e'});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenShell(
      title: 'Payment',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_payLabel(widget.method),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Charging ${money(_args['amount'])}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const ['card', 'applePay', 'paypal', 'androidPay'])
                  ActionChip(
                    label: Text(_payLabel(m)),
                    onPressed: () => _switchTo(m),
                  ),
              ],
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: Colors.redAccent)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _pay,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Pay with ${_payLabel(widget.method)}'),
            ),
          ],
        ),
      ),
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

  @override
  void initState() {
    super.initState();
    final a = ModalRoute.of(context)?.settings.arguments;
    if (a is Map) _args = a.map((k, v) => MapEntry(k.toString(), v));
    Bd.screenView('PaymentFailed');
  }

  @override
  Widget build(BuildContext context) {
    return ScreenShell(
      title: 'Payment failed',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.payment, size: 56, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('Payment failed', style: Theme.of(context).textTheme.titleLarge),
              if ((_args['method'] ?? '').toString().isNotEmpty)
                Text(_payLabel(_args['method'].toString()),
                    style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final orderId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    return LoadScreen(
      title: 'Confirmation',
      screenView: 'Confirmation',
      fetch: () =>
          Api.confirmation(orderId.isEmpty ? 'unknown' : orderId),
      builder: (context, d) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text('Order confirmed', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Order ${d['order_id'] ?? orderId}',
                  style: const TextStyle(color: Colors.grey)),
              Text(money(d['total']),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.settings.name == '/'),
                child: const Text('Back to shop'),
              ),
            ],
          ),
        ),
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
    Bd.screenView('Diagnostics');
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
    return ScreenShell(
      title: 'Diagnostics',
      actions: [
        IconButton(
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          onPressed: _busy ? null : _load,
        )
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoRow(label: 'Session ID', value: _info['session_id']?.toString() ?? '—'),
          _InfoRow(label: 'Session URL', value: _info['session_url']?.toString() ?? '—'),
          _InfoRow(label: 'Device ID', value: _info['device_id']?.toString() ?? '—'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _newSession,
            child: const Text('New session'),
          ),
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
