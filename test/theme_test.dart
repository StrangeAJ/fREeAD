import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/app_settings.dart';
import 'package:freead/theme/accent.dart';
import 'package:freead/theme/app_theme.dart';
import 'package:freead/theme/app_tokens.dart';
import 'package:freead/theme/app_typography.dart';

void main() {
  group('AppTheme builds', () {
    test('every accent x mode x pureBlack builds and carries AppTokens', () {
      for (final AppAccent accent in AppAccent.values) {
        for (final bool pureBlack in <bool>[false, true]) {
          final ThemeData light = AppTheme.light(
            accent: accent,
            pureBlack: pureBlack,
          );
          final ThemeData dark = AppTheme.dark(
            accent: accent,
            pureBlack: pureBlack,
          );

          expect(light.brightness, Brightness.light);
          expect(dark.brightness, Brightness.dark);
          expect(light.useMaterial3, isTrue);
          expect(dark.useMaterial3, isTrue);

          final AppTokens? lightTokens = light.extension<AppTokens>();
          final AppTokens? darkTokens = dark.extension<AppTokens>();
          expect(lightTokens, isNotNull, reason: '$accent light tokens');
          expect(darkTokens, isNotNull, reason: '$accent dark tokens');
          expect(lightTokens!.brightness, Brightness.light);
          expect(darkTokens!.brightness, Brightness.dark);
        }
      }
    });

    test('builds from a dynamic (Material You) scheme', () {
      final ColorScheme dynamicDark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
      );
      final ThemeData theme = AppTheme.dark(
        accent: AppAccent.emerald,
        dynamicScheme: dynamicDark,
      );

      // Surfaces stay ours even with a dynamic scheme.
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0B0C0E));
      expect(theme.colorScheme.primary, dynamicDark.primary);
      expect(theme.extension<AppTokens>()!.accent, dynamicDark.primary);
    });

    test('a mismatched dynamic scheme is re-derived for the mode', () {
      final ColorScheme lightDynamic = ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C4DFF),
      );
      final ThemeData dark = AppTheme.dark(
        accent: AppAccent.cyan,
        dynamicScheme: lightDynamic,
      );
      expect(dark.colorScheme.brightness, Brightness.dark);
    });
  });

  group('surface tokens', () {
    test('dark uses the near-black palette', () {
      final AppTokens t = AppTheme.dark(
        accent: AppAccent.emerald,
      ).extension<AppTokens>()!;
      expect(t.bg, const Color(0xFF0B0C0E));
      expect(t.surface1, const Color(0xFF121317));
      expect(t.surface2, const Color(0xFF191B20));
      expect(t.surface3, const Color(0xFF22252B));
      expect(t.textPrimary, const Color(0xFFECEDEF));
      expect(t.textSecondary, const Color(0xFFA0A4AD));
      expect(t.textTertiary, const Color(0xFF6B7079));
      expect(t.accent, const Color(0xFF10B981));
    });

    test('pure black swaps the dark surfaces', () {
      final AppTokens t = AppTheme.dark(
        accent: AppAccent.emerald,
        pureBlack: true,
      ).extension<AppTokens>()!;
      expect(t.bg, const Color(0xFF000000));
      expect(t.surface1, const Color(0xFF0A0A0A));
      expect(t.surface2, const Color(0xFF111111));
      expect(t.surface3, const Color(0xFF181818));
    });

    test('light uses the off-white palette and never goes pure black', () {
      final AppTokens t = AppTheme.light(
        accent: AppAccent.emerald,
        pureBlack: true,
      ).extension<AppTokens>()!;
      expect(t.bg, const Color(0xFFF6F7F9));
      expect(t.surface1, const Color(0xFFFFFFFF));
      expect(t.surface2, const Color(0xFFF0F2F5));
      expect(t.surface3, const Color(0xFFE6E9EE));
      expect(t.textPrimary, const Color(0xFF15171A));
      expect(t.accent, const Color(0xFF059669));
    });

    test('shape and spacing scales match the design language', () {
      final AppTokens t = AppTheme.dark(
        accent: AppAccent.emerald,
      ).extension<AppTokens>()!;
      expect(<double>[t.radiusS, t.radiusM, t.radiusL], <double>[12, 20, 28]);
      expect(AppTokens.spaceScale, <double>[4, 8, 12, 16, 20, 24, 32]);
      expect(t.glassBlur, 16);
      expect(t.readingMaxWidth, 680);
    });

    test('accentSoft is 16% and accentGlow 35% of the accent', () {
      final AppTokens t = AppTheme.dark(
        accent: AppAccent.violet,
      ).extension<AppTokens>()!;
      expect(t.accentSoft.a, closeTo(0.16, 0.005));
      expect(t.accentGlow.a, closeTo(0.35, 0.005));
      expect(t.accentSoft.r, t.accent.r);
    });

    test('onAccent is readable on every accent', () {
      for (final AppAccent accent in AppAccent.values) {
        for (final ThemeData theme in <ThemeData>[
          AppTheme.light(accent: accent),
          AppTheme.dark(accent: accent),
        ]) {
          final AppTokens t = theme.extension<AppTokens>()!;
          final double contrast =
              (t.accent.computeLuminance() - t.onAccent.computeLuminance())
                  .abs();
          expect(
            contrast,
            greaterThan(0.3),
            reason: '${accent.name} ${theme.brightness}',
          );
        }
      }
    });

    test('copyWith and lerp keep the extension usable', () {
      final AppTokens dark = AppTheme.dark(
        accent: AppAccent.emerald,
      ).extension<AppTokens>()!;
      final AppTokens light = AppTheme.light(
        accent: AppAccent.emerald,
      ).extension<AppTokens>()!;

      expect(
        dark.copyWith(bg: const Color(0xFF123456)).bg,
        const Color(0xFF123456),
      );
      expect(dark.copyWith().surface2, dark.surface2);

      final AppTokens mid = dark.lerp(light, 0.5);
      expect(mid.bg, isNot(dark.bg));
      expect(dark.lerp(null, 0.5), same(dark));
      expect(dark.lerp(dark, 0.0).bg, dark.bg);
    });
  });

  group('component themes are defined for both modes', () {
    for (final MapEntry<String, ThemeData> entry in <String, ThemeData>{
      'light': AppTheme.light(accent: AppAccent.emerald),
      'dark': AppTheme.dark(accent: AppAccent.emerald),
    }.entries) {
      final String mode = entry.key;
      final ThemeData theme = entry.value;
      final AppTokens t = theme.extension<AppTokens>()!;

      test('$mode: surfaces, hairlines and shapes', () {
        expect(theme.scaffoldBackgroundColor, t.bg);
        expect(theme.canvasColor, t.bg);
        expect(theme.dividerColor, t.hairline);
        expect(theme.dividerTheme.color, t.hairline);
        expect(theme.dividerTheme.thickness, 1);

        // Hairlines, not shadows.
        expect(theme.shadowColor, Colors.transparent);
        expect(theme.cardTheme.elevation, 0);
        expect(theme.cardTheme.color, t.surface1);
        expect(theme.cardTheme.margin, EdgeInsets.zero);
        final RoundedRectangleBorder cardShape =
            theme.cardTheme.shape! as RoundedRectangleBorder;
        expect(cardShape.borderRadius, BorderRadius.circular(20));
        expect(cardShape.side.color, t.hairline);
      });

      test('$mode: app bar, navigation bar and chips', () {
        expect(theme.appBarTheme.backgroundColor, Colors.transparent);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.appBarTheme.titleTextStyle!.fontFamily, 'SpaceGrotesk');
        expect(theme.appBarTheme.titleTextStyle!.fontSize, 22);
        expect(theme.appBarTheme.titleTextStyle!.fontWeight, FontWeight.w600);

        expect(theme.navigationBarTheme.backgroundColor, Colors.transparent);
        expect(theme.navigationBarTheme.indicatorColor, t.accentSoft);
        expect(
          theme.navigationBarTheme.labelTextStyle!.resolve(<WidgetState>{
            WidgetState.selected,
          })!.color,
          t.accent,
        );

        expect(theme.chipTheme.shape, isA<StadiumBorder>());
        expect(theme.chipTheme.selectedColor, t.accentSoft);
        expect(theme.chipTheme.backgroundColor, t.surface2);
        expect(theme.chipTheme.side!.color, t.hairline);
        expect(theme.chipTheme.showCheckmark, isFalse);
      });

      test('$mode: buttons keep a 44px target and a 12px radius', () {
        for (final ButtonStyle? style in <ButtonStyle?>[
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
          theme.elevatedButtonTheme.style,
          theme.iconButtonTheme.style,
        ]) {
          expect(style, isNotNull);
          final Size? min = style!.minimumSize?.resolve(<WidgetState>{});
          expect(min, isNotNull);
          expect(min!.height, greaterThanOrEqualTo(44));
          final RoundedRectangleBorder shape =
              style.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(12));
        }
        expect(
          theme.filledButtonTheme.style!.backgroundColor!.resolve(
            <WidgetState>{},
          ),
          t.accent,
        );
        expect(theme.floatingActionButtonTheme.backgroundColor, t.accent);
        expect(theme.floatingActionButtonTheme.elevation, 0);
      });

      test('$mode: inputs, sheets, dialogs, snackbar, menus', () {
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.inputDecorationTheme.fillColor, t.surface2);
        expect(
          (theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
              .borderSide
              .color,
          t.accent,
        );

        expect(theme.bottomSheetTheme.backgroundColor, t.surface1);
        expect(theme.bottomSheetTheme.modalBackgroundColor, t.surface1);
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(
          (theme.bottomSheetTheme.shape! as RoundedRectangleBorder)
              .borderRadius,
          const BorderRadius.vertical(top: Radius.circular(28)),
        );

        expect(theme.dialogTheme.backgroundColor, t.surface1);
        expect(
          (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(28),
        );

        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.snackBarTheme.backgroundColor, t.surface3);
        expect(theme.snackBarTheme.actionTextColor, t.accent);
        expect(
          (theme.snackBarTheme.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12),
        );

        expect(theme.popupMenuTheme.color, t.surface2);
        expect(theme.popupMenuTheme.elevation, 0);
        expect(theme.listTileTheme.textColor, t.textPrimary);
        expect(theme.tabBarTheme.labelColor, t.accent);
        expect(theme.progressIndicatorTheme.color, t.accent);
        expect(theme.sliderTheme.activeTrackColor, t.accent);
        expect(
          theme.switchTheme.trackColor!.resolve(<WidgetState>{
            WidgetState.selected,
          }),
          t.accent,
        );
        expect(theme.textSelectionTheme.cursorColor, t.accent);
        expect(theme.textSelectionTheme.selectionColor!.a, closeTo(0.3, 0.005));
      });

      test('$mode: page transitions fade forward', () {
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<FadeForwardsPageTransitionsBuilder>(),
        );
      });
    }
  });

  group('AppTypography', () {
    final TextTheme text = AppTheme.dark(accent: AppAccent.emerald).textTheme;

    test('display and headline use Space Grotesk', () {
      for (final TextStyle? style in <TextStyle?>[
        text.displayLarge,
        text.displayMedium,
        text.displaySmall,
        text.headlineLarge,
        text.headlineMedium,
        text.headlineSmall,
      ]) {
        expect(style!.fontFamily, 'SpaceGrotesk');
        expect(style.letterSpacing, lessThan(0));
      }
    });

    test('title, body and label use Inter', () {
      for (final TextStyle? style in <TextStyle?>[
        text.titleLarge,
        text.titleMedium,
        text.titleSmall,
        text.bodyLarge,
        text.bodyMedium,
        text.bodySmall,
        text.labelLarge,
        text.labelMedium,
        text.labelSmall,
      ]) {
        expect(style!.fontFamily, 'Inter');
      }
    });

    test('labelSmall is the section-header style', () {
      expect(text.labelSmall!.fontSize, 12);
      expect(text.labelSmall!.fontWeight, FontWeight.w600);
      expect(text.labelSmall!.letterSpacing, 0.8);
    });

    test('readingBody picks the right bundled family', () {
      final TextStyle serif = AppTypography.readingBody(
        ReadingFont.serif,
        18,
        1.6,
      );
      final TextStyle sans = AppTypography.readingBody(
        ReadingFont.sans,
        20,
        1.8,
      );
      expect(serif.fontFamily, 'Literata');
      expect(serif.fontSize, 18);
      expect(serif.height, 1.6);
      expect(sans.fontFamily, 'Inter');
      expect(sans.fontSize, 20);
      expect(sans.height, 1.8);
    });

    test('readingHeading uses Space Grotesk and shrinks with the level', () {
      final TextStyle h1 = AppTypography.readingHeading(1);
      final TextStyle h6 = AppTypography.readingHeading(6);
      expect(h1.fontFamily, 'SpaceGrotesk');
      expect(h6.fontFamily, 'SpaceGrotesk');
      expect(h1.fontSize! > h6.fontSize!, isTrue);
      // Out of range levels clamp instead of throwing.
      expect(AppTypography.readingHeading(0).fontSize, h1.fontSize);
      expect(AppTypography.readingHeading(9).fontSize, h6.fontSize);
    });
  });

  group('AppAccent', () {
    test('every accent has a label and both primaries', () {
      for (final AppAccent accent in AppAccent.values) {
        expect(accent.label, isNotEmpty);
        expect(accent.darkPrimary, isNot(accent.lightPrimary));
        expect(accent.primaryFor(Brightness.dark), accent.darkPrimary);
        expect(accent.primaryFor(Brightness.light), accent.lightPrimary);
      }
    });

    test('spec colours', () {
      expect(AppAccent.emerald.darkPrimary, const Color(0xFF10B981));
      expect(AppAccent.emerald.lightPrimary, const Color(0xFF059669));
      expect(AppAccent.cyan.darkPrimary, const Color(0xFF22D3EE));
      expect(AppAccent.cyan.lightPrimary, const Color(0xFF0891B2));
      expect(AppAccent.violet.darkPrimary, const Color(0xFFA78BFA));
      expect(AppAccent.violet.lightPrimary, const Color(0xFF7C3AED));
      expect(AppAccent.amber.darkPrimary, const Color(0xFFF59E0B));
      expect(AppAccent.amber.lightPrimary, const Color(0xFFB45309));
      expect(AppAccent.rose.darkPrimary, const Color(0xFFFB7185));
      expect(AppAccent.rose.lightPrimary, const Color(0xFFE11D48));
      expect(AppAccent.mono.darkPrimary, const Color(0xFFE5E7EB));
      expect(AppAccent.mono.lightPrimary, const Color(0xFF1F2937));
    });
  });

  testWidgets('context.tokens resolves inside the app theme', (
    WidgetTester tester,
  ) async {
    late AppTokens seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(accent: AppAccent.rose),
        home: Builder(
          builder: (BuildContext context) {
            seen = context.tokens;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.accent, const Color(0xFFFB7185));
    expect(seen.bg, const Color(0xFF0B0C0E));
  });

  testWidgets('context.tokens falls back outside the app theme', (
    WidgetTester tester,
  ) async {
    late AppTokens seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            seen = context.tokens;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.bg, const Color(0xFF0B0C0E));
  });
}
