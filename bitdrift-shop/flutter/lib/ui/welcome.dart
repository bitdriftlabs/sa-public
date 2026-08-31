import 'package:flutter/material.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../config.dart';
import '../sim/simulator.dart';

/// Variant selector accents, matching the Android app's variant buttons.
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
  SimVariant _variant = SimVariant.control;
  String _deviceCode = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Bd.screenView('Welcome');
    _loadInfo();
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
    final store = (_info['store_name'] ?? 'Bitdrift Shop').toString();
    final tagline = (_info['tagline'] ?? '').toString();
    final promos = _info['promotions'];
    // Dimmed label, like the Android app's version block.
    final versionStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
    );
    // Unselected variant-button colors, matching the Android app (this
    // Flutter's resolveWith-less API: theme values are captured here).
    final unselectedBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final unselectedFg = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: Text(store),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('diagnostics'),
            child: const Text('Diagnostics'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: sim,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Device code button (like the Android welcome screen): generating
            // a code turns the button blue and the label becomes the code.
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    _deviceCode.isEmpty ? unselectedBg : const Color(0xFF2196F3),
                foregroundColor: _deviceCode.isEmpty
                    ? unselectedFg
                    : Colors.white,
                textStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: _deviceCode.isEmpty ? 14 : 11,
                ),
              ),
              onPressed: _busy ? null : _genCode,
              child: Text(_deviceCode.isEmpty ? 'Device Code' : _deviceCode),
            ),
            const SizedBox(height: 16),
            // Version block, like the Android app's welcome header.
            Center(
              child: Column(
                children: [
                  Text(
                    'SDK v${Config.captureSdkVersion} (alpha)',
                    style: versionStyle,
                  ),
                  const SizedBox(height: 6),
                  Text('App v${Config.appVersion}', style: versionStyle),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (tagline.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tagline, style: const TextStyle(color: Colors.grey)),
              ),
            if (promos is List)
              ...promos.whereType<Map<String, dynamic>>().map((p) {
                final sub = [
                  (p['discount'] ?? '').toString(),
                  (p['code'] ?? '').toString(),
                ].where((s) => s.isNotEmpty).join(' · ');
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.card_giftcard),
                    title: Text((p['title'] ?? 'Promo').toString()),
                    subtitle: sub.isEmpty ? null : Text(sub),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Text('Persona', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            // Like the Android app: a row of buttons, colored when selected.
            Row(
              children: [
                for (final v in SimVariant.values) ...[
                  if (v != SimVariant.control) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _variant == v ? kVariantColors[v] : unselectedBg,
                        foregroundColor:
                            _variant == v ? Colors.white : unselectedFg,
                      ),
                      onPressed: () {
                        setState(() => _variant = v);
                        sim.setVariant(_variant);
                      },
                      child: Text(simVariantLabel(v)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Text('Browse', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, route) in const [
                  ('Browse', 'browse'),
                  ('Search', 'search'),
                  ('Featured', 'featured'),
                  ('Categories', 'categories'),
                  ('Cart', 'cart'),
                ])
                  ActionChip(
                    label: Text(label),
                    onPressed: () => Navigator.of(context).pushNamed(route),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Simulation', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  // Android "Sim 10" button color.
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: sim.running
                        ? sim.stop
                        : () {
                            sim.setVariant(_variant);
                            sim.start(runs: 3);
                          },
                    child:
                        sim.running ? const Text('Stop') : const Text('Start (3 runs)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Android "SIM ∞" button color.
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF9C27B0),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: sim.running
                        ? null
                        : () {
                            sim.setVariant(_variant);
                            sim.start(runs: 5, infinite: true);
                          },
                    child: const Text('Infinite'),
                  ),
                ),
              ],
            ),
            if (sim.running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  sim.infinite
                      ? 'Running… (stop anytime)'
                      : 'Run ${sim.currentRun} / ${sim.totalRuns} …',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
