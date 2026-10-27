import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/player_controller.dart';
import '../theme.dart';
import '../widgets/art_thumb.dart';
import '../widgets/mini_player.dart' show formatTime;
import 'queue_page.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  static Route<void> route() => PageRouteBuilder(
        pageBuilder: (_, __, ___) => const NowPlayingPage(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic))
              .animate(anim),
          child: child,
        ),
      );

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: p,
          builder: (context, _) {
            if (p.currentItem == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).maybePop();
              });
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 32),
                      ),
                      const Expanded(
                        child: Text('Now playing',
                            textAlign: TextAlign.center,
                            style: sectionLabel),
                      ),
                      IconButton(
                        tooltip: 'Up next',
                        onPressed: () =>
                            Navigator.of(context).push(QueuePage.route()),
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                    ],
                  ),
                  const Spacer(),
                  LayoutBuilder(
                    builder: (context, c) => p.currentArt == null
                        ? AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Center(
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: AppColors.selectedFill,
                                    borderRadius: BorderRadius.circular(60),
                                  ),
                                  child: const Icon(Icons.music_note_rounded,
                                      size: 56, color: AppColors.accent),
                                ),
                              ),
                            ),
                          )
                        : ArtThumb(
                            artPath: p.currentArt,
                            size: c.maxWidth,
                            radius: 28,
                            iconSize: 56,
                          ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      p.currentTitle ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(24, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      [p.currentArtist, p.currentAlbum]
                          .where((s) => s != null && s.isNotEmpty && s != 'Grab')
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 15, color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 20),
                  StreamBuilder<Duration>(
                    stream: p.player.positionStream,
                    builder: (context, snap) {
                      final dur = p.player.duration ?? Duration.zero;
                      final pos = snap.data ?? Duration.zero;
                      final max = dur.inMilliseconds.toDouble();
                      final value = (_dragValue ??
                              pos.inMilliseconds.toDouble())
                          .clamp(0.0, max <= 0 ? 1.0 : max);
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              activeTrackColor: AppColors.accent,
                              inactiveTrackColor: AppColors.placeholder,
                              thumbColor: AppColors.accent,
                              overlayColor: const Color(0x33D4FF4F),
                            ),
                            child: Slider(
                              min: 0,
                              max: max <= 0 ? 1 : max,
                              value: value,
                              onChanged: max <= 0
                                  ? null
                                  : (v) => setState(() => _dragValue = v),
                              onChangeEnd: (v) {
                                p.player
                                    .seek(Duration(milliseconds: v.round()));
                                setState(() => _dragValue = null);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    formatTime(Duration(
                                        milliseconds: value.round())),
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.muted)),
                                Text(formatTime(dur),
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.muted)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: p.shuffle ? 'Shuffle on' : 'Shuffle off',
                        onPressed: p.toggleShuffle,
                        icon: Icon(Icons.shuffle_rounded,
                            color:
                                p.shuffle ? AppColors.accent : AppColors.muted),
                      ),
                      IconButton(
                        tooltip: 'Previous',
                        iconSize: 36,
                        onPressed: p.previous,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: IconButton.filled(
                          tooltip: p.isPlaying ? 'Pause' : 'Play',
                          iconSize: 40,
                          onPressed: p.toggle,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.bg,
                          ),
                          icon: Icon(p.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        iconSize: 36,
                        onPressed: p.next,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                      IconButton(
                        tooltip: switch (p.loopMode) {
                          LoopMode.off => 'Repeat off',
                          LoopMode.all => 'Repeat all',
                          LoopMode.one => 'Repeat one',
                        },
                        onPressed: p.cycleRepeat,
                        icon: Icon(
                          p.loopMode == LoopMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: p.loopMode == LoopMode.off
                              ? AppColors.muted
                              : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await p.stop();
                            if (context.mounted) Navigator.of(context).maybePop();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('Stop'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).push(QueuePage.route()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.queue_music_rounded),
                          label: const Text('Up next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
