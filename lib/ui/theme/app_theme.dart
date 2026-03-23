// lib/ui/theme/app_theme.dart
// Light and dark themes. Dark is the default for workshop use.
// Chart background colour is part of the theme so it responds to theme changes.

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _chartBackgroundDark = Color(0xFF1A1A2E);
  static const Color _chartBackgroundLight = Color(0xFFF5F5F5);

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.tealAccent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D0D1A),
      cardTheme: const CardThemeData(
        color: Color(0xFF1E1E3A),
      ),
      extensions: const [
        AppChartTheme(backgroundColor: _chartBackgroundDark),
      ],
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.light,
      ),
      extensions: const [
        AppChartTheme(backgroundColor: _chartBackgroundLight),
      ],
    );
  }
}

/// ThemeExtension providing chart-specific colours.
class AppChartTheme extends ThemeExtension<AppChartTheme> {
  final Color backgroundColor;

  const AppChartTheme({required this.backgroundColor});

  @override
  AppChartTheme copyWith({Color? backgroundColor}) =>
      AppChartTheme(backgroundColor: backgroundColor ?? this.backgroundColor);

  @override
  AppChartTheme lerp(AppChartTheme? other, double t) {
    if (other == null) return this;
    return AppChartTheme(
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t)!,
    );
  }
}
