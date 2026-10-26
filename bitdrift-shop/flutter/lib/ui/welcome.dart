import 'package:flutter/material.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../config.dart';
import '../crash.dart';
import '../generated/spec.dart';
import '../sim/simulator.dart';
import 'container.dart';

/// Variant selector accents, matching the Android app's variant buttons
/// (used by the Advanced screen's persona row).
const Map<SimVariant, Color> kVariantColors = {
  SimVariant.control: Color(0xFF607D8B),
  SimVariant.variantA: Color(0xFF00BCD4),
  SimVariant.variantB: Color(0xFFFF9800),
};

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Map<String, dynamic> _info = const {};
  String _deviceCode = '';
  bool _busy = false;
  bool _loopActive = false;

  @override
  void initState() {
    super.initState();
    Bd.screenView(SpecScreen.welcome.screenName);
    _loadInfo();
    _loadLoop();
  }

  Future<void> _loadLoop() async {
    _loopActive = await Crash.loopActive();
    if (mounted) setState(() {});
  }

  Future<void> _loadInfo() async {
    try {
      _info = await Api.welcome();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Like the Android welcome screen: the button label becomes the code.
  Future<void> _genCode() async {
    setState(() => _busy = true);
    final code = await Bd.createDeviceCode();
    if (!mounted) return;
    setState(() {
      _deviceCode = code ?? '⚠ needs_sdk_key';
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sim = SimulatorScope.of(context);
    final store = (_info['store_name'] ?? 'ShopDemo').toString();
    final tagline = (_info['tagline'] ?? 'Premium Shopping Experience').toString();
    final promos = _info['promotions'];
    final firstPromo = promos is List && promos.isNotEmpty && promos.first is Map
        ? ((promos.first as Map)['title'] ?? '').toString()
        : '';
    final subtitle = firstPromo.isEmpty ? tagline : '$tagline\n$firstPromo';

    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) => ScreenContainer(
        title: store,
        subtitle: subtitle,
        step: 1,
        icon: Icons.storefront,
        color: const Color(0xFF2196F3),
        logoLines: [
          'SDK v${Config.captureSdkVersion} (alpha)',
          'App v${Config.appVersion}',
        ],
        children: [
          if (_loopActive)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.report, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Crash loop ACTIVE — journey runs on launch, crashes at payment (random)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          PrimaryButton(
            title: 'Browse Products',
            icon: Icons.menu,
            onPressed: sim.running ? null : () => Navigator.of(context).pushNamed('browse'),
          ),
          SecondaryButton(
            title: 'Search for Items',
            icon: Icons.search,
            onPressed: sim.running ? null : () => Navigator.of(context).pushNamed('search'),
          ),
          const Divider(height: 8),
          Row(
            children: [
              Expanded(
                child: ColorButton(
                  title: sim.running ? 'Stop' : 'Sim 3',
                  color: const Color(0xFFFF9800),
                  onPressed: sim.running ? sim.stop : () => sim.start(runs: 3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ColorButton(
                  title: 'SIM ∞',
                  color: const Color(0xFF9C27B0),
                  onPressed: sim.running ? null : () => sim.start(runs: 5, infinite: true),
                ),
              ),
            ],
          ),
          if (sim.running)
            Text(
              sim.infinite ? 'Running… (stop anytime)' : 'Run ${sim.currentRun} / ${sim.totalRuns} …',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          // Generating a code turns the label into the code (like the Android app).
          TonalButton(
            title: _deviceCode.isEmpty ? 'Device Code' : _deviceCode,
            fontSize: _deviceCode.isEmpty ? 14 : 11,
            onPressed: _busy ? null : _genCode,
          ),
          SecondaryButton(
            title: 'Advanced',
            icon: Icons.settings,
            onPressed: sim.running ? null : () => Navigator.of(context).pushNamed('diagnostics'),
          ),
        ],
      ),
    );
  }
}
