import 'dart:ui';

/// User-selectable accent colour.
///
/// The enum is persisted by `name` (see `SettingsProvider`), so do not rename
/// or reorder the values without a migration.
enum AppAccent { emerald, cyan, violet, amber, rose, mono }

/// Colours and labels attached to [AppAccent].
///
/// Each accent carries two primaries: [darkPrimary] is tuned for the near-black
/// dark surfaces, [lightPrimary] is darkened so it still passes contrast on the
/// off-white light surfaces. [seed] is what `ColorScheme.fromSeed` is given.
extension AppAccentX on AppAccent {
  /// Human readable name for settings.
  String get label => switch (this) {
    AppAccent.emerald => 'Emerald',
    AppAccent.cyan => 'Cyan',
    AppAccent.violet => 'Violet',
    AppAccent.amber => 'Amber',
    AppAccent.rose => 'Rose',
    AppAccent.mono => 'Mono',
  };

  /// Accent used on dark surfaces.
  Color get darkPrimary => switch (this) {
    AppAccent.emerald => const Color(0xFF10B981),
    AppAccent.cyan => const Color(0xFF22D3EE),
    AppAccent.violet => const Color(0xFFA78BFA),
    AppAccent.amber => const Color(0xFFF59E0B),
    AppAccent.rose => const Color(0xFFFB7185),
    AppAccent.mono => const Color(0xFFE5E7EB),
  };

  /// Accent used on light surfaces.
  Color get lightPrimary => switch (this) {
    AppAccent.emerald => const Color(0xFF059669),
    AppAccent.cyan => const Color(0xFF0891B2),
    AppAccent.violet => const Color(0xFF7C3AED),
    AppAccent.amber => const Color(0xFFB45309),
    AppAccent.rose => const Color(0xFFE11D48),
    AppAccent.mono => const Color(0xFF1F2937),
  };

  /// Seed handed to `ColorScheme.fromSeed`.
  ///
  /// `mono` seeds from a slate grey so the generated scheme stays neutral
  /// instead of picking up a hue from the near-white/near-black primaries.
  Color get seed =>
      this == AppAccent.mono ? const Color(0xFF64748B) : darkPrimary;

  /// The accent for a given [brightness].
  Color primaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrimary : lightPrimary;

  /// Colour to draw the swatch with in settings (readable on both modes).
  Color get swatch =>
      this == AppAccent.mono ? const Color(0xFF94A3B8) : darkPrimary;
}
