/// Design tokens.
///
/// There is no Material or Cupertino here (ADR-0003), so colour and type come
/// from one InheritedWidget rather than from a ThemeData. Dark-first: this is
/// read across a room and often left on a screen for hours.
library;

import 'package:flutter/widgets.dart';

class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.accent,
    required this.error,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color accent;
  final Color error;
  final Color divider;

  static const dark = AppColors(
    background: Color(0xFF0E0E11),
    surface: Color(0xFF17171C),
    surfaceRaised: Color(0xFF222229),
    textPrimary: Color(0xFFF4F4F6),
    textSecondary: Color(0xFF9A9AA6),
    textDisabled: Color(0xFF4C4C57),
    accent: Color(0xFF6FD3A8),
    error: Color(0xFFE2725B),
    divider: Color(0xFF2A2A33),
  );
}

class AppTypography {
  const AppTypography({
    required this.display,
    required this.title,
    required this.body,
    required this.caption,
  });

  final TextStyle display;
  final TextStyle title;
  final TextStyle body;
  final TextStyle caption;

  /// No font is bundled yet — this uses the platform's own UI font via the
  /// fallback stack. Bundling one is a pubspec change plus a .ttf and does not
  /// affect anything else here.
  static const _fallbacks = <String>[
    'SF Pro Display',
    'Roboto',
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
  ];

  static const dark = AppTypography(
    display: TextStyle(
      fontSize: 34,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      color: Color(0xFFF4F4F6),
      fontFamilyFallback: _fallbacks,
      decoration: TextDecoration.none,
    ),
    title: TextStyle(
      fontSize: 21,
      height: 1.25,
      fontWeight: FontWeight.w500,
      color: Color(0xFFF4F4F6),
      fontFamilyFallback: _fallbacks,
      decoration: TextDecoration.none,
    ),
    body: TextStyle(
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w400,
      color: Color(0xFF9A9AA6),
      fontFamilyFallback: _fallbacks,
      decoration: TextDecoration.none,
    ),
    caption: TextStyle(
      fontSize: 13,
      height: 1.3,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.6,
      color: Color(0xFF9A9AA6),
      fontFamilyFallback: _fallbacks,
      decoration: TextDecoration.none,
    ),
  );
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
}

class AppTheme extends InheritedWidget {
  const AppTheme({
    super.key,
    this.colors = AppColors.dark,
    this.typography = AppTypography.dark,
    required super.child,
  });

  final AppColors colors;
  final AppTypography typography;

  static AppTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(theme != null, 'No AppTheme found. Wrap the app in an AppTheme.');
    return theme!;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) =>
      oldWidget.colors != colors || oldWidget.typography != typography;
}
