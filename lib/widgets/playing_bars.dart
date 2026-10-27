import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated equalizer bars for the song that's playing. When [playing] is
/// false the bars settle into a still, low pattern.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.playing,
    this.size = 22,
    this.color = AppColors.accent,
    this.bars = 4,
  });

  final bool playing;
  final double size;
  final Color color;
  final int bars;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.playing ? 'Playing' : 'Paused',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _BarsPainter(
              t: _c.value,
              playing: widget.playing,
              color: widget.color,
              bars: widget.bars,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.t,
    required this.playing,
    required this.color,
    required this.bars,
  });

  final double t;
  final bool playing;
  final Color color;
  final int bars;

  // Each bar mixes two sine waves at its own speed/phase, so the motion
  // looks lively rather than mechanical.
  static const _speed = [1.0, 1.6, 1.25, 1.9, 1.4];
  static const _phase = [0.0, 1.7, 3.1, 0.9, 2.4];
  static const _rest = [0.45, 0.8, 0.6, 0.35, 0.7];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final gap = size.width * 0.12;
    final w = (size.width - gap * (bars - 1)) / bars;
    for (var i = 0; i < bars; i++) {
      double h;
      if (playing) {
        final a = 2 * math.pi * t * _speed[i % 5] + _phase[i % 5];
        final v = 0.5 + 0.32 * math.sin(a) + 0.18 * math.sin(a * 2.3 + i);
        h = v.clamp(0.15, 1.0);
      } else {
        h = _rest[i % 5] * 0.6;
      }
      final barH = size.height * h;
      final x = i * (w + gap);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - barH, w, barH),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.t != t || old.playing != playing || old.color != color;
}
