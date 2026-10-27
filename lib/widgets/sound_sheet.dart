import 'package:flutter/material.dart';

import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../services/sound_fx.dart';
import '../theme.dart';

/// Speed / pitch / reverb sheet opened from Now Playing.
Future<void> showSoundSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _SoundSheet(),
    );

class _SoundSheet extends StatefulWidget {
  const _SoundSheet();

  @override
  State<_SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<_SoundSheet> {
  final s = SettingsService.instance;
  double? _exporting; // progress 0..1 while saving

  Future<void> _export() async {
    final path = PlayerController.instance.currentPath;
    if (path == null) return;
    setState(() => _exporting = 0);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = await SoundFx.exportCurrent(path,
          onProgress: (v) {
            if (mounted) setState(() => _exporting = v);
          });
      messenger.showSnackBar(SnackBar(
        content: Text('Saved "${f.path.split('/').last}" to your music'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) =>
      Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Row(
          children: [
            SizedBox(
                width: 56,
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(
              child: Slider(
                min: 0.5,
                max: 2.0,
                divisions: 30,
                value: value.clamp(0.5, 2.0),
                activeColor: AppColors.accent,
                inactiveColor: AppColors.placeholder,
                label: '${value.toStringAsFixed(2)}×',
                onChanged: enabled ? onChanged : null,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text('${value.toStringAsFixed(2)}×',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.sub)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF45484F),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Sound', style: displayStyle(22)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in FxMode.values)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: s.fxMode == m,
                      onSelected: m == FxMode.custom
                          ? null
                          : (_) => SoundFx.setMode(m),
                      selectedColor: AppColors.selectedFill,
                      side: BorderSide(
                          color: s.fxMode == m
                              ? AppColors.accent
                              : AppColors.border),
                      labelStyle: TextStyle(
                        color:
                            s.fxMode == m ? AppColors.accent : AppColors.sub,
                        fontWeight: FontWeight.w600,
                      ),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _slider(
                label: 'Speed',
                value: s.speed,
                onChanged: (v) => SoundFx.change((s) => s.speed = v),
              ),
              _slider(
                label: 'Pitch',
                value: s.effectivePitch,
                enabled: !s.linkPitch,
                onChanged: (v) => SoundFx.change((s) => s.pitch = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Link pitch to speed'),
                subtitle: const Text(
                    'On: faster sounds higher, like a record. Off: change them separately.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                value: s.linkPitch,
                activeThumbColor: AppColors.bg,
                activeTrackColor: AppColors.accent,
                onChanged: (v) => SoundFx.change((s) {
                  if (!v) s.pitch = s.speed;
                  s.linkPitch = v;
                }),
              ),
              const SizedBox(height: 4),
              const Text('REVERB', style: sectionLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in ReverbPreset.values)
                    ChoiceChip(
                      label: Text(r.label),
                      selected: s.reverb == r,
                      onSelected: (_) => SoundFx.change((s) => s.reverb = r),
                      selectedColor: AppColors.selectedFill,
                      side: BorderSide(
                          color: s.reverb == r
                              ? AppColors.accent
                              : AppColors.border),
                      labelStyle: TextStyle(
                        color: s.reverb == r ? AppColors.accent : AppColors.sub,
                        fontWeight: FontWeight.w600,
                      ),
                      showCheckmark: false,
                    ),
                ],
              ),
              if (SoundFx.reverbError != null) ...[
                const SizedBox(height: 8),
                Text(SoundFx.reverbError!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFFFB4A8))),
              ],
              const SizedBox(height: 20),
              if (_exporting != null) ...[
                Text(
                    'Saving new MP3… ${(_exporting! * 100).round()}%',
                    style: const TextStyle(color: AppColors.sub)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _exporting! > 0 ? _exporting : null,
                  minHeight: 4,
                  backgroundColor: AppColors.placeholder,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: s.fxMode == FxMode.normal
                            ? null
                            : () => SoundFx.setMode(FxMode.normal),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.text,
                          side: const BorderSide(color: AppColors.border),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed:
                            s.fxMode == FxMode.normal ? null : _export,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.bg,
                          disabledBackgroundColor: AppColors.surface2,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('Save as new MP3'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              const Text(
                'Applies to everything you play until you reset it. '
                '"Save as new MP3" makes a copy of this song with these settings.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
