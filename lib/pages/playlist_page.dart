import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/player_controller.dart';
import '../services/playlist_service.dart';
import '../theme.dart';
import '../widgets/art_thumb.dart';

/// One playlist: a smart one (Favourites, Most played, Recently added) or
/// one of yours (rename, delete, reorder, remove songs).
class PlaylistPage extends StatelessWidget {
  const PlaylistPage.smart(this.smart, {super.key}) : playlist = null;
  const PlaylistPage.user(this.playlist, {super.key}) : smart = null;

  final SmartPlaylist? smart;
  final Playlist? playlist;

  static Route<void> route(PlaylistPage page) =>
      MaterialPageRoute(builder: (_) => page);

  String get _name => playlist?.name ?? smart!.label;

  List<String> get _paths => playlist != null
      ? PlaylistService.instance.pathsFor(playlist!)
      : PlaylistService.instance.smartPaths(smart!);

  Future<void> _menu(BuildContext context, String action) async {
    final lists = PlaylistService.instance;
    final pl = playlist!;
    if (action == 'rename') {
      final name = await askPlaylistName(context,
          title: 'Rename playlist', initial: pl.name);
      if (name != null) lists.rename(pl, name);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this playlist?'),
          content: Text('"${pl.name}" will be removed. The songs stay on your phone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: AppColors.sub)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) {
        lists.delete(pl);
        if (context.mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(
              [PlaylistService.instance, LibraryService.instance, p]),
          builder: (context, _) {
            final paths = _paths;
            final firstArt =
                paths.map(PlayerController.artOf).firstWhere((a) => a != null,
                    orElse: () => null);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      if (playlist != null)
                        PopupMenuButton<String>(
                          tooltip: 'Playlist options',
                          color: AppColors.surface2,
                          onSelected: (v) => _menu(context, v),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'rename', child: Text('Rename')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete playlist')),
                          ],
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(
                    children: [
                      smart == SmartPlaylist.favourites
                          ? const _BigIcon(Icons.favorite_rounded)
                          : smart == SmartPlaylist.mostPlayed
                              ? const _BigIcon(Icons.trending_up_rounded)
                              : smart == SmartPlaylist.recentlyAdded
                                  ? const _BigIcon(Icons.schedule_rounded)
                                  : ArtThumb(
                                      artPath: firstArt,
                                      size: 88,
                                      radius: 18,
                                      iconSize: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: displayStyle(26)),
                            const SizedBox(height: 4),
                            Text('${paths.length} songs',
                                style:
                                    const TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: paths.isEmpty
                              ? null
                              : () => p.play(paths.first, paths),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.bg,
                            disabledBackgroundColor: AppColors.surface2,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              paths.isEmpty ? null : () => p.shuffleAll(paths),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Shuffle'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: paths.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              switch (smart) {
                                SmartPlaylist.favourites =>
                                  'No favourites yet.\nTap the heart on Now Playing, or use a song\'s ⋮ menu.',
                                SmartPlaylist.mostPlayed =>
                                  'Play some music and your most played songs show up here.',
                                SmartPlaylist.recentlyAdded =>
                                  'No songs found yet.',
                                null =>
                                  'This playlist is empty.\nUse "Add to playlist…" in any song\'s ⋮ menu.',
                              },
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.muted, height: 1.5),
                            ),
                          ),
                        )
                      : playlist != null
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 0, 24),
                              itemCount: paths.length,
                              onReorder: (from, to) {
                                // Map visible indices back to stored ones.
                                final stored = playlist!.paths;
                                final a = stored.indexOf(paths[from]);
                                final b = to >= paths.length
                                    ? stored.length
                                    : stored.indexOf(paths[to]);
                                PlaylistService.instance
                                    .reorder(playlist!, a, b);
                              },
                              itemBuilder: (context, i) => _PlaylistSongRow(
                                key: ValueKey('pl${paths[i]}'),
                                path: paths[i],
                                queue: paths,
                                onRemove: () => PlaylistService.instance
                                    .removeFrom(playlist!, paths[i]),
                                dragIndex: i,
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 0, 24),
                              itemCount: paths.length,
                              itemBuilder: (context, i) => _PlaylistSongRow(
                                path: paths[i],
                                queue: paths,
                                plays: smart == SmartPlaylist.mostPlayed
                                    ? PlaylistService.instance
                                        .playsOf(paths[i])
                                    : null,
                                onRemove: smart == SmartPlaylist.favourites
                                    ? () => PlaylistService.instance
                                        .toggleFavourite(paths[i])
                                    : null,
                              ),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BigIcon extends StatelessWidget {
  const _BigIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.selectedFill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 40, color: AppColors.accent),
      );
}

class _PlaylistSongRow extends StatelessWidget {
  const _PlaylistSongRow({
    super.key,
    required this.path,
    required this.queue,
    this.onRemove,
    this.plays,
    this.dragIndex,
  });

  final String path;
  final List<String> queue;
  final VoidCallback? onRemove;
  final int? plays;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    final current = p.currentPath == path;
    final song = LibraryService.instance.songFor(path);
    final subtitle = [
      PlayerController.artistOf(path),
      if (song?.album != null) song!.album!,
      if (plays != null) '$plays plays',
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => p.play(path, queue),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ArtThumb(artPath: PlayerController.artOf(path), size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(PlayerController.titleOf(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: current ? AppColors.accent : AppColors.text,
                      )),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ),
            SongMenu(path: path, onRemoveFromPlaylist: onRemove),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(0, 10, 12, 10),
                  child: Icon(Icons.drag_handle_rounded,
                      color: AppColors.muted, semanticLabel: 'Reorder'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
