import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF0F1012);
  static const surface = Color(0xFF1A1B1F);
  static const surface2 = Color(0xFF24262B);
  static const card = Color(0xFF1F2125);
  static const placeholder = Color(0xFF2A2C31);
  static const border = Color(0xFF33363C);
  static const line = Color(0xFF26282D);
  static const text = Color(0xFFF2F2F0);
  static const sub = Color(0xFFB5B7BD);
  static const muted = Color(0xFF9A9CA3);
  static const accent = Color(0xFFD4FF4F);
  static const selectedFill = Color(0xFF23261A);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final textTheme = GoogleFonts.interTextTheme(base.textTheme)
      .apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.bg,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    textTheme: textTheme,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.card,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.accent),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionHandleColor: AppColors.accent,
    ),
  );
}

/// Display face used for the app name and big numbers.
TextStyle displayStyle(double size,
        {FontWeight weight = FontWeight.w700, Color color = AppColors.text}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -0.02 * size,
    );

/// Small caps-style section label ("IN PROGRESS", "QUALITY").
const sectionLabel = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppColors.sub,
  letterSpacing: 0.5,
);
