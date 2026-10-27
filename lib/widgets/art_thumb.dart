import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Album-art square with a music-note fallback.
class ArtThumb extends StatelessWidget {
  const ArtThumb({
    super.key,
    required this.artPath,
    this.size = 48,
    this.radius = 12,
    this.iconSize = 22,
  });

  final String? artPath;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final file = artPath == null || artPath!.isEmpty ? null : File(artPath!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: AppColors.surface,
        child: file == null
            ? Icon(Icons.music_note_rounded,
                color: AppColors.muted, size: iconSize)
            : Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * dpr).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Icon(Icons.music_note_rounded,
                    color: AppColors.muted, size: iconSize),
              ),
      ),
    );
  }
}

/// "More" menu for a song: Play next / Add to queue (+ optional extras).
class SongMenu extends StatelessWidget {
  const SongMenu({
    super.key,
    required this.onPlayNext,
    required this.onAddToQueue,
    this.onDelete,
  });

  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
      color: AppColors.surface2,
      onSelected: (v) {
        switch (v) {
          case 'next':
            onPlayNext();
          case 'queue':
            onAddToQueue();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'next',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_play_rounded),
            title: Text('Play next'),
          ),
        ),
        const PopupMenuItem(
          value: 'queue',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.queue_music_rounded),
            title: Text('Add to queue'),
          ),
        ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('Delete'),
            ),
          ),
      ],
    );
  }
}

void showQueuedSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 2),
    ));
}
