/// Compatibility shims for the pre-v3 buttons. New code uses `GlowButton`
/// (`lib/widgets/ui/glow_button.dart`) or the themed Material buttons.
library;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Legacy primary button. Prefer `GlowButton`.
class FuturisticGlowButton extends StatelessWidget {
  const FuturisticGlowButton({
    super.key,
    this.onPressed,
    required this.child,
    this.icon,
    this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.glowColor,
    this.showGlow = true,
    this.glowRadius = 20.0,
    this.glowSpread = 2.0,
    this.padding,
    this.borderRadius,
    this.isToggled = false,
    this.isLoading = false,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final String? label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? glowColor;
  final bool showGlow;
  final double glowRadius;
  final double glowSpread;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool isToggled;
  final bool isLoading;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color bg = backgroundColor ?? t.accent;
    final Color fg = foregroundColor ?? t.onAccent;
    final BorderRadius shape = borderRadius ?? t.borderRadiusS;

    final ButtonStyle effectiveStyle =
        style ??
        FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: t.surface3,
          disabledForegroundColor: t.textTertiary,
          minimumSize: const Size(64, 46),
          padding:
              padding ??
              EdgeInsets.symmetric(horizontal: t.spaceXl, vertical: t.spaceM),
          shape: RoundedRectangleBorder(borderRadius: shape),
          elevation: 0,
        );

    final Widget button = icon != null && label != null
        ? FilledButton.icon(
            onPressed: isLoading ? null : onPressed,
            style: effectiveStyle,
            icon: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Icon(icon, size: 18),
            label: Text(label!),
          )
        : FilledButton(
            onPressed: isLoading ? null : onPressed,
            style: effectiveStyle,
            child: child,
          );

    if (!showGlow || onPressed == null) return button;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (glowColor ?? bg).withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: button,
    );
  }
}

/// Legacy secondary button. Prefer `OutlinedButton` with the app theme.
class FuturisticSecondaryButton extends StatelessWidget {
  const FuturisticSecondaryButton({
    super.key,
    this.onPressed,
    required this.child,
    this.icon,
    this.label,
    this.padding,
    this.borderRadius,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final String? label;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ButtonStyle style = OutlinedButton.styleFrom(
      foregroundColor: t.textPrimary,
      minimumSize: const Size(64, 46),
      padding:
          padding ??
          EdgeInsets.symmetric(horizontal: t.spaceXl, vertical: t.spaceM),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? t.borderRadiusS,
      ),
      side: t.hairlineStrongSide,
    );

    if (icon != null && label != null) {
      return OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        style: style,
        icon: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(t.textPrimary),
                ),
              )
            : Icon(icon, size: 18),
        label: Text(label!),
      );
    }

    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: style,
      child: child,
    );
  }
}
