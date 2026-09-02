import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Design tokens for the "quiet instrument" language.
///
/// Every colour, radius and spacing value used by `lib/widgets/ui/**` and by
/// the screens comes from here (or from `Theme.of(context).colorScheme` /
/// `textTheme`). Nothing hardcodes a hex value outside `lib/theme/`.
///
/// Read them with the [BuildContext] extension:
///
/// ```dart
/// final t = context.tokens;
/// Container(color: t.surface2, padding: EdgeInsets.all(t.spaceL));
/// ```
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.hairline,
    required this.hairlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentGlow,
    required this.success,
    required this.warning,
    required this.danger,
  });

  /// Which mode these tokens were built for.
  final Brightness brightness;

  /// Page background - the lowest layer.
  final Color bg;

  /// Cards, app bars, sheets.
  final Color surface1;

  /// Inputs, chips, nested surfaces.
  final Color surface2;

  /// Snackbars, pressed states, the highest layer.
  final Color surface3;

  /// 1px separators. Borders replace shadows everywhere.
  final Color hairline;

  /// Slightly stronger separator, for focused/selected outlines.
  final Color hairlineStrong;

  /// Primary body text.
  final Color textPrimary;

  /// Meta text, subtitles.
  final Color textSecondary;

  /// Timestamps, captions, disabled text.
  final Color textTertiary;

  /// The single accent colour.
  final Color accent;

  /// Readable foreground on top of [accent].
  final Color onAccent;

  /// [accent] at 16% - chip/indicator fills.
  final Color accentSoft;

  /// [accent] at 35% - the soft glow under the primary action.
  final Color accentGlow;

  final Color success;
  final Color warning;
  final Color danger;

  // --- Shape ---------------------------------------------------------------

  /// Chips, buttons, inputs.
  static const double kRadiusS = 12;

  /// Cards, tiles.
  static const double kRadiusM = 20;

  /// Sheets, dialogs.
  static const double kRadiusL = 28;

  double get radiusS => kRadiusS;
  double get radiusM => kRadiusM;
  double get radiusL => kRadiusL;

  BorderRadius get borderRadiusS => BorderRadius.circular(kRadiusS);
  BorderRadius get borderRadiusM => BorderRadius.circular(kRadiusM);
  BorderRadius get borderRadiusL => BorderRadius.circular(kRadiusL);

  // --- Spacing scale: 4 / 8 / 12 / 16 / 20 / 24 / 32 -----------------------

  static const double kSpaceXs = 4;
  static const double kSpaceS = 8;
  static const double kSpaceM = 12;
  static const double kSpaceL = 16;
  static const double kSpaceXl = 20;
  static const double kSpace2xl = 24;
  static const double kSpace3xl = 32;

  double get spaceXs => kSpaceXs;
  double get spaceS => kSpaceS;
  double get spaceM => kSpaceM;
  double get spaceL => kSpaceL;
  double get spaceXl => kSpaceXl;
  double get spaceXL => kSpaceXl; // Alias for capitalization consistency
  double get space2xl => kSpace2xl;
  double get space3xl => kSpace3xl;

  /// The whole scale, ascending - handy for sliders/settings.
  static const List<double> spaceScale = <double>[
    kSpaceXs,
    kSpaceS,
    kSpaceM,
    kSpaceL,
    kSpaceXl,
    kSpace2xl,
    kSpace3xl,
  ];

  // --- Effects -------------------------------------------------------------

  /// Sigma for the glass (blur) app bar / bottom bar.
  static const double kGlassBlur = 16;

  double get glassBlur => kGlassBlur;

  /// Opacity of the glass surfaces sitting on top of scrolling content.
  static const double kGlassOpacity = 0.72;

  double get glassOpacity => kGlassOpacity;

  /// Maximum measure for reading text.
  static const double kReadingMaxWidth = 680;

  double get readingMaxWidth => kReadingMaxWidth;

  /// Standard motion duration and curve. Nothing bouncy.
  static const Duration motionFast = Duration(milliseconds: 200);
  static const Duration motionMedium = Duration(milliseconds: 260);
  static const Duration motionSlow = Duration(milliseconds: 320);
  static const Curve motionCurve = Curves.easeOutCubic;

  // --- Convenience ---------------------------------------------------------

  /// A 1px hairline side. Use instead of a shadow.
  BorderSide get hairlineSide => BorderSide(color: hairline, width: 1);

  BorderSide get hairlineStrongSide =>
      BorderSide(color: hairlineStrong, width: 1);

  Border get hairlineBorder => Border.fromBorderSide(hairlineSide);

  /// Surface colour for a card "level" (1, 2 or 3).
  Color surfaceForLevel(int level) => switch (level) {
    <= 1 => surface1,
    2 => surface2,
    _ => surface3,
  };

  // --- Factories -----------------------------------------------------------

  /// Dark tokens. [pureBlack] switches to the AMOLED variant.
  factory AppTokens.dark({required Color accent, bool pureBlack = false}) {
    return AppTokens(
      brightness: Brightness.dark,
      bg: pureBlack ? AppColors.blackBg : AppColors.darkBg,
      surface1: pureBlack ? AppColors.blackSurface1 : AppColors.darkSurface1,
      surface2: pureBlack ? AppColors.blackSurface2 : AppColors.darkSurface2,
      surface3: pureBlack ? AppColors.blackSurface3 : AppColors.darkSurface3,
      hairline: AppColors.white.withValues(alpha: AppColors.darkHairlineAlpha),
      hairlineStrong: AppColors.white.withValues(
        alpha: AppColors.darkHairlineStrongAlpha,
      ),
      textPrimary: AppColors.darkTextPrimary,
      textSecondary: AppColors.darkTextSecondary,
      textTertiary: AppColors.darkTextTertiary,
      accent: accent,
      onAccent: _onAccentFor(accent),
      accentSoft: accent.withValues(alpha: 0.16),
      accentGlow: accent.withValues(alpha: 0.35),
      success: AppColors.successDark,
      warning: AppColors.warningDark,
      danger: AppColors.dangerDark,
    );
  }

  /// Light tokens. [pureBlack] is ignored (it only affects dark mode) but is
  /// accepted so both factories share a signature.
  factory AppTokens.light({required Color accent, bool pureBlack = false}) {
    return AppTokens(
      brightness: Brightness.light,
      bg: AppColors.lightBg,
      surface1: AppColors.lightSurface1,
      surface2: AppColors.lightSurface2,
      surface3: AppColors.lightSurface3,
      hairline: AppColors.black.withValues(alpha: AppColors.lightHairlineAlpha),
      hairlineStrong: AppColors.black.withValues(
        alpha: AppColors.lightHairlineStrongAlpha,
      ),
      textPrimary: AppColors.lightTextPrimary,
      textSecondary: AppColors.lightTextSecondary,
      textTertiary: AppColors.lightTextTertiary,
      accent: accent,
      onAccent: _onAccentFor(accent),
      accentSoft: accent.withValues(alpha: 0.16),
      accentGlow: accent.withValues(alpha: 0.35),
      success: AppColors.successLight,
      warning: AppColors.warningLight,
      danger: AppColors.dangerLight,
    );
  }

  /// Black or white, whichever reads better on [accent].
  static Color _onAccentFor(Color accent) =>
      accent.computeLuminance() > 0.45 ? AppColors.black : AppColors.white;

  // --- ThemeExtension ------------------------------------------------------

  /// The tokens for the nearest [Theme]. Falls back to the dark defaults so a
  /// widget pumped without the app theme still renders.
  static AppTokens of(BuildContext context) {
    return Theme.of(context).extension<AppTokens>() ??
        AppTokens.dark(accent: const Color(0xFF10B981));
  }

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? hairline,
    Color? hairlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? accentGlow,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentGlow: accentGlow ?? this.accentGlow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentGlow: Color.lerp(accentGlow, other.accentGlow, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// `context.tokens` - the ergonomic way to read [AppTokens].
extension AppTokensContext on BuildContext {
  AppTokens get tokens => AppTokens.of(this);
}
