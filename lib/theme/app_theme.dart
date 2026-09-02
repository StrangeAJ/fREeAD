import 'package:flutter/material.dart';

import 'accent.dart';
import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// The application theme - "quiet instrument": layered near-black (or
/// off-white) surfaces, 1px hairlines instead of shadows, one accent colour,
/// pill chips, glass bars.
///
/// ```dart
/// MaterialApp(
///   theme: AppTheme.light(accent: settings.accent),
///   darkTheme: AppTheme.dark(accent: settings.accent, pureBlack: settings.pureBlack),
/// )
/// ```
abstract final class AppTheme {
  /// Light theme. [pureBlack] is accepted for signature symmetry and ignored.
  static ThemeData light({
    required AppAccent accent,
    ColorScheme? dynamicScheme,
    bool pureBlack = false,
  }) => _build(
    brightness: Brightness.light,
    accent: accent,
    dynamicScheme: dynamicScheme,
    pureBlack: false,
  );

  /// Dark theme. [pureBlack] switches to the AMOLED surfaces.
  static ThemeData dark({
    required AppAccent accent,
    ColorScheme? dynamicScheme,
    bool pureBlack = false,
  }) => _build(
    brightness: Brightness.dark,
    accent: accent,
    dynamicScheme: dynamicScheme,
    pureBlack: pureBlack,
  );

  /// Convenience shorthands (default accent) for call sites without settings.
  static ThemeData get lightTheme => light(accent: AppAccent.emerald);

  /// Convenience shorthands (default accent) for call sites without settings.
  static ThemeData get darkTheme => dark(accent: AppAccent.emerald);

  // -------------------------------------------------------------------------

  static ThemeData _build({
    required Brightness brightness,
    required AppAccent accent,
    required ColorScheme? dynamicScheme,
    required bool pureBlack,
  }) {
    final bool isDark = brightness == Brightness.dark;

    // A dynamic (Material You) scheme wins over the picked accent, but we still
    // impose our own surfaces so the app looks like itself.
    final ColorScheme base = _baseScheme(brightness, accent, dynamicScheme);
    final Color accentColor = base.primary;

    final AppTokens tokens = isDark
        ? AppTokens.dark(accent: accentColor, pureBlack: pureBlack)
        : AppTokens.light(accent: accentColor);

    final ColorScheme scheme = base.copyWith(
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      primaryContainer: Color.alphaBlend(tokens.accentSoft, tokens.surface2),
      onPrimaryContainer: tokens.accent,
      secondary: tokens.accent,
      onSecondary: tokens.onAccent,
      secondaryContainer: Color.alphaBlend(tokens.accentSoft, tokens.surface2),
      onSecondaryContainer: tokens.accent,
      tertiary: tokens.accent,
      onTertiary: tokens.onAccent,
      error: tokens.danger,
      onError: isDark ? AppColors.black : AppColors.white,
      errorContainer: Color.alphaBlend(
        tokens.danger.withValues(alpha: 0.16),
        tokens.surface2,
      ),
      onErrorContainer: tokens.danger,
      surface: tokens.bg,
      onSurface: tokens.textPrimary,
      onSurfaceVariant: tokens.textSecondary,
      surfaceDim: tokens.bg,
      surfaceBright: tokens.surface3,
      surfaceContainerLowest: tokens.bg,
      surfaceContainerLow: tokens.surface1,
      surfaceContainer: tokens.surface1,
      surfaceContainerHigh: tokens.surface2,
      surfaceContainerHighest: tokens.surface3,
      outline: tokens.hairlineStrong,
      outlineVariant: tokens.hairline,
      inverseSurface: isDark ? tokens.textPrimary : tokens.surface3,
      onInverseSurface: isDark ? tokens.bg : tokens.textPrimary,
      inversePrimary: tokens.accent,
      shadow: AppColors.black,
      scrim: AppColors.black,
      surfaceTint: Colors.transparent,
    );

    final TextTheme textTheme = AppTypography.textTheme().apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
      decorationColor: tokens.textPrimary,
    );

    final RoundedRectangleBorder shapeS = RoundedRectangleBorder(
      borderRadius: tokens.borderRadiusS,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],

      scaffoldBackgroundColor: tokens.bg,
      canvasColor: tokens.bg,
      dividerColor: tokens.hairline,
      shadowColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: _pageTransitions,

