import 'dart:async';

import 'package:flutter/material.dart';

import '../services/lyrics_service.dart';
import '../services/player_controller.dart';
import '../theme.dart';

/// Lyrics for the playing song, read from the user's own files.
/// Synced lyrics highlight and follow the current line; tap a line to seek.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.path, required this.accent});
  final String path;
  final Color accent;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<Lyrics?> _future = LyricsService.instance.load(widget.path);
  final _scroll = ScrollController();
  final _keys = <GlobalKey>[];
  int _current = -1;
  StreamSubscription<Duration>? _posSub;
  Lyrics? _lyrics;

  @override
  void initState() {
    super.initState();
    _posSub = PlayerController.instance.player.positionStream.listen(_onPos);
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _future = LyricsService.instance.load(widget.path);
      _lyrics = null;
      _current = -1;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _onPos(Duration pos) {
    final l = _lyrics;
    if (l == null || !l.synced) return;
    final i = l.indexAt(pos + const Duration(milliseconds: 150));
    if (i == _current) return;
    setState(() => _current = i);
    if (i >= 0 && i < _keys.length) {
      final ctx = _keys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.38,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Lyrics?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 2));
        }
        final l = snap.data;
        _lyrics = l;
        if (l == null) return const _NoLyrics();

        final fade = ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent
            ],
            stops: [0, 0.12, 0.85, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: l.synced
              ? _synced(l)
              : SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(l.plain,
                      style: const TextStyle(
                          fontSize: 18, height: 1.6, color: AppColors.text)),
                ),
        );
        return Column(
          children: [
            Expanded(child: fade),
            Text('Lyrics from ${l.source}${l.synced ? '' : ' · not timed'}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        );
      },
    );
  }

  Widget _synced(Lyrics l) {
    while (_keys.length < l.lines.length) {
      _keys.add(GlobalKey());
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 120),
      itemCount: l.lines.length,
      itemBuilder: (context, i) {
        final line = l.lines[i];
        final active = i == _current;
        final past = i < _current;
        return InkWell(
          key: _keys[i],
          borderRadius: BorderRadius.circular(10),
          onTap: () => PlayerController.instance.player.seek(line.time),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                fontSize: active ? 24 : 20,
                height: 1.3,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active
                    ? widget.accent
                    : past
                        ? AppColors.muted.withValues(alpha: 0.6)
                        : AppColors.text.withValues(alpha: 0.75),
              ),
              child: Text(line.text.isEmpty ? '♪' : line.text),
            ),
          ),
        );
      },
    );
  }
}

class _NoLyrics extends StatelessWidget {
  const _NoLyrics();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 40, color: AppColors.muted),
              SizedBox(height: 12),
              Text('No lyrics for this song',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text(
                'Put an .lrc file with the same name next to the MP3 '
                '(e.g. "Song.mp3" + "Song.lrc"), or use an MP3 that has '
                'lyrics saved in its tags.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
            ],
          ),
        ),
      );
}
