import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum VisualizerStyle { bars, glow, both, off }

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

enum FxMode { normal, nightcore, slowedReverb, custom }

extension FxModeLabel on FxMode {
  String get label => switch (this) {
        FxMode.normal => 'Normal',
        FxMode.nightcore => 'Nightcore',
        FxMode.slowedReverb => 'Slowed + reverb',
        FxMode.custom => 'Custom',
      };
}

/// Android PresetReverb presets (same order as the platform constants).
enum ReverbPreset { none, smallRoom, mediumRoom, largeRoom, mediumHall, largeHall, plate }

extension ReverbLabel on ReverbPreset {
  String get label => switch (this) {
        ReverbPreset.none => 'None',
        ReverbPreset.smallRoom => 'Small room',
        ReverbPreset.mediumRoom => 'Medium room',
        ReverbPreset.largeRoom => 'Large room',
        ReverbPreset.mediumHall => 'Medium hall',
        ReverbPreset.largeHall => 'Large hall',
        ReverbPreset.plate => 'Plate',
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

  // Sound modes (speed / pitch / reverb).
  FxMode fxMode = FxMode.normal;
  double speed = 1;
  double pitch = 1;
  bool linkPitch = true;
  ReverbPreset reverb = ReverbPreset.none;

  double get effectivePitch => linkPitch ? speed : pitch;

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
      fxMode = FxMode.values.firstWhere((v) => v.name == j['fxMode'],
          orElse: () => FxMode.normal);
      speed = (j['speed'] as num?)?.toDouble() ?? 1;
      pitch = (j['pitch'] as num?)?.toDouble() ?? 1;
      linkPitch = j['linkPitch'] as bool? ?? true;
      reverb = ReverbPreset.values.firstWhere((v) => v.name == j['reverb'],
          orElse: () => ReverbPreset.none);
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
          'fxMode': fxMode.name,
          'speed': speed,
          'pitch': pitch,
          'linkPitch': linkPitch,
          'reverb': reverb.name,
        }));
      } catch (_) {}
    });
  }
}
