import 'dart:ui';

/// Raw palette for the "quiet instrument" design language.
///
/// Nothing outside `lib/theme/` should read these directly - consume
/// [AppTokens] (`context.tokens`) or the [ColorScheme] instead.
abstract final class AppColors {
  // --- Dark (default) ------------------------------------------------------
  static const Color darkBg = Color(0xFF0B0C0E);
  static const Color darkSurface1 = Color(0xFF121317);
  static const Color darkSurface2 = Color(0xFF191B20);
  static const Color darkSurface3 = Color(0xFF22252B);

  static const Color darkTextPrimary = Color(0xFFECEDEF);
  static const Color darkTextSecondary = Color(0xFFA0A4AD);
  static const Color darkTextTertiary = Color(0xFF6B7079);

  /// Hairline separators. Shadows are never used - only these.
  static const double darkHairlineAlpha = 0.08;
  static const double darkHairlineStrongAlpha = 0.14;

  // --- Dark, pure black (AMOLED) ------------------------------------------
  static const Color blackBg = Color(0xFF000000);
  static const Color blackSurface1 = Color(0xFF0A0A0A);
  static const Color blackSurface2 = Color(0xFF111111);
  static const Color blackSurface3 = Color(0xFF181818);

  // --- Light ---------------------------------------------------------------
  static const Color lightBg = Color(0xFFF6F7F9);
  static const Color lightSurface1 = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFF0F2F5);
  static const Color lightSurface3 = Color(0xFFE6E9EE);

  static const Color lightTextPrimary = Color(0xFF15171A);
  static const Color lightTextSecondary = Color(0xFF5B6068);
  static const Color lightTextTertiary = Color(0xFF8A8F98);

  static const double lightHairlineAlpha = 0.07;
  static const double lightHairlineStrongAlpha = 0.12;

  // --- Semantic ------------------------------------------------------------
  static const Color successDark = Color(0xFF34D399);
  static const Color successLight = Color(0xFF059669);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color warningLight = Color(0xFFB45309);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color dangerLight = Color(0xFFDC2626);

  /// Neutral used when a category has no colour of its own.
  static const Color neutral = Color(0xFF94A3B8);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
}
