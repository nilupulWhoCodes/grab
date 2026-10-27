import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'settings_service.dart';

/// Equalizer (inside the player's audio pipeline) and the native visualizer.
class AudioFx {
  AudioFx._();

  /// Lives in the AudioPlayer's pipeline (see PlayerController).
  static final AndroidEqualizer equalizer = AndroidEqualizer();

  static AndroidEqualizerParameters? _params;

  /// Band info; only available after the player has loaded a song.
  static Future<AndroidEqualizerParameters?> parameters() async {
    if (!Platform.isAndroid) return null;
    if (_params != null) return _params;
    try {
      _params = await equalizer.parameters.timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
    return _params;
  }

  /// Gain (dB) for a band at [hz] in a preset, before clamping.
  static double _presetGain(EqPreset p, double hz) => switch (p) {
        EqPreset.flat || EqPreset.custom => 0,
        EqPreset.bassBoost => hz < 150
            ? 7
            : hz < 400
                ? 4.5
                : hz < 1000
                    ? 1
                    : 0,
        EqPreset.vocal => hz < 200
            ? -2.5
            : hz < 800
                ? 1.5
                : hz < 4000
                    ? 4.5
                    : hz < 8000
                        ? 2
                        : 0,
        EqPreset.treble => hz < 1000
            ? 0
            : hz < 3000
                ? 2.5
                : hz < 8000
                    ? 5
                    : 6.5,
      };

  static List<double> gainsFor(EqPreset p, AndroidEqualizerParameters prm) {
    final s = SettingsService.instance;
    return [
      for (var i = 0; i < prm.bands.length; i++)
        (p == EqPreset.custom && i < s.eqCustomGains.length
                ? s.eqCustomGains[i]
                : _presetGain(p, prm.bands[i].centerFrequency / 1000))
            .clamp(prm.minDecibels, prm.maxDecibels)
            .toDouble(),
    ];
  }

  /// Applies the saved equalizer settings to the player.
  static Future<void> apply() async {
    if (!Platform.isAndroid) return;
    final s = SettingsService.instance;
    try {
      await equalizer.setEnabled(s.eqEnabled);
      if (!s.eqEnabled) return;
      final prm = await parameters();
      if (prm == null) return;
      final gains = gainsFor(s.eqPreset, prm);
      for (var i = 0; i < prm.bands.length; i++) {
        await prm.bands[i].setGain(gains[i]);
      }
    } catch (_) {}
  }

  // --- Visualizer (native android.media.audiofx.Visualizer) ----------------

  static const _visualizer = EventChannel('grab/visualizer');

  /// 24 frequency bands (0..1, low → high) for the given audio session.
  static Stream<List<double>> visualizerBands(int sessionId) => _visualizer
      .receiveBroadcastStream(sessionId)
      .map((e) => List<double>.from(e as List));
}
