import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Colours taken from a song's cover art, for the Now Playing background.
class ArtColors {
  const ArtColors({required this.glow, required this.top, required this.accent});

  /// Background gradient start (dark, tinted by the cover).
  final Color top;

  /// Visualizer / glow colour.
  final Color glow;

  /// Readable accent for highlights (slider, lyrics line).
  final Color accent;

  static const fallback =
      ArtColors(glow: AppColors.accent, top: Color(0xFF1C2010), accent: AppColors.accent);

  static final _cache = <String, ArtColors>{};

  static Future<ArtColors> forArt(String? artPath) async {
    if (artPath == null || artPath.isEmpty) return fallback;
    final cached = _cache[artPath];
    if (cached != null) return cached;
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(FileImage(File(artPath)), width: 96, height: 96),
        brightness: Brightness.dark,
      );
      final top = Color.lerp(scheme.primaryContainer, AppColors.bg, 0.35)!;
      final c = ArtColors(
        top: top,
        glow: scheme.primary,
        accent: scheme.primary,
      );
      _cache[artPath] = c;
      return c;
    } catch (_) {
      return fallback;
    }
  }
}
