import 'package:flutter/material.dart';

class AppTheme {
  // Board colors - muted parchment/tactical table feel
  static const Color boardBackground = Color(0xFFC9B38E); // Matte beige/light walnut
  static const Color gridLine = Color(0xFF8B7355); // Micro grid - darker for visibility
  static const Color gridLineAccent = Color(0xFF9A8567); // Major grid lines (every 6th)
  static const Color gridLineBoundary = Color(0xFF7A5E3C); // Board edge/frame

  // Stone colors
  static const Color blackStone = Color(0xFF1A1A1A);
  static const Color whiteStone = Color(0xFFF5F5F5);
  static const Color blackStoneBorder = Color(0xFF000000);
  static const Color whiteStoneBorder = Color(0xFFCCCCCC);

  // UI colors
  static const Color primaryColor = Color(0xFF2D2D2D);
  static const Color accentColor = Color(0xFF4A90A4);
  static const Color backgroundColor = Color(0xFFF5F5F0);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Last move highlight
  static const Color lastMoveHighlight = Color(0xFFE53935);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: primaryColor,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: primaryColor,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: primaryColor,
        ),
      ),
    );
  }
}
