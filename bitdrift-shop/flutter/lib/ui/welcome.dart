import 'package:flutter/material.dart';

import '../api/client.dart';
import '../bd/capture.dart';
import '../config.dart';
import '../sim/simulator.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Map<String, dynamic> _info = const {};
  SimVariant _variant = SimVariant.control;

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
            SegmentedButton<SimVariant>(
              segments: const [
                ButtonSegment(value: SimVariant.control, label: Text('Control')),
                ButtonSegment(value: SimVariant.variantA, label: Text('Variant A')),
                ButtonSegment(value: SimVariant.variantB, label: Text('Variant B')),
              ],
              selected: {_variant},
              onSelectionChanged: (s) {
                setState(() => _variant = s.first);
                sim.setVariant(_variant);
              },
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
                  child: FilledButton(
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
                  child: OutlinedButton(
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
