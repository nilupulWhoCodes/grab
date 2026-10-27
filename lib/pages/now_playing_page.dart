import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/player_controller.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/art_backdrop.dart';
import '../widgets/art_thumb.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/sound_sheet.dart';
import '../widgets/visualizer.dart';
import '../widgets/mini_player.dart' show formatTime;
import 'queue_page.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  static Route<void> route() => PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
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

class _NowPlayingPageState extends State<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  double? _dragValue;
  bool _showLyrics = false;

  // Drag down to collapse.
  double _dragY = 0;
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _dragY = _snapFrom * (1 - _snap.value)));
  double _snapFrom = 0;
  bool _closing = false;

  // Swipe the artwork left/right to change song.
  // keepPage: false so a rebuilt pager never restores an old page.
  final PageController _pager =
      PageController(viewportFraction: 1, keepPage: false);
  bool _syncing = false;
  int? _shownIndex;

  /// Song the user swiped to, until the player confirms it's playing.
  int? _pendingIndex;
  DateTime _pendingSince = DateTime.fromMillisecondsSinceEpoch(0);

  void _swipedTo(int index) {
    _pendingIndex = index;
    _pendingSince = DateTime.now();
    _shownIndex = index;
    PlayerController.instance.jumpTo(index);
  }

  @override
  void dispose() {
    _snap.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_closing) return;
    setState(() => _dragY = (_dragY + d.delta.dy).clamp(0.0, double.infinity));
  }

  void _onDragEnd(DragEndDetails d) {
    if (_closing) return;
    final height = MediaQuery.sizeOf(context).height;
    final fast = (d.primaryVelocity ?? 0) > 700;
    if (fast || _dragY > height * 0.22) {
      _closing = true;
      Navigator.of(context).maybePop();
    } else {
      _snapFrom = _dragY;
      _snap.forward(from: 0);
    }
  }

  /// Keeps the artwork pager on the song that's actually playing.
  void _syncPager(List<int> order, int? current) {
    if (current == null) return;
    // After a swipe, ignore the old song until the player has switched
    // (or give up after 2 s if it never does).
    if (_pendingIndex != null) {
      final waited = DateTime.now().difference(_pendingSince);
      if (current != _pendingIndex && waited < const Duration(seconds: 2)) {
        return;
      }
      _pendingIndex = null;
    }
    if (current == _shownIndex) return;
    _shownIndex = current;
    final page = order.indexOf(current);
    if (page < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_pager.hasClients) return;
      // Never move the card while a finger is on it.
      if (_pager.position.isScrollingNotifier.value) {
        _shownIndex = null; // try again on the next update
        return;
      }
      final now = _pager.page?.round();
      if (now == page) return;
      _syncing = true;
      if (now == null || (now - page).abs() > 1) {
        _pager.jumpToPage(page);
      } else {
        await _pager.animateToPage(page,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic);
      }
      _syncing = false;
    });
  }

  /// Artwork (or lyrics) plus the visualizer.
  Widget _artArea(
      BuildContext context, PlayerController p, double side, Widget pager) {
    final colors = ArtBackdrop.colorsOf(context);
    final style = SettingsService.instance.visualizer;
    final path = p.currentPath;
    if (_showLyrics && path != null) {
      return SizedBox(
        width: side,
        height: side + 44,
        child: LyricsView(path: path, accent: colors.accent),
      );
    }
    if (style == VisualizerStyle.off) return pager;
    return VisualizerFeed(
      builder: (context, bands, access, request) {
        final needsAccess = access != VisualizerAccess.granted &&
            access != VisualizerAccess.unavailable;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            style == VisualizerStyle.glow || style == VisualizerStyle.both
                ? VisualizerGlow(
                    bands: bands, color: colors.glow, child: pager)
                : pager,
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: needsAccess
                  ? VisualizerPrompt(
                      onTap: request,
                      denied: access == VisualizerAccess.denied)
                  : style == VisualizerStyle.bars ||
                          style == VisualizerStyle.both
                      ? VisualizerBars(bands: bands, color: colors.glow)
                      : null,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = PlayerController.instance;
    final height = MediaQuery.sizeOf(context).height;
    final progress = (_dragY / (height * 0.6)).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragY),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(_dragY > 0 ? 28 : 0)),
          child: Opacity(
            opacity: 1 - progress * 0.35,
            child: Scaffold(
      backgroundColor: AppColors.bg,
      body: ArtBackdrop(
      child: SafeArea(
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
                      ListenableBuilder(
                        listenable: SettingsService.instance,
                        builder: (context, _) {
                          final on = SettingsService.instance.fxMode !=
                              FxMode.normal;
                          return IconButton(
                            tooltip: 'Speed, pitch & reverb',
                            onPressed: () => showSoundSheet(context),
                            icon: Icon(Icons.speed_rounded,
                                color: on
                                    ? ArtBackdrop.colorsOf(context).accent
                                    : null),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: _showLyrics ? 'Show artwork' : 'Lyrics',
                        onPressed: () =>
                            setState(() => _showLyrics = !_showLyrics),
                        icon: Icon(
                          _showLyrics
                              ? Icons.album_rounded
                              : Icons.lyrics_outlined,
                          color: _showLyrics
                              ? ArtBackdrop.colorsOf(context).accent
                              : null,
                        ),
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
                  LayoutBuilder(builder: (context, c) {
                    final queue = p.queue;
                    final order = p.player.effectiveIndices
                        .where((i) => i < queue.length)
                        .toList();
                    _syncPager(order, p.currentIndex);
                    final side = c.maxWidth;
                    final pager = SizedBox(
                      width: side,
                      height: side,
                      // Change song only once the swipe has settled on a new
                      // card, never mid-drag (dragging back cancels it).
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: (_) {
                          final page = _pager.page?.round();
                          if (!_syncing &&
                              page != null &&
                              page >= 0 &&
                              page < order.length &&
                              order[page] != p.currentIndex) {
                            _swipedTo(order[page]);
                          }
                          return false;
                        },
                        child: PageView.builder(
                          controller: _pager,
                          physics: const _ArtSwipePhysics(),
                          itemCount: order.length,
                          itemBuilder: (context, k) {
                            final item = queue[order[k]];
                            final art = item.artUri?.toFilePath();
                            return AnimatedBuilder(
                              animation: _pager,
                              builder: (context, child) {
                                // Cards shrink a little as they slide away.
                                final page = _pager.hasClients &&
                                        _pager.position.haveDimensions
                                    ? (_pager.page ?? k.toDouble())
                                    : k.toDouble();
                                final t = (1 - (page - k).abs()).clamp(0.0, 1.0);
                                return Transform.scale(
                                  scale: 0.9 + 0.1 * t,
                                  child: Opacity(
                                      opacity: 0.5 + 0.5 * t, child: child),
                                );
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: art == null
                                    ? _NoArtCard(
                                        title: item.title,
                                        artist: item.artist ?? '')
                                    : ArtCover(
                                        artPath: art,
                                        size: side - 8,
                                        radius: 28,
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                    return _artArea(context, p, side, pager);
                  }),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                      begin: const Offset(0, 0.25),
                                      end: Offset.zero)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: [...previous, if (current != null) current],
                          ),
                          child: Text(
                            p.currentTitle ?? '',
                            key: ValueKey(p.currentPath),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: displayStyle(24, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      ListenableBuilder(
                        listenable: PlaylistService.instance,
                        builder: (context, _) {
                          final path = p.currentPath;
                          final fav = path != null &&
                              PlaylistService.instance.isFavourite(path);
                          return IconButton(
                            tooltip: fav
                                ? 'Remove from Favourites'
                                : 'Add to Favourites',
                            onPressed: path == null
                                ? null
                                : () => PlaylistService.instance
                                    .toggleFavourite(path),
                            icon: Icon(
                              fav
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: fav ? AppColors.accent : AppColors.muted,
                              size: 28,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Add to playlist',
                        onPressed: p.currentPath == null
                            ? null
                            : () =>
                                showAddToPlaylistSheet(context, p.currentPath!),
                        icon: const Icon(Icons.playlist_add_rounded,
                            color: AppColors.muted, size: 28),
                      ),
                    ],
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
                              activeTrackColor: ArtBackdrop.colorsOf(context).accent,
                              inactiveTrackColor: AppColors.placeholder,
                              thumbColor: ArtBackdrop.colorsOf(context).accent,
                              overlayColor: ArtBackdrop.colorsOf(context)
                                  .accent
                                  .withValues(alpha: 0.2),
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
      ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Swipes need a real drag or flick (a nudge snaps back).
class _ArtSwipePhysics extends PageScrollPhysics {
  const _ArtSwipePhysics({super.parent});

  @override
  _ArtSwipePhysics applyTo(ScrollPhysics? ancestor) =>
      _ArtSwipePhysics(parent: buildParent(ancestor));

  @override
  double get minFlingVelocity => 600;

  @override
  double get minFlingDistance => 40;
}

/// Card for songs without cover art: shows the title so swiping is visible.
class _NoArtCard extends StatelessWidget {
  const _NoArtCard({required this.title, required this.artist});
  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final colors = ArtBackdrop.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface2, AppColors.surface],
        ),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.selectedFill,
              borderRadius: BorderRadius.circular(48),
            ),
            child: Icon(Icons.music_note_rounded, size: 48, color: colors.accent),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: displayStyle(22, weight: FontWeight.w600)),
          if (artist.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          ],
        ],
      ),
    );
  }
}
