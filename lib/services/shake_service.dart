import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Detects a deliberate shake: 4 strong back-and-forth jolts within 1.2 s.
///
/// Picking the phone up or putting it down gives one or two jolts in roughly
/// one direction, and walking is far weaker, so neither triggers it. After a
/// shake there's a cool-down so one long shake only counts once.
class ShakeService {
  ShakeService._();
  static final instance = ShakeService._();

  static const _threshold = 16.0; // m/s² beyond gravity (~1.6 g)
  static const _window = Duration(milliseconds: 1200);
  static const _minGap = Duration(milliseconds: 70);
  static const _cooldown = Duration(milliseconds: 2500);
  static const _peaksNeeded = 4;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  final _peaks = <(DateTime, int, int)>[]; // (time, axis, direction)
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  void Function()? onShake;

  bool get running => _sub != null;

  void start() {
    _sub ??= userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onEvent, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _peaks.clear();
  }

  void _onEvent(UserAccelerometerEvent e) {
    final now = DateTime.now();
    if (now.isBefore(_quietUntil)) return;

    // Strongest axis of this sample.
    final ax = e.x.abs(), ay = e.y.abs(), az = e.z.abs();
    final (double v, int axis) = ax >= ay && ax >= az
        ? (e.x, 0)
        : ay >= az
            ? (e.y, 1)
            : (e.z, 2);
    if (v.abs() < _threshold) return;
    final dir = v > 0 ? 1 : -1;

    _peaks.removeWhere((p) => now.difference(p.$1) > _window);
    if (_peaks.isNotEmpty) {
      final last = _peaks.last;
      if (now.difference(last.$1) < _minGap) return; // same jolt
      if (last.$3 == dir) return; // must go back and forth
    }
    _peaks.add((now, axis, dir));

    if (_peaks.length >= _peaksNeeded) {
      // Most jolts should be along the same axis (a real shake).
      final counts = [0, 0, 0];
      for (final p in _peaks) {
        counts[p.$2]++;
      }
      final best = counts.reduce((a, b) => a > b ? a : b);
      if (best >= _peaksNeeded - 1) {
        _peaks.clear();
        _quietUntil = now.add(_cooldown);
        HapticFeedback.heavyImpact();
        onShake?.call();
      }
    }
  }
}
