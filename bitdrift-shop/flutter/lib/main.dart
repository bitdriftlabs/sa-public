import 'package:flutter/material.dart';

import 'app.dart';
import 'bd/capture.dart';
import 'config.dart';
import 'crash.dart';
import 'sim/simulator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime.now();

  // Start the SDK as early as possible so every subsequent log, screen view and
  // span is captured. Measure its duration for the cold-start span tree.
  final initStart = DateTime.now();
  final started = await Bd.start();
  final initMs = DateTime.now().difference(initStart).inMilliseconds;

  // Global fields — attached to every log/span, matching the other demos.
  await Bd.field('app_variant', Config.appVariant);
  await Bd.field('platform', Config.platform);
  await Bd.field('app_version', Config.appVersion);

  final ttiMs = DateTime.now().difference(t0).inMilliseconds;
  // The alpha SDK has no TTI API; emit it as a completed-span pair (the same
  // signal the other demos emit via paired logs).
  await Bd.logCompletedSpan('app_cold_start', ttiMs,
      fields: {'sdk_started': '$started'});
  await Bd.logCompletedSpan('app_cold_start.sdk_init', initMs);
  await Bd.info('app_launched', fields: {'sdk_started': '$started'});

  final navKey = GlobalKey<NavigatorState>();
  final sim = Simulator(navKey);
  runApp(ShopApp(navKey: navKey, sim: sim));

  // Crash loop (like the Android demo's "crash on payment"): when the loop is
  // active (scripts/crash-loop.sh set the property), run one journey right
  // after launch; the journey crashes at payment with a random crash shape.
  // The script relaunches the app — each pass is a fresh journey ending in a
  // fresh random crash in a live session.
  if (await Crash.loopActive()) {
    WidgetsBinding.instance.addPostFrameCallback((_) => sim.start(runs: 1));
  }
}
