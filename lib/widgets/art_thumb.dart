import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/player_controller.dart';
import '../services/playlist_service.dart';
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

/// Large cover for Now Playing: shows the whole image (no zoom/crop).
/// Wide pictures such as YouTube thumbnails sit on a blurred copy of
/// themselves, so the square is always filled.
class ArtCover extends StatelessWidget {
  const ArtCover({
    super.key,
    required this.artPath,
    required this.size,
    this.radius = 28,
  });

  final String artPath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final file = File(artPath);
    Widget fallback() => Container(
          color: AppColors.surface,
          alignment: Alignment.center,
          child: const Icon(Icons.music_note_rounded,
              size: 56, color: AppColors.muted),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred, darkened fill behind the picture.
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                    Color(0x66000000), BlendMode.darken),
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => fallback(),
                ),
              ),
            ),
            // The whole picture, never cropped.
            Image.file(
              file,
              fit: BoxFit.contain,
              cacheWidth: (size * dpr).round(),
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ],
        ),
      ),
    );
  }
}

/// "More" menu for a song: Play next, Add to queue, Favourite,
/// Add to playlist, plus optional Remove-from-playlist / Delete.
class SongMenu extends StatelessWidget {
  const SongMenu({
    super.key,
    required this.path,
    this.onRemoveFromPlaylist,
    this.onDelete,
  });

  final String path;
  final VoidCallback? onRemoveFromPlaylist;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    final lists = PlaylistService.instance;
    final title = PlayerController.titleOf(path);
    final fav = lists.isFavourite(path);
    final off = lists.isDisabled(path);
    final folderOff = lists.isFolderDisabled(path);
    final folder = PlaylistService.folderName(path);

    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon),
            title: Text(label),
          ),
        );

    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
      color: AppColors.surface2,
      onSelected: (v) {
        switch (v) {
          case 'next':
            p.playNext(path);
            showQueuedSnack(context, 'Playing next: $title');
          case 'queue':
            p.addToQueue(path);
            showQueuedSnack(context, 'Added to queue: $title');
          case 'fav':
            lists.toggleFavourite(path);
            showQueuedSnack(context,
                fav ? 'Removed from Favourites' : 'Added to Favourites');
          case 'playlist':
            showAddToPlaylistSheet(context, path);
          case 'disable':
            lists.setDisabled(path, true);
            p.dropDisabled();
            showUndoSnack(context, 'Disabled: $title',
                () => lists.setDisabled(path, false));
          case 'enable':
            lists.setDisabled(path, false);
            showQueuedSnack(context, 'Enabled: $title');
          case 'disableFolder':
            lists.setFolderDisabled(path, true);
            p.dropDisabled();
            showUndoSnack(context, 'Disabled every song in "$folder"',
                () => lists.setFolderDisabled(path, false));
          case 'enableFolder':
            lists.setFolderDisabled(path, false);
            showQueuedSnack(context, 'Enabled every song in "$folder"');
          case 'remove':
            onRemoveFromPlaylist?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        if (!off) ...[
          item('next', Icons.playlist_play_rounded, 'Play next'),
          item('queue', Icons.queue_music_rounded, 'Add to queue'),
        ],
        item('fav', fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            fav ? 'Remove from Favourites' : 'Add to Favourites'),
        item('playlist', Icons.playlist_add_rounded, 'Add to playlist…'),
        if (off)
          item('enable', Icons.check_circle_outline_rounded, 'Enable song')
        else
          item('disable', Icons.block_rounded, 'Disable song'),
        if (folderOff)
          item('enableFolder', Icons.folder_open_rounded,
              'Enable folder "$folder"')
        else
          item('disableFolder', Icons.folder_off_outlined,
              'Disable folder "$folder"'),
        if (onRemoveFromPlaylist != null)
          item('remove', Icons.playlist_remove_rounded, 'Remove from playlist'),
        if (onDelete != null)
          item('delete', Icons.delete_outline_rounded, 'Delete file'),
      ],
    );
  }
}

/// Bottom sheet: pick a playlist (or make a new one) for [path].
Future<void> showAddToPlaylistSheet(BuildContext context, String path) async {
  final lists = PlaylistService.instance;
  final messenger = ScaffoldMessenger.of(context);
  final chosen = await showModalBottomSheet<Object>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text('Add to playlist', style: sectionLabel),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded, color: AppColors.accent),
            title: const Text('New playlist'),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final pl in lists.playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(pl.name),
                    subtitle: Text('${pl.paths.length} songs',
                        style: const TextStyle(color: AppColors.muted)),
                    trailing: pl.paths.contains(path)
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.accent)
                        : null,
                    onTap: () => Navigator.pop(ctx, pl),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (chosen == null) return;
  Playlist? target = chosen is Playlist ? chosen : null;
  if (chosen == 'new') {
    if (!context.mounted) return;
    final name = await askPlaylistName(context, title: 'New playlist');
    if (name == null) return;
    target = lists.create(name);
  }
  if (target == null) return;
  final added = lists.addTo(target, path);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(added
          ? 'Added to ${target.name}'
          : 'Already in ${target.name}'),
      duration: const Duration(seconds: 2),
    ));
}

/// Simple name prompt for creating/renaming playlists.
Future<String?> askPlaylistName(BuildContext context,
    {required String title, String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: AppColors.sub)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void showUndoSnack(BuildContext context, String text, VoidCallback undo) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final bar = messenger.showSnackBar(SnackBar(
    content: Text(text),
    duration: const Duration(seconds: 4),
    action: SnackBarAction(
      label: 'Undo',
      textColor: AppColors.accent,
      onPressed: undo,
    ),
  ));
  _autoClose(bar, const Duration(seconds: 4));
}

/// Snackbars with a button stay up until dismissed on newer Flutter
/// versions, so close them ourselves after [after].
void _autoClose(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> bar,
    Duration after) {
  var closed = false;
  bar.closed.then((_) => closed = true);
  Future.delayed(after, () {
    if (!closed) bar.close();
  });
}

/// Tapping a disabled song: explain, and offer to switch it back on.
void showDisabledSnack(BuildContext context, String path) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final bar = messenger.showSnackBar(SnackBar(
    content: const Text('This song is disabled, so it won\'t play.'),
    duration: const Duration(seconds: 4),
    action: SnackBarAction(
      label: 'Enable',
      textColor: AppColors.accent,
      onPressed: () => PlaylistService.instance.setDisabled(path, false),
    ),
  ));
  _autoClose(bar, const Duration(seconds: 4));
}

/// Greys out a disabled song's row.
class DisabledFade extends StatelessWidget {
  const DisabledFade({super.key, required this.disabled, required this.child});
  final bool disabled;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: disabled ? 0.4 : 1, child: child);
}

/// Small "Disabled" tag shown next to a disabled song's details.
class DisabledTag extends StatelessWidget {
  const DisabledTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.muted),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 11, color: AppColors.sub),
            SizedBox(width: 3),
            Text('Disabled',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.sub,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

void showQueuedSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 2),
    ));
}
