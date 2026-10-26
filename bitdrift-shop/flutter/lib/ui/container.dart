import 'package:flutter/material.dart';

import '../config.dart';
import '../models/models.dart';
import '../sim/simulator.dart';

/// Step dots across the top of a screen, like the Android app's StepIndicator.
class StepDots extends StatelessWidget {
  final int current;
  final int total;
  const StepDots({super.key, required this.current, this.total = 7});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= total; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current ? primary : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

/// Port of the Android app's `ScreenContainer` (Components.kt): back / step dots /
/// cart header, a centered hero (logo + versions, product image or tinted icon),
/// title and subtitle, then the screen's buttons stacked at the bottom.
class ScreenContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final int step;
  final IconData icon;
  final Color color;
  final String? imageUrl;

  /// Extra lines shown under the logo (SDK version, app version, ...). When set,
  /// the hero is the bitdrift logo; the app version then lives in this group.
  final List<String>? logoLines;
  final VoidCallback? onBack;
  final VoidCallback? onCart;
  final List<Widget> children;

  const ScreenContainer({
    super.key,
    required this.title,
    required this.subtitle,
    required this.step,
    required this.icon,
    required this.color,
    this.imageUrl,
    this.logoLines,
    this.onBack,
    this.onCart,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final sim = SimulatorScope.of(context);
    final labelStyle = text.labelMedium?.copyWith(color: onSurface.withValues(alpha: 0.85));

    Widget hero;
    if (logoLines != null) {
      hero = Column(
        children: [
          FractionallySizedBox(
            widthFactor: 0.72,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset('assets/bitdrift_logo.png', height: 44, fit: BoxFit.contain),
            ),
          ),
          for (final line in logoLines!) ...[
            const SizedBox(height: 6),
            Text(line, style: labelStyle),
          ],
        ],
      );
    } else if (imageUrl != null) {
      hero = ClipOval(
        child: Image.network(imageUrl!, width: 120, height: 120, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 120)),
      );
    } else {
      hero = Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, size: 44, color: color),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: onBack == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.arrow_back), onPressed: onBack),
                        ),
                        const Spacer(),
                        StepDots(current: step),
                        const Spacer(),
                        SizedBox(
                          width: 48,
                          height: 48,
                          // While a simulation runs, journey screens get a stop button
                          // in the spot the cart icon uses.
                          child: ListenableBuilder(
                            listenable: sim,
                            builder: (context, _) => sim.running && onBack != null
                                ? IconButton(
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Stop simulation',
                                    onPressed: sim.stop)
                                : onCart == null
                                    ? const SizedBox.shrink()
                                    : IconButton(
                                        icon: const Icon(Icons.shopping_cart), onPressed: onCart),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    hero,
                    const SizedBox(height: 16),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(subtitle,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(color: onSurface.withValues(alpha: 0.6))),
                    ),
                    if (logoLines == null) ...[
                      const SizedBox(height: 16),
                      Text('App v${Config.appVersion}', style: labelStyle),
                    ],
                    const Spacer(),
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filled primary button with a leading icon and trailing chevron (Android `PrimaryButton`).
class PrimaryButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.title, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _row(context, icon, title, Theme.of(context).colorScheme.onPrimary),
      );
}

/// Outlined button with a leading icon and trailing chevron (Android `SecondaryButton`).
class SecondaryButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onPressed;
  const SecondaryButton({super.key, required this.title, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          foregroundColor: Theme.of(context).colorScheme.primary,
        ),
        child: _row(context, icon, title, Theme.of(context).colorScheme.primary),
      );
}

Widget _row(BuildContext context, IconData icon, String title, Color color) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        ]),
        Icon(Icons.chevron_right, color: color),
      ],
    );

/// Compact bold colored action button (Android `SimButton` / persona buttons).
class ColorButton extends StatelessWidget {
  final String title;
  final Color color;
  final Color foreground;
  final VoidCallback? onPressed;
  const ColorButton({
    super.key,
    required this.title,
    required this.color,
    this.foreground = Colors.white,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        child: Text(title),
      );
}

/// Full-width tonal button (Android's lavender "Device Code").
class TonalButton extends StatelessWidget {
  final String title;
  final VoidCallback? onPressed;
  final double fontSize;
  const TonalButton({super.key, required this.title, this.onPressed, this.fontSize = 14});

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
        ),
        child: Text(title),
      );
}

String _money(dynamic v) {
  final d = double.tryParse((v ?? 0).toString()) ?? 0.0;
  return '\$${d.toStringAsFixed(2)}';
}

/// A flat, tinted list row: leading visual, bold title, secondary line (Android `ProductRow`).
class _Row extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({required this.leading, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Short scrolling product list (about three rows), like the Android screens.
class ProductRows extends StatelessWidget {
  final List<Product> products;
  final void Function(Product) onTap;
  const ProductRows({super.key, required this.products, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Text('No products', style: TextStyle(color: Colors.grey));
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 235),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final p = products[i];
          return _Row(
            leading: SizedBox(
              width: 66,
              height: 66,
              child: Image.network(Config.resolveImageUrl(p.imageUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x11000000))),
            ),
            title: p.name,
            subtitle: _money(p.price),
            onTap: () => onTap(p),
          );
        },
      ),
    );
  }
}

/// Category list rows with the per-category icon and accent.
class CategoryRows extends StatelessWidget {
  final List<Category> categories;
  final Color Function(String) colorOf;
  final IconData Function(String) iconOf;
  final void Function(Category) onTap;
  const CategoryRows({
    super.key,
    required this.categories,
    required this.colorOf,
    required this.iconOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 235),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final c = categories[i];
            final color = colorOf(c.name);
            return _Row(
              leading: Container(
                width: 66,
                height: 66,
                color: color.withValues(alpha: 0.15),
                child: Icon(iconOf(c.name), color: color),
              ),
              title: c.name,
              subtitle: '${c.productCount} products',
              trailing: Icon(Icons.chevron_right, color: color),
              onTap: () => onTap(c),
            );
          },
        ),
      );
}

/// Generic short list of text rows (cart lines, reviews).
class InfoRows extends StatelessWidget {
  final List<({String title, String subtitle, String trailing})> rows;
  const InfoRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 235),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _Row(
            leading: const SizedBox(width: 12),
            title: rows[i].title,
            subtitle: rows[i].subtitle,
            trailing: Text(rows[i].trailing,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
      );
}
