import 'package:flutter/material.dart';

import '../bd/capture.dart';
import '../config.dart';
import '../models/models.dart';

/// Per-category accents, matching the Android app (Components.kt `categoryColors`).
const Map<String, Color> kCategoryColors = {
  'Electronics': Color(0xFF6196F3),
  'Clothing': Color(0xFF9C27B0),
  'Home & Garden': Color(0xFFFF9800),
  'Sports': Color(0xFF4CAF50),
};

/// Per-category icons, matching the Android app (Components.kt `categoryIcons`).
const Map<String, IconData> kCategoryIcons = {
  'Electronics': Icons.phone_android,
  'Clothing': Icons.face,
  'Home & Garden': Icons.home,
  'Sports': Icons.star,
};

Color categoryColor(String name) => kCategoryColors[name] ?? Colors.grey;

IconData categoryIcon(String name) => kCategoryIcons[name] ?? Icons.folder;

String money(dynamic v) {
  final d = double.tryParse((v ?? 0).toString()) ?? 0.0;
  return '\$${d.toStringAsFixed(2)}';
}

/// Common scaffold with an optional app-bar actions list.
class ScreenShell extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const ScreenShell({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(title), actions: actions), body: body);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final grey = const Color(0xFF9AA0A6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: grey)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a product image, with a placeholder on failure.
class ProductImage extends StatelessWidget {
  final String url;
  final double size;
  const ProductImage({super.key, required this.url, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final u = Config.resolveImageUrl(url);
    final placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFF1F2733),
      child: Icon(Icons.image, size: size * 0.5, color: const Color(0xFF5A6472)),
    );
    if (u.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, e, s) => placeholder,
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const ProductTile({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bits = [product.category, product.brand]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: ProductImage(url: product.imageUrl),
        title: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: bits.isEmpty ? null : Text(bits),
        trailing: Text(
          money(product.price),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: onTap,
      ),
    );
  }
}

enum _LoadState { loading, error, ready }

/// Fetches a backend endpoint, handles loading/error/retry, and delegates the
/// rendered body to [builder]. Logs a screen view once when first shown.
class LoadScreen extends StatefulWidget {
  final String title;
  final String screenView;
  final Future<Map<String, dynamic>> Function() fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> data) builder;

  const LoadScreen({
    super.key,
    required this.title,
    required this.screenView,
    required this.fetch,
    required this.builder,
  });

  @override
  State<LoadScreen> createState() => _LoadScreenState();
}

class _LoadScreenState extends State<LoadScreen> {
  _LoadState _state = _LoadState.loading;
  String _error = '';
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    Bd.screenView(widget.screenView);
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _state = _LoadState.loading);
    try {
      final d = await widget.fetch();
      if (mounted) {
        setState(() {
          _data = d;
          _state = _LoadState.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _state = _LoadState.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenShell(
      title: widget.title,
      body: _state == _LoadState.loading
          ? const LoadingView()
          : _state == _LoadState.error
              ? ErrorView(message: _error, onRetry: _load)
              : widget.builder(context, _data),
    );
  }
}
