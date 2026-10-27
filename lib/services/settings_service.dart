import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum VisualizerStyle { bars, glow, off }

enum EqPreset { flat, bassBoost, vocal, treble, custom }

extension EqPresetLabel on EqPreset {
  String get label => switch (this) {
        EqPreset.flat => 'Flat',
        EqPreset.bassBoost => 'Bass boost',
        EqPreset.vocal => 'Vocal',
        EqPreset.treble => 'Treble',
        EqPreset.custom => 'Custom',
      };
}

/// App settings, saved on the phone.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final instance = SettingsService._();

  /// Seconds to fade between songs (0 = off).
  double crossfadeSeconds = 0;
  bool shakeToShuffle = true;
  VisualizerStyle visualizer = VisualizerStyle.bars;
  bool albumColours = true;

  bool eqEnabled = false;
  EqPreset eqPreset = EqPreset.flat;
  List<double> eqCustomGains = [];

  Timer? _saveTimer;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<void> load() async {
    try {
      final j = jsonDecode(await (await _file()).readAsString())
          as Map<String, dynamic>;
      crossfadeSeconds = (j['crossfade'] as num?)?.toDouble() ?? 0;
      shakeToShuffle = j['shake'] as bool? ?? true;
      visualizer = VisualizerStyle.values.firstWhere(
          (v) => v.name == j['visualizer'],
          orElse: () => VisualizerStyle.bars);
      albumColours = j['albumColours'] as bool? ?? true;
      eqEnabled = j['eqEnabled'] as bool? ?? false;
      eqPreset = EqPreset.values.firstWhere((v) => v.name == j['eqPreset'],
          orElse: () => EqPreset.flat);
      eqCustomGains = ((j['eqCustom'] as List?) ?? [])
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {
      // First run: defaults.
    }
    notifyListeners();
  }

  void update(void Function(SettingsService s) change) {
    change(this);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await (await _file()).writeAsString(jsonEncode({
          'crossfade': crossfadeSeconds,
          'shake': shakeToShuffle,
          'visualizer': visualizer.name,
          'albumColours': albumColours,
          'eqEnabled': eqEnabled,
          'eqPreset': eqPreset.name,
          'eqCustom': eqCustomGains,
        }));
      } catch (_) {}
    });
  }
}
