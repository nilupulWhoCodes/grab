import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/player_controller.dart';
import '../services/playlist_service.dart';
import '../theme.dart';
import '../widgets/art_thumb.dart';
import 'playlist_page.dart';

/// Playlists tab inside Music: smart playlists on top, yours below.
class PlaylistsView extends StatelessWidget {
  const PlaylistsView({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await askPlaylistName(context, title: 'New playlist');
    if (name == null || !context.mounted) return;
    final pl = PlaylistService.instance.create(name);
    Navigator.of(context).push(PlaylistPage.route(PlaylistPage.user(pl)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([PlaylistService.instance, LibraryService.instance]),
      builder: (context, _) {
        final lists = PlaylistService.instance;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                for (final (i, s) in [
                  (SmartPlaylist.favourites, Icons.favorite_rounded),
                  (SmartPlaylist.mostPlayed, Icons.trending_up_rounded),
                  (SmartPlaylist.recentlyAdded, Icons.schedule_rounded),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _SmartCard(
                      label: s.$1.label,
                      icon: s.$2,
                      count: lists.smartPaths(s.$1).length,
                      onTap: () => Navigator.of(context).push(
                          PlaylistPage.route(PlaylistPage.smart(s.$1))),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('YOUR PLAYLISTS', style: sectionLabel),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New'),
                ),
              ],
            ),
            if (lists.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.queue_music_rounded,
                        size: 36, color: AppColors.muted),
                    const SizedBox(height: 10),
                    const Text(
                      'No playlists yet.\nCreate one, or use "Add to playlist…" in a song\'s ⋮ menu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _create(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.bg,
                        minimumSize: const Size(180, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New playlist'),
                    ),
                  ],
                ),
              )
            else
              for (final pl in lists.playlists)
                _PlaylistRow(
                  playlist: pl,
                  count: lists.pathsFor(pl).length,
                  art: lists
                      .pathsFor(pl)
                      .map(PlayerController.artOf)
                      .firstWhere((a) => a != null, orElse: () => null),
                ),
          ],
        );
      },
    );
  }
}

class _SmartCard extends StatelessWidget {
  const _SmartCard({
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.selectedFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.accent, size: 22),
              ),
              const SizedBox(height: 12),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('$count songs',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.count,
    required this.art,
  });

  final Playlist playlist;
  final int count;
  final String? art;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context)
          .push(PlaylistPage.route(PlaylistPage.user(playlist))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ArtThumb(artPath: art, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('$count songs',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
