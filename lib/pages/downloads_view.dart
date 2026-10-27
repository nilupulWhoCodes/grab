import 'dart:io';

import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../services/player_controller.dart';
import '../theme.dart';
import '../services/playlist_service.dart';
import '../widgets/art_thumb.dart';
import '../widgets/playing_bars.dart';

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        DownloadManager.instance,
        PlayerController.instance,
        PlaylistService.instance,
      ]),
      builder: (context, _) {
        final manager = DownloadManager.instance;
        final active = manager.active;
        final library = manager.library;
        final player = PlayerController.instance;

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: manager.refreshLibrary,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    if (active.isNotEmpty) ...[
                      const Text('IN PROGRESS', style: sectionLabel),
                      const SizedBox(height: 10),
                      for (final t in active) ...[
                        _TaskCard(task: t),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Text('SAVED · ${library.length}', style: sectionLabel),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (library.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Column(
                          children: [
                            Icon(Icons.library_music_outlined,
                                size: 40, color: AppColors.muted),
                            SizedBox(height: 12),
                            Text(
                              'Nothing saved yet.\nOpen a video in Browse and tap MP3.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.muted, height: 1.5),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final f in library)
                        _TrackRow(
                          file: f,
                          isCurrent: player.currentPath == f.path,
                          isPlaying:
                              player.currentPath == f.path && player.isPlaying,
                          onTap: () => PlaylistService.instance
                                  .isDisabled(f.path)
                              ? showDisabledSnack(context, f.path)
                              : player.play(
                                  f.path, library.map((e) => e.path).toList()),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final DownloadTask task;

  String get _status => switch (task.status) {
        TaskStatus.queued => 'Waiting…',
        TaskStatus.fetching => task.attempt == 0
            ? 'Getting audio stream…'
            : 'That source failed, trying another…',
        TaskStatus.downloading => task.attempt > 1
            ? 'Downloading · source ${task.attempt}'
            : 'Downloading · ${task.bitrate} kbps',
        TaskStatus.converting => 'Converting to MP3…',
        TaskStatus.failed => task.error ?? 'Failed',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final failed = task.status == TaskStatus.failed;
    final m = DownloadManager.instance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 48,
                  height: 48,
                  color: AppColors.placeholder,
                  child: Image.network(task.info.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(_status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: failed
                                ? const Color(0xFFFFB4A8)
                                : AppColors.muted)),
                  ],
                ),
              ),
              if (failed) ...[
                _SquareButton(
                  icon: Icons.refresh_rounded,
                  label: 'Retry',
                  onTap: () => m.retry(task),
                ),
                const SizedBox(width: 6),
                _SquareButton(
                  icon: Icons.close_rounded,
                  label: 'Dismiss',
                  onTap: () => m.dismiss(task),
                ),
              ] else
                _SquareButton(
                  icon: Icons.close_rounded,
                  label: 'Cancel download',
                  onTap: () => m.cancel(task),
                ),
            ],
          ),
          if (!failed) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: task.status == TaskStatus.fetching ||
                        task.status == TaskStatus.queued
                    ? null
                    : task.progress,
                minHeight: 6,
                backgroundColor: AppColors.placeholder,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.total > 0
                      ? '${_mb(task.received)} of ${_mb(task.total)}'
                      : '',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text('${(task.progress * 100).round()}%',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: AppColors.sub),
          ),
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.file,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final File file;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  Future<void> _confirmDelete(BuildContext context) async {
    final title = PlayerController.titleOf(file.path);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this MP3?'),
        content: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PlayerController.instance.forget(file.path);
      await DownloadManager.instance.deleteFile(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stat = file.statSync();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Stack(
              children: [
                ArtThumb(
                    artPath: PlayerController.artOf(file.path),
                    size: 48,
                    radius: 12),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0x99000000)
                          : const Color(0x55000000),
                      borderRadius: BorderRadius.circular(12),
                      border: isCurrent
                          ? Border.all(color: AppColors.accent, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: isCurrent
                        ? PlayingBars(playing: isPlaying, size: 20)
                        : const Icon(Icons.play_arrow_rounded,
                            color: AppColors.text, semanticLabel: 'Play'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PlayerController.titleOf(file.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppColors.accent : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${_mb(stat.size)} · ${_date(stat.modified)}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ),
            SongMenu(
              path: file.path,
              onDelete: () => _confirmDelete(context),
            ),
          ],
        ),
      ),
    );
  }
}
