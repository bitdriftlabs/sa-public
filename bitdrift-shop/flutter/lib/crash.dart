import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import 'bd/capture.dart';

/// Crash injection, limited to the shapes that work in Flutter.
///
/// The Android demo's JVM-exception catalog is not reproducible here: the alpha
/// Flutter SDK has no Dart exception bridge — uncaught Dart exceptions are
/// logged by the VM and the app keeps running. What works, mirroring the
/// Android demo's native-signal entries (Os.kill), is raising native signals
/// in our own process via libc:
///  - `sigabrt` / `sigsegv` / `sigbus` — real native crashes (distinct
///    signals, like Android's native_sigabrt / native_sigsegv / native_sigbus).
///  - `process_exit`  — exit(1), a hard exit with no signal.
class Crash {
  static const List<String> variants = ['sigabrt', 'sigsegv', 'sigbus', 'process_exit'];

  static DynamicLibrary get _libc {
    for (final p in [
      '/system/lib64/libc.so',
      '/system/lib/libc.so',
      'libc.so',
    ]) {
      try {
        return DynamicLibrary.open(p);
      } catch (_) {}
    }
    throw StateError('libc not found');
  }

  /// Raise [signum] in our own process (POSIX numbers: 6=ABRT, 7=BUS, 11=SEGV).
  static void _raise(int signum) {
    final libc = _libc;
    final getpid =
        libc.lookupFunction<IntPtr Function(), int Function()>('getpid');
    final kill = libc.lookupFunction<
        IntPtr Function(Int32, Int32), int Function(int, int)>('kill');
    kill(getpid(), signum);
  }

  /// Inject a crash. The app is not expected to survive this call.
  static Future<void> inject(String name) async {
    await Bd.warning('crash_injection', fields: {'crash': name});
    switch (name) {
      case 'sigsegv':
        _raise(11);
      case 'sigbus':
        _raise(7);
      case 'process_exit':
        exit(1);
      default:
        _raise(6);
    }
  }

  /// Inject a random crash shape (like the Android demo's crash cycling).
  static Future<void> injectRandom() {
    final name = variants[Random().nextInt(variants.length)];
    return inject(name);
  }

  /// Crash loop state lives in a system property (persists across app death):
  /// `scripts/crash-loop.sh` sets it on (non-zero) and clears it on exit.
  /// Mirrors the Android demo's persisted crash-loop flag.
  ///
  /// The app can read the property but cannot write it — on this device
  /// SELinux denies untrusted_app the property-service socket — so the loop
  /// is script-driven (like the Android demo's watchdog).
  static const String prop = 'debug.bd_shop_crash';

  /// Whether the crash loop is active (the script set the property).
  static Future<bool> loopActive() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final r = await Process.run('getprop', [prop]);
      final v = (r.stdout.toString()).trim();
      return v.isNotEmpty && v != '0';
    } catch (_) {
      return false;
    }
  }
}
