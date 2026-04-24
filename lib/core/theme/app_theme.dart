import 'package:flutter/material.dart';

class AppTheme {
  static const _primary = Color(0xFF00113A);
  static const _secondary = Color(0xFF2552CA);
  static const _surface = Color(0xFFF0F2F8);
  static const _error = Color(0xFFD32F2F);
  static const _onSurface = Color(0xFF1A1C2E);
  static const _onSurfaceVariant = Color(0xFF6B7280);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: _primary,
      secondary: _secondary,
      surface: _surface,
      error: _error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: _onSurface,
      onSurfaceVariant: _onSurfaceVariant,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFE8EAF2),
      surfaceContainer: Color(0xFFDDE0EC),
      surfaceContainerHigh: Color(0xFFD2D5E5),
      surfaceContainerHighest: Color(0xFFC7CADB),
      outline: Color(0xFF9EA3B8),
      outlineVariant: Color(0xFFCDD0E0),
      errorContainer: Color(0xFFFFDAD6),
    ),
    scaffoldBackgroundColor: _surface,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: _surface,
      foregroundColor: _primary,
      elevation: 0,
      centerTitle: true,
    ),
  );

  // Convenience color getters for use outside BuildContext
  static const primary = _primary;
  static const secondary = _secondary;
  static const surface = _surface;
  static const error = _error;
  static const onSurface = _onSurface;
  static const onSurfaceVariant = _onSurfaceVariant;
  static const surfaceContainerLowest = Colors.white;
  static const surfaceContainerLow = Color(0xFFE8EAF2);
  static const surfaceContainer = Color(0xFFDDE0EC);
  static const surfaceContainerHigh = Color(0xFFD2D5E5);
  static const mint = Color(0xFFC9ECE6);
}
