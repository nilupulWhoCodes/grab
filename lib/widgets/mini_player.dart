import 'package:flutter/material.dart';

import '../pages/now_playing_page.dart';
import '../services/player_controller.dart';
import '../theme.dart';
import 'art_thumb.dart';

String formatTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Compact player shown above the bottom bar on every tab.
/// Tap or swipe up to open Now Playing.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _drag = 0;
  bool _opening = false;

  void _open() {
    if (_opening) return;
    _opening = true;
    Navigator.of(context)
        .push(NowPlayingPage.route())
        .whenComplete(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        if (p.currentItem == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: _open,
          onVerticalDragStart: (_) => _drag = 0,
          onVerticalDragUpdate: (d) {
            _drag += d.delta.dy;
            if (_drag < -40) _open();
          },
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -250) _open();
            _drag = 0;
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: StreamBuilder<Duration>(
              stream: p.player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = p.player.duration ?? Duration.zero;
                final frac = dur.inMilliseconds == 0
                    ? 0.0
                    : (pos.inMilliseconds / dur.inMilliseconds)
                        .clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ArtThumb(
                            artPath: p.currentArt,
                            size: 44,
                            radius: 10,
                            iconSize: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.currentTitle ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(p.currentArtist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          tooltip: p.isPlaying ? 'Pause' : 'Play',
                          onPressed: p.toggle,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.bg,
                          ),
                          icon: Icon(p.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                        ),
                        IconButton(
                          tooltip: 'Next',
                          onPressed: p.next,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        IconButton(
                          tooltip: 'Stop',
                          onPressed: p.stop,
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                          backgroundColor: AppColors.placeholder,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
