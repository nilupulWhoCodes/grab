import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/audio_fx.dart';
import '../services/player_controller.dart';
import '../theme.dart';

/// Listens to the native visualizer while it's on screen and hands the
/// latest 24 bands (0..1) to [builder]. Bands are null when unavailable.
class VisualizerFeed extends StatefulWidget {
  const VisualizerFeed({super.key, required this.builder});
  final Widget Function(BuildContext context, List<double>? bands,
      VisualizerAccess access, VoidCallback requestAccess) builder;

  @override
  State<VisualizerFeed> createState() => _VisualizerFeedState();
}

enum VisualizerAccess { unknown, granted, denied, unavailable }

class _VisualizerFeedState extends State<VisualizerFeed> {
  StreamSubscription<int?>? _sessionSub;
  StreamSubscription<List<double>>? _bandsSub;
  List<double>? _bands;
  int? _session;
  VisualizerAccess _access = VisualizerAccess.unknown;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) {
      _access = VisualizerAccess.unavailable;
      return;
    }
    Permission.microphone.status.then((s) {
      if (!mounted) return;
      setState(() => _access =
          s.isGranted ? VisualizerAccess.granted : VisualizerAccess.unknown);
      if (s.isGranted) _listenSession();
    });
  }

  void _listenSession() {
    _sessionSub ??= PlayerController.instance.player.androidAudioSessionIdStream
        .listen((id) {
      if (id == null || id <= 0 || id == _session) return;
      _session = id;
      _bandsSub?.cancel();
      _bandsSub = AudioFx.visualizerBands(id).listen(
        (b) {
          if (mounted) setState(() => _bands = b);
        },
        onError: (_) {
          if (mounted) setState(() => _access = VisualizerAccess.unavailable);
        },
      );
    });
  }

  Future<void> _request() async {
    final s = await Permission.microphone.request();
    if (!mounted) return;
    if (s.isGranted) {
      setState(() => _access = VisualizerAccess.granted);
      _listenSession();
    } else {
      setState(() => _access = VisualizerAccess.denied);
      if (s.isPermanentlyDenied) await openAppSettings();
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _bandsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _bands, _access, _request);
}

/// Mirrored bars that move with the music.
class VisualizerBars extends StatelessWidget {
  const VisualizerBars({
    super.key,
    required this.bands,
    required this.color,
    this.height = 44,
  });

  final List<double>? bands;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarsPainter(bands ?? const [], color)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.bands, this.color);
  final List<double> bands;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    // Low frequencies in the middle, mirrored outwards.
    final ordered = [...bands.reversed, ...bands];
    final n = ordered.length;
    final gap = 3.0;
    final w = (size.width - gap * (n - 1)) / n;
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height),
        Offset.zero,
        [color.withValues(alpha: 0.55), color],
      );
    for (var i = 0; i < n; i++) {
      final h = math.max(3.0, ordered[i] * size.height);
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.bands != bands || old.color != color;
}

/// Colourful glowing ring behind the artwork: it rotates through colours
/// taken from the cover, swells with the music and the cover pulses on the
/// bass.
class VisualizerGlow extends StatelessWidget {
  const VisualizerGlow({
    super.key,
    required this.bands,
    required this.color,
    required this.child,
  });

  final List<double>? bands;
  final Color color;
  final Widget child;

  static double _avg(List<double> b, int from, int to) {
    if (b.length <= from) return 0;
    final part = b.sublist(from, math.min(to, b.length));
    return (part.reduce((a, c) => a + c) / part.length).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final b = bands ?? const <double>[];
    final bass = _avg(b, 0, 5);
    final mid = _avg(b, 6, 14);
    final high = _avg(b, 14, 24);
    // Ease the curve so quiet passages still glow and loud ones really pop.
    final energy = math.pow((bass * 0.6 + mid * 0.3 + high * 0.1), 0.7).toDouble();

    final hsl = HSLColor.fromColor(color);
    Color hue(double shift, double light) => hsl
        .withHue((hsl.hue + shift) % 360)
        .withSaturation(math.max(hsl.saturation, 0.8))
        .withLightness(light)
        .toColor();
    final colors = [
      hue(0, 0.6),
      hue(70, 0.62),
      hue(150, 0.58),
      hue(230, 0.62),
      hue(300, 0.6),
      hue(0, 0.6),
    ];

    final angle =
        (DateTime.now().millisecondsSinceEpoch % 7000) / 7000 * 2 * math.pi;
    final spread = 14 + 46 * energy;
    final blur = 20 + 26 * bass;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Wide, soft colour wash.
        Positioned(
          left: -spread * 1.4,
          right: -spread * 1.4,
          top: -spread * 1.4,
          bottom: -spread * 1.4,
          child: IgnorePointer(
            child: Opacity(
              opacity: (0.25 + 0.55 * energy).clamp(0.0, 1.0),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blur + 18, sigmaY: blur + 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(60),
                    gradient: SweepGradient(
                      colors: colors,
                      transform: GradientRotation(-angle * 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Bright rotating ring hugging the cover.
        Positioned(
          left: -spread * 0.55,
          right: -spread * 0.55,
          top: -spread * 0.55,
          bottom: -spread * 0.55,
          child: IgnorePointer(
            child: Opacity(
              opacity: (0.45 + 0.55 * energy).clamp(0.0, 1.0),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 10 + 10 * bass, sigmaY: 10 + 10 * bass),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    gradient: SweepGradient(
                      colors: colors,
                      transform: GradientRotation(angle),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The cover itself, with a little beat pulse.
        AnimatedScale(
          scale: 1 + 0.04 * bass,
          duration: const Duration(milliseconds: 80),
          child: child,
        ),
      ],
    );
  }
}

/// Shown instead of the visualizer until the user allows it.
class VisualizerPrompt extends StatelessWidget {
  const VisualizerPrompt({super.key, required this.onTap, required this.denied});
  final VoidCallback onTap;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.graphic_eq_rounded, size: 18),
        label: Text(denied
            ? 'Visualizer needs the audio permission'
            : 'Turn on visualizer'),
        style: TextButton.styleFrom(foregroundColor: AppColors.sub),
      ),
    );
  }
}
