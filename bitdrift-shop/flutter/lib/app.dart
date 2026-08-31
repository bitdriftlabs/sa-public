import 'package:flutter/material.dart';

import 'sim/simulator.dart';
import 'ui/screens.dart';
import 'ui/welcome.dart';

class ShopApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navKey;
  final Simulator sim;

  const ShopApp({super.key, required this.navKey, required this.sim});

  @override
  Widget build(BuildContext context) {
    return SimulatorScope(
      sim: sim,
      child: MaterialApp(
        title: 'Bitdrift Shop',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        initialRoute: '/',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4A6CF7),
            brightness: Brightness.dark,
          ),
        ),
        routes: {
          '/': (_) => const WelcomeScreen(),
          'browse': (_) => const BrowseScreen(),
          'search': (_) => const SearchScreen(),
          'featured': (_) => const FeaturedScreen(),
          'categories': (_) => const CategoriesScreen(),
          'category': (_) => const CategoryScreen(),
          'product': (_) => const ProductScreen(),
          'reviews': (_) => const ReviewsScreen(),
          'cart': (_) => const CartScreen(),
          'wishlist': (_) => const WishlistScreen(),
          'checkout_guest': (_) => const CheckoutScreen(guest: true),
          'checkout_signin': (_) => const CheckoutScreen(guest: false),
          'payment_card': (_) => const PaymentScreen(method: 'card'),
          'payment_applepay': (_) => const PaymentScreen(method: 'applePay'),
          'payment_paypal': (_) => const PaymentScreen(method: 'paypal'),
          'payment_androidpay': (_) => const PaymentScreen(method: 'androidPay'),
          'payment_failed': (_) => const PaymentFailedScreen(),
          'confirmation': (_) => const ConfirmationScreen(),
          'diagnostics': (_) => const DiagnosticsScreen(),
        },
      ),
    );
  }
}
