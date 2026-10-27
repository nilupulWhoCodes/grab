import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/shake_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/update_ui.dart';
import 'equalizer_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const SettingsPage());

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Settings', style: displayStyle(22)),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            const _Header('SOUND'),
            _Tile(
              icon: Icons.equalizer_rounded,
              title: 'Equalizer',
              subtitle: s.eqEnabled ? s.eqPreset.label : 'Off',
              onTap: () => Navigator.of(context).push(EqualizerPage.route()),
            ),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.blur_linear_rounded,
                          color: AppColors.accent),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('Crossfade',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        s.crossfadeSeconds == 0
                            ? 'Off'
                            : '${s.crossfadeSeconds.round()} s',
                        style: const TextStyle(color: AppColors.sub),
                      ),
                    ],
                  ),
                  Slider(
                    min: 0,
                    max: 12,
                    divisions: 12,
                    value: s.crossfadeSeconds,
                    activeColor: AppColors.accent,
                    inactiveColor: AppColors.placeholder,
                    label: s.crossfadeSeconds == 0
                        ? 'Off'
                        : '${s.crossfadeSeconds.round()} s',
                    onChanged: (v) => s.update((s) => s.crossfadeSeconds = v),
                  ),
                  const Text(
                    'Fades the end of each song out and the next one in. '
                    'Songs already play back-to-back with no gap.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const _Header('NOW PLAYING'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, color: AppColors.accent),
                      SizedBox(width: 14),
                      Text('Visualizer',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<VisualizerStyle>(
                    segments: const [
                      ButtonSegment(
                          value: VisualizerStyle.bars,
                          label: Text('Bars')),
                      ButtonSegment(
                          value: VisualizerStyle.glow,
                          label: Text('Glow')),
                      ButtonSegment(
                          value: VisualizerStyle.both,
                          label: Text('Both')),
                      ButtonSegment(
                          value: VisualizerStyle.off,
                          label: Text('Off')),
                    ],
                    selected: {s.visualizer},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) =>
                        s.update((s) => s.visualizer = v.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.selectedFill,
                      selectedForegroundColor: AppColors.accent,
                      foregroundColor: AppColors.sub,
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Android asks for the audio-recording permission for '
                    'visualizers. Grab only reads its own music, never the mic.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _SwitchTile(
              icon: Icons.palette_outlined,
              title: 'Colours from album art',
              subtitle: 'Now Playing takes on each cover\'s colours',
              value: s.albumColours,
              onChanged: (v) => s.update((s) => s.albumColours = v),
            ),
            const _Header('GESTURES'),
            _SwitchTile(
              icon: Icons.vibration_rounded,
              title: 'Shake to shuffle',
              subtitle:
                  'Shake the phone hard back and forth 3–4 times to jump to a '
                  'random song. Picking the phone up won\'t trigger it.',
              value: s.shakeToShuffle,
              onChanged: (v) {
                s.update((s) => s.shakeToShuffle = v);
                v ? ShakeService.instance.start() : ShakeService.instance.stop();
              },
            ),
            const _Header('ABOUT'),
            _Tile(
              icon: Icons.system_update_rounded,
              title: 'About & updates',
              subtitle: 'Version ${UpdateService.currentVersion}',
              onTap: () => showAboutSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text, style: sectionLabel),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            leading: Icon(icon, color: AppColors.accent),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle:
                Text(subtitle, style: const TextStyle(color: AppColors.muted)),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            onTap: onTap,
          ),
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: SwitchListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            secondary: Icon(icon, color: AppColors.accent),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle:
                Text(subtitle, style: const TextStyle(color: AppColors.muted)),
            value: value,
            activeThumbColor: AppColors.bg,
            activeTrackColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ),
      );
}
