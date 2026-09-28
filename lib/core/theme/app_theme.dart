import 'package:flutter/material.dart';

/// Palette taken from the COSBIMP logo: navy, gold and green.
class AppColors {
  static const navy = Color(0xFF12306B);
  static const navyDark = Color(0xFF0B1F47);
  static const gold = Color(0xFFC8912B);
  static const green = Color(0xFF1E6B3C);
  static const background = Color(0xFFF3F5F9);
  static const border = Color(0xFFE1E6EF);
  static const textMuted = Color(0xFF5B667A);
  static const danger = Color(0xFFB3261E);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      secondary: AppColors.gold,
      surface: Colors.white,
    );
    const radius = 12.0;
    OutlineInputBorder inputBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.comfortable,
      dividerColor: AppColors.border,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF1B2437),
        ),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(const Color(0xFFCBD3E1)),
        focusedBorder: inputBorder(AppColors.navy, 1.6),
        disabledBorder: inputBorder(AppColors.border),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: Color(0xFFCBD3E1)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFEDF1F8)),
        headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          fontSize: 13,
        ),
        dataTextStyle: const TextStyle(fontSize: 14, color: Color(0xFF1B2437)),
        dividerThickness: 0.6,
        horizontalMargin: 20,
        columnSpacing: 28,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
