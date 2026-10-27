import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme.dart';

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';

/// Small bar above the player when a newer version is on GitHub.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final u = UpdateService.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final info = u.available;
        final show = info != null &&
            !u.bannerDismissed &&
            (u.state == UpdateState.available ||
                u.state == UpdateState.downloading);
        if (!show) return const SizedBox.shrink();
        final downloading = u.state == UpdateState.downloading;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: BoxDecoration(
            color: AppColors.selectedFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  downloading
                      ? 'Downloading update… ${(u.progress * 100).round()}%'
                      : 'Update available · ${info.version}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              if (!downloading) ...[
                TextButton(
                  onPressed: u.install,
                  child: const Text('Update'),
                ),
                IconButton(
                  tooltip: 'Later',
                  onPressed: u.dismissBanner,
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.muted),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// About sheet: version + "Check for updates".
Future<void> showAboutSheet(BuildContext context) {
  final u = UpdateService.instance;
  if (u.state == UpdateState.idle || u.state == UpdateState.error) u.check();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: ListenableBuilder(
          listenable: u,
          builder: (context, _) {
            final info = u.available;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.music_note_rounded,
                          color: AppColors.accent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Grab', style: displayStyle(22)),
                          Text('Version ${UpdateService.currentVersion}',
                              style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                switch (u.state) {
                  UpdateState.checking => const _Line(
                      icon: Icons.sync_rounded,
                      text: 'Checking for updates…'),
                  UpdateState.upToDate => const _Line(
                      icon: Icons.check_circle_rounded,
                      text: 'You have the latest version.'),
                  UpdateState.error => _Line(
                      icon: Icons.error_outline_rounded,
                      text: u.error ?? 'Could not check for updates.'),
                  UpdateState.downloading => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(
                            icon: Icons.download_rounded,
                            text:
                                'Downloading ${info?.version ?? ''}… ${(u.progress * 100).round()}%'),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: u.progress,
                          minHeight: 4,
                          backgroundColor: AppColors.placeholder,
                        ),
                      ],
                    ),
                  UpdateState.available when info != null => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Line(
                            icon: Icons.system_update_rounded,
                            text:
                                'Version ${info.version} is available${info.size > 0 ? ' (${_mb(info.size)})' : ''}.'),
                        if (info.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(info.notes,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.sub,
                                  height: 1.4)),
                        ],
                      ],
                    ),
                  _ => const SizedBox.shrink(),
                },
                const SizedBox(height: 20),
                if (u.state == UpdateState.available && info != null)
                  FilledButton.icon(
                    onPressed: u.install,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.bg,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: Text('Update to ${info.version}'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: u.state == UpdateState.checking ||
                            u.state == UpdateState.downloading
                        ? null
                        : () => u.check(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Check for updates'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Updates come from the Releases page of nilupulWhoCodes/grab on GitHub. '
                  'Android will ask you to allow installs from Grab the first time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      );
}
