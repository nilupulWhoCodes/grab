import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/library_service.dart';
import '../services/player_controller.dart';
import '../services/storage_service.dart';
import '../theme.dart';

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// Part 1: plays the MP3s already on the phone.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    final lib = LibraryService.instance;
    if (lib.state == LibraryState.idle) lib.scan();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _allowAccess() async {
    final storage = StorageService.instance;
    if (await storage.isReadPermissionPermanentlyDenied()) {
      await openAppSettings();
      return;
    }
    await LibraryService.instance.scan();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([LibraryService.instance, PlayerController.instance]),
      builder: (context, _) {
        final lib = LibraryService.instance;
        final player = PlayerController.instance;
        final songs = lib.songs;
        final paths = songs.map((s) => s.path).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Text('Music', style: displayStyle(26)),
                  const SizedBox(width: 10),
                  if (lib.total > 0)
                    Text('${lib.total}',
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.muted)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Rescan storage',
                    onPressed: lib.state == LibraryState.scanning
                        ? null
                        : () => lib.scan(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            if (lib.state == LibraryState.noPermission)
              Expanded(child: _PermissionPrompt(onAllow: _allowAccess))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _search,
                  onChanged: lib.setQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, folders',
                    hintStyle: const TextStyle(color: AppColors.muted),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: AppColors.muted),
                    suffixIcon: lib.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              lib.setQuery('');
                            },
                            icon: const Icon(Icons.close_rounded,
                                color: AppColors.muted),
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: paths.isEmpty
                          ? null
                          : () => player.shuffleAll(paths),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.bg,
                        disabledBackgroundColor: AppColors.surface2,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      label: const Text('Shuffle all'),
                    ),
                    const Spacer(),
                    _SortChip(
                      label: 'Recent',
                      selected: lib.sort == SortMode.recent,
                      onTap: () => lib.setSort(SortMode.recent),
                    ),
                    const SizedBox(width: 6),
                    _SortChip(
                      label: 'A–Z',
                      selected: lib.sort == SortMode.title,
                      onTap: () => lib.setSort(SortMode.title),
                    ),
                  ],
                ),
              ),
              if (lib.state == LibraryState.scanning)
                const LinearProgressIndicator(
                    minHeight: 2, backgroundColor: AppColors.line),
              Expanded(
                child: songs.isEmpty
                    ? _EmptyState(
                        scanning: lib.state == LibraryState.scanning ||
                            lib.state == LibraryState.idle,
                        searching: lib.query.isNotEmpty,
                      )
                    : RefreshIndicator(
                        onRefresh: () => lib.scan(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 16),
                          itemCount: songs.length,
                          itemBuilder: (context, i) {
                            final s = songs[i];
                            final current = player.currentPath == s.path;
                            return _SongRow(
                              song: s,
                              isCurrent: current,
                              isPlaying: current && player.isPlaying,
                              onTap: () => player.play(s.path, paths),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.selectedFill : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.accent : AppColors.sub,
              )),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCurrent
                    ? (isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded)
                    : Icons.music_note_rounded,
                color: isCurrent ? AppColors.bg : AppColors.muted,
                semanticLabel: isPlaying ? 'Pause' : 'Play',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppColors.accent : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [song.artist, _mb(song.size)]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (isCurrent && isPlaying)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.graphic_eq_rounded,
                    color: AppColors.accent, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, required this.searching});

  final bool scanning;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final text = scanning
        ? 'Looking for MP3s on your phone…'
        : searching
            ? 'No songs match your search.'
            : 'No MP3s found on this phone yet.\nDownload some in the MP3 tab.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined,
                size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded,
                size: 44, color: AppColors.muted),
            const SizedBox(height: 14),
            Text('Allow access to your music',
                textAlign: TextAlign.center,
                style: displayStyle(20, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Grab needs permission to find the MP3 files on your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAllow,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.bg,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: const Text('Allow access'),
            ),
          ],
        ),
      ),
    );
  }
}
