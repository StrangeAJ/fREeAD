import 'package:flutter/material.dart';

import '../models/app_settings.dart';

/// Typography for the design system.
///
/// Three bundled families (registered in `pubspec.yaml`):
/// * [display] `SpaceGrotesk` - display + headlines, tight tracking.
/// * [ui] `Inter` - titles, body, labels, everything chrome.
/// * [reading] `Literata` - the reading body when the user picks Serif.
abstract final class AppTypography {
  /// Display / headline family.
  static const String display = 'SpaceGrotesk';

  /// UI family (titles, body, labels).
  static const String ui = 'Inter';

  /// Serif reading family.
  static const String reading = 'Literata';

  /// Monospace used for `<pre>`/`<code>` in the reader.
  static const String mono = 'monospace';

  /// The app [TextTheme]. Colours are applied by `AppTheme` afterwards.
  static TextTheme textTheme() {
    return const TextTheme(
      // Display - SpaceGrotesk, very tight.
      displayLarge: TextStyle(
        fontFamily: display,
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.1,
      ),
      displayMedium: TextStyle(
        fontFamily: display,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        height: 1.1,
      ),
      displaySmall: TextStyle(
        fontFamily: display,
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        height: 1.15,
      ),

      // Headline - SpaceGrotesk.
      headlineLarge: TextStyle(
        fontFamily: display,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        height: 1.15,
      ),
      headlineMedium: TextStyle(
        fontFamily: display,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        height: 1.18,
      ),
      headlineSmall: TextStyle(
        fontFamily: display,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.2,
      ),

      // Title - Inter.
      titleLarge: TextStyle(
        fontFamily: ui,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        fontFamily: ui,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        height: 1.3,
      ),
      titleSmall: TextStyle(
        fontFamily: ui,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),

      // Body - Inter.
      bodyLarge: TextStyle(
        fontFamily: ui,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: ui,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontFamily: ui,
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.4,
      ),

      // Label - Inter. `labelSmall` is the section-header style.
      labelLarge: TextStyle(
        fontFamily: ui,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.2,
      ),
      labelMedium: TextStyle(
        fontFamily: ui,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        height: 1.2,
      ),
      labelSmall: TextStyle(
        fontFamily: ui,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        height: 1.2,
      ),
    );
  }

  /// The reading body style for the reader screen.
  ///
  /// ```dart
  /// AppTypography.readingBody(settings.readingFont, settings.fontSize, settings.lineHeight)
  /// ```
  static TextStyle readingBody(
    ReadingFont font,
    double size,
    double lineHeight, {
    Color? color,
  }) {
    return TextStyle(
      fontFamily: font == ReadingFont.serif ? reading : ui,
      fontSize: size,
      height: lineHeight,
      fontWeight: FontWeight.w400,
      letterSpacing: font == ReadingFont.serif ? 0 : -0.1,
      color: color,
    );
  }

  /// Heading style inside the reader for `h1`..`h6` ([level] 1-6).
  static TextStyle readingHeading(int level, {Color? color, double scale = 1}) {
    final int l = level.clamp(1, 6);
    final double size = switch (l) {
      1 => 28.0,
      2 => 24.0,
      3 => 20.0,
      4 => 18.0,
      5 => 16.0,
      _ => 15.0,
    };
    return TextStyle(
      fontFamily: display,
      fontSize: size * scale,
      fontWeight: l <= 2 ? FontWeight.w700 : FontWeight.w600,
      letterSpacing: l <= 2 ? -0.6 : -0.3,
      height: 1.22,
      color: color,
    );
  }
}
