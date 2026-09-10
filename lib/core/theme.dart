import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B0F1A);
  static const surface = Color(0xFF131A2B);
  static const surfaceLight = Color(0xFF1B2439);
  static const border = Color(0xFF27324D);
  static const primary = Color(0xFF6C5CE7);
  static const primaryLight = Color(0xFF8E7CFF);
  static const accent = Color(0xFF00CEC9);
  static const good = Color(0xFF00B894);
  static const warn = Color(0xFFFDCB6E);
  static const bad = Color(0xFFE17055);
  static const textHigh = Color(0xFFEAF0FF);
  static const textMid = Color(0xFF9AA7C7);
  static const textLow = Color(0xFF5C6885);
}

ThemeData buildPixelTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.bad,
    ).copyWith(
      surface: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textHigh,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      hintStyle: const TextStyle(color: AppColors.textLow),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primaryLight,
      selectionColor: Color(0x448E7CFF),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      contentTextStyle: TextStyle(color: AppColors.textHigh),
      behavior: SnackBarBehavior.floating,
    ),
  );
}