import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_fx.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// Equalizer: presets plus one slider per band.
class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const EqualizerPage());

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  final s = SettingsService.instance;
  late final Future<AndroidEqualizerParameters?> _params = AudioFx.parameters();
  List<double> _gains = [];

  String _freq(double hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k' : '${hz.round()}';

  Future<void> _choose(EqPreset preset, AndroidEqualizerParameters prm) async {
    s.update((s) {
      s.eqPreset = preset;
      s.eqEnabled = true;
    });
    setState(() => _gains = AudioFx.gainsFor(preset, prm));
    await AudioFx.apply();
  }

  Future<void> _slide(int band, double v, AndroidEqualizerParameters prm) async {
    if (_gains.length != prm.bands.length) {
      _gains = AudioFx.gainsFor(s.eqPreset, prm);
    }
    setState(() => _gains[band] = v);
    s.update((s) {
      s.eqPreset = EqPreset.custom;
      s.eqEnabled = true;
      s.eqCustomGains = List.of(_gains);
    });
    await prm.bands[band].setGain(v);
    if (!await AudioFx.equalizer.enabledStream.first) {
      await AudioFx.equalizer.setEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Equalizer', style: displayStyle(22)),
        actions: [
          ListenableBuilder(
            listenable: s,
            builder: (context, _) => Switch(
              value: s.eqEnabled,
              activeThumbColor: AppColors.bg,
              activeTrackColor: AppColors.accent,
              onChanged: (v) async {
                s.update((s) => s.eqEnabled = v);
                await AudioFx.apply();
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<AndroidEqualizerParameters?>(
        future: _params,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final prm = snap.data;
          if (prm == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Play a song first, then open the equalizer again.\n'
                  '(Android only sets it up once music has loaded.)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ),
            );
          }
          if (_gains.length != prm.bands.length) {
            _gains = AudioFx.gainsFor(s.eqPreset, prm);
          }
          return ListenableBuilder(
            listenable: s,
            builder: (context, _) => Opacity(
              opacity: s.eqEnabled ? 1 : 0.45,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Text('PRESETS', style: sectionLabel),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in EqPreset.values)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: s.eqEnabled && s.eqPreset == preset,
                          onSelected: preset == EqPreset.custom &&
                                  s.eqCustomGains.isEmpty
                              ? null
                              : (_) => _choose(preset, prm),
                          selectedColor: AppColors.selectedFill,
                          side: BorderSide(
                              color: s.eqEnabled && s.eqPreset == preset
                                  ? AppColors.accent
                                  : AppColors.border),
                          labelStyle: TextStyle(
                            color: s.eqEnabled && s.eqPreset == preset
                                ? AppColors.accent
                                : AppColors.sub,
                            fontWeight: FontWeight.w600,
                          ),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text('BANDS', style: sectionLabel),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < prm.bands.length; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${_gains[i] > 0 ? '+' : ''}${_gains[i].toStringAsFixed(1)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.sub),
                                ),
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        activeTrackColor: AppColors.accent,
                                        inactiveTrackColor:
                                            AppColors.placeholder,
                                        thumbColor: AppColors.accent,
                                      ),
                                      child: Slider(
                                        min: prm.minDecibels,
                                        max: prm.maxDecibels,
                                        value: _gains[i].clamp(
                                            prm.minDecibels, prm.maxDecibels),
                                        onChanged: (v) => _slide(i, v, prm),
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_freq(prm.bands[i].centerFrequency / 1000)}Hz',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Drag a slider to make your own "Custom" sound. '
                    'Values are in decibels.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
