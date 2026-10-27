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

/// Soft glow around the artwork that pulses with the bass.
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

  @override
  Widget build(BuildContext context) {
    final b = bands;
    final bass = b == null || b.isEmpty
        ? 0.0
        : (b.take(5).reduce((a, c) => a + c) / 5).clamp(0.0, 1.0);
    final mid = b == null || b.length < 12
        ? 0.0
        : (b.skip(6).take(6).reduce((a, c) => a + c) / 6).clamp(0.0, 1.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18 + 0.5 * bass),
            blurRadius: 18 + 60 * bass,
            spreadRadius: 2 + 16 * bass,
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.1 + 0.3 * mid),
            blurRadius: 40 + 50 * mid,
            spreadRadius: 6 * mid,
          ),
        ],
      ),
      child: child,
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
