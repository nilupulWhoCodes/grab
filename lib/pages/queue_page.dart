import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../services/player_controller.dart';
import '../theme.dart';
import '../widgets/art_thumb.dart';
import '../widgets/playing_bars.dart';

/// "Up next": the play queue. Drag to reorder, swipe to remove, tap to jump.
class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const QueuePage());

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: p,
          builder: (context, _) {
            final queue = p.queue;
            final current = p.currentIndex;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      Text('Up next', style: displayStyle(24)),
                      const Spacer(),
                      Text('${queue.length} songs',
                          style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                if (p.shuffle)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shuffle_rounded,
                            size: 18, color: AppColors.accent),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Shuffle is on. Turn it off to reorder.',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.sub)),
                        ),
                        TextButton(
                          onPressed: p.toggleShuffle,
                          child: const Text('Turn off'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: queue.isEmpty
                      ? const Center(
                          child: Text('Nothing in the queue.',
                              style: TextStyle(color: AppColors.muted)),
                        )
                      : p.shuffle
                          ? _ShuffledList(queue: queue, current: current)
                          : ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                              itemCount: queue.length,
                              onReorder: (from, to) {
                                if (to > from) to -= 1;
                                if (from != to) p.move(from, to);
                              },
                              itemBuilder: (context, i) => _QueueRow(
                                key: ValueKey('q$i-${queue[i].id}'),
                                item: queue[i],
                                index: i,
                                isCurrent: i == current,
                                draggable: true,
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

class _ShuffledList extends StatelessWidget {
  const _ShuffledList({required this.queue, required this.current});

  final List<MediaItem> queue;
  final int? current;

  @override
  Widget build(BuildContext context) {
    final order = PlayerController.instance.player.effectiveIndices
        .where((i) => i < queue.length)
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      itemCount: order.length,
      itemBuilder: (context, k) {
        final i = order[k];
        return _QueueRow(
          key: ValueKey('s$i-${queue[i].id}'),
          item: queue[i],
          index: i,
          isCurrent: i == current,
          draggable: false,
        );
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.draggable,
  });

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    final row = Material(
      color: isCurrent ? AppColors.selectedFill : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => p.jumpTo(index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              Stack(
                children: [
                  ArtThumb(
                      artPath: item.artUri?.toFilePath(), size: 44, radius: 10),
                  if (isCurrent)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: PlayingBars(playing: p.isPlaying, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isCurrent ? AppColors.accent : AppColors.text,
                        )),
                    const SizedBox(height: 2),
                    Text(isCurrent ? 'Now playing' : (item.artist ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from queue',
                onPressed: () => p.removeAt(index),
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: AppColors.muted, size: 22),
              ),
              if (draggable)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Icon(Icons.drag_handle_rounded,
                        color: AppColors.muted, semanticLabel: 'Reorder'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Dismissible(
        key: ValueKey('d$index-${item.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.delete_outline_rounded, color: AppColors.sub),
        ),
        onDismissed: (_) => p.removeAt(index),
        child: row,
      ),
    );
  }
}