      // --- App bar -----------------------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: tokens.spaceL,
        iconTheme: IconThemeData(color: tokens.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: tokens.textPrimary, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.display,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          height: 1.2,
          color: tokens.textPrimary,
        ),
        toolbarTextStyle: textTheme.bodyMedium,
      ),

      // --- Bottom navigation -------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: tokens.accentSoft,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? tokens.accent : tokens.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium!.copyWith(
            color: selected ? tokens.accent : tokens.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),

      // --- Cards --------------------------------------------------------
      cardTheme: CardThemeData(
        color: tokens.surface1,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.borderRadiusM,
          side: tokens.hairlineSide,
        ),
      ),

      // --- Chips (pills) -------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surface2,
        selectedColor: tokens.accentSoft,
        secondarySelectedColor: tokens.accentSoft,
        disabledColor: tokens.surface2,
        surfaceTintColor: Colors.transparent,
        checkmarkColor: tokens.accent,
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        side: tokens.hairlineSide,
        shape: const StadiumBorder(),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spaceM,
          vertical: tokens.spaceS,
        ),
        labelPadding: EdgeInsets.symmetric(horizontal: tokens.spaceXs),
        labelStyle: textTheme.labelLarge!.copyWith(color: tokens.textSecondary),
        secondaryLabelStyle: textTheme.labelLarge!.copyWith(
          color: tokens.accent,
        ),
        iconTheme: IconThemeData(size: 16, color: tokens.textSecondary),
        brightness: brightness,
      ),

      // --- Buttons -------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: tokens.onAccent,
          disabledBackgroundColor: tokens.surface3,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(64, 44),
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceXl),
          shape: shapeS,
          elevation: 0,
          textStyle: textTheme.labelLarge,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.surface2,
          foregroundColor: tokens.textPrimary,
          disabledBackgroundColor: tokens.surface2,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(64, 44),
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceXl),
          shape: shapeS,
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textTheme.labelLarge,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textTertiary,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(64, 44),
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceXl),
          shape: shapeS,
          side: tokens.hairlineStrongSide,
          textStyle: textTheme.labelLarge,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(48, 44),
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceM),
          shape: shapeS,
          textStyle: textTheme.labelLarge,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(44, 44),
          shape: shapeS,
          highlightColor: tokens.accentSoft,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? tokens.accentSoft
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? tokens.accent
                : tokens.textSecondary,
          ),
          side: WidgetStatePropertyAll<BorderSide>(tokens.hairlineSide),
          shape: WidgetStatePropertyAll<OutlinedBorder>(shapeS),
          textStyle: WidgetStatePropertyAll<TextStyle?>(textTheme.labelLarge),
        ),
      ),

      // --- FAB ------------------------------------------------------------
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        splashColor: tokens.onAccent.withValues(alpha: 0.12),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: textTheme.labelLarge,
        iconSize: 24,
      ),

      // --- Inputs ----------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface2,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.spaceL,
          vertical: tokens.spaceM,
        ),
        hintStyle: textTheme.bodyMedium!.copyWith(color: tokens.textTertiary),
        labelStyle: textTheme.bodyMedium!.copyWith(color: tokens.textSecondary),
        floatingLabelStyle: textTheme.labelMedium!.copyWith(
          color: tokens.accent,
        ),
        helperStyle: textTheme.bodySmall!.copyWith(color: tokens.textTertiary),
        errorStyle: textTheme.bodySmall!.copyWith(color: tokens.danger),
        prefixIconColor: tokens.textTertiary,
        suffixIconColor: tokens.textTertiary,
        border: OutlineInputBorder(
          borderRadius: tokens.borderRadiusS,
          borderSide: tokens.hairlineSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadiusS,
          borderSide: tokens.hairlineSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadiusS,
          borderSide: BorderSide(color: tokens.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadiusS,
          borderSide: BorderSide(color: tokens.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadiusS,
          borderSide: BorderSide(color: tokens.danger, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: tokens.borderRadiusS,
          borderSide: tokens.hairlineSide,
        ),
      ),

      // --- Sheets & dialogs -------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface1,
        modalBackgroundColor: tokens.surface1,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        modalBarrierColor: AppColors.black.withValues(alpha: 0.5),
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: tokens.hairlineStrong,
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radiusL),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface1,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        barrierColor: AppColors.black.withValues(alpha: 0.5),
        insetPadding: EdgeInsets.symmetric(
          horizontal: tokens.space2xl,
          vertical: tokens.space2xl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: tokens.borderRadiusL,
          side: tokens.hairlineSide,
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium!.copyWith(
          color: tokens.textSecondary,
        ),
      ),

      // --- Feedback ---------------------------------------------------------
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.surface3,
        actionTextColor: tokens.accent,
        closeIconColor: tokens.textSecondary,
        contentTextStyle: textTheme.bodyMedium!.copyWith(
          color: tokens.textPrimary,
        ),
        elevation: 0,
        insetPadding: EdgeInsets.all(tokens.spaceL),
        shape: RoundedRectangleBorder(
          borderRadius: tokens.borderRadiusS,
          side: tokens.hairlineStrongSide,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.surface3,
          borderRadius: BorderRadius.circular(8),
          border: tokens.hairlineBorder,
        ),
        textStyle: textTheme.bodySmall!.copyWith(color: tokens.textPrimary),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spaceM,
          vertical: tokens.spaceS,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // --- Lists & separators -----------------------------------------------
      dividerTheme: DividerThemeData(
        color: tokens.hairline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.spaceL,
          vertical: tokens.spaceXs,
        ),
        minVerticalPadding: tokens.spaceM,
        horizontalTitleGap: tokens.spaceM,
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        selectedColor: tokens.accent,
        selectedTileColor: tokens.accentSoft,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall!.copyWith(
          color: tokens.textSecondary,
        ),
        leadingAndTrailingTextStyle: textTheme.labelMedium!.copyWith(
          color: tokens.textTertiary,
        ),
        shape: shapeS,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: tokens.accent,
        collapsedIconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        collapsedTextColor: tokens.textPrimary,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: shapeS,
        collapsedShape: shapeS,
      ),

      // --- Controls ----------------------------------------------------------
      sliderTheme: SliderThemeData(
        activeTrackColor: tokens.accent,
        inactiveTrackColor: tokens.surface3,
        thumbColor: tokens.accent,
        overlayColor: tokens.accentSoft,
        valueIndicatorColor: tokens.surface3,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        trackHeight: 4,
        valueIndicatorTextStyle: textTheme.labelMedium!.copyWith(
          color: tokens.textPrimary,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return tokens.textTertiary;
          if (states.contains(WidgetState.selected)) return tokens.onAccent;
          return tokens.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return tokens.surface2;
          if (states.contains(WidgetState.selected)) return tokens.accent;
          return tokens.surface3;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return tokens.hairlineStrong;
        }),
        overlayColor: WidgetStatePropertyAll<Color>(tokens.accentSoft),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color>(tokens.onAccent),
        side: BorderSide(color: tokens.hairlineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.textTertiary,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.surface3,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: tokens.surface1,
        linearMinHeight: 2,
      ),

      // --- Navigation extras --------------------------------------------------
      tabBarTheme: TabBarThemeData(
        labelColor: tokens.accent,
        unselectedLabelColor: tokens.textSecondary,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorColor: tokens.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: tokens.hairline,
        overlayColor: WidgetStatePropertyAll<Color>(tokens.accentSoft),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surface2,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyMedium,
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          textTheme.bodyMedium,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: tokens.hairlineSide,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(tokens.surface2),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: tokens.hairlineSide,
            ),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: tokens.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: tokens.accent,
        textColor: tokens.onAccent,
        textStyle: textTheme.labelSmall!.copyWith(
          letterSpacing: 0,
          fontSize: 11,
        ),
      ),

      // --- Selection -----------------------------------------------------------
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accent,
        selectionColor: tokens.accent.withValues(alpha: 0.3),
        selectionHandleColor: tokens.accent,
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 22),
      primaryIconTheme: IconThemeData(color: tokens.onAccent, size: 22),
    );
  }

  /// `FadeForwardsPageTransitionsBuilder` exists on Flutter 3.32 and carries a
  /// `delegatedTransition`, so the outgoing route animates correctly during an
  /// Android predictive-back gesture.
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
    },
  );

  static ColorScheme _baseScheme(
    Brightness brightness,
    AppAccent accent,
    ColorScheme? dynamicScheme,
  ) {
    if (dynamicScheme != null) {
      if (dynamicScheme.brightness == brightness) return dynamicScheme;
      return ColorScheme.fromSeed(
        seedColor: dynamicScheme.primary,
        brightness: brightness,
      );
    }
    return ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: brightness,
    ).copyWith(primary: accent.primaryFor(brightness));
  }
}
