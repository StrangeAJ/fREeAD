import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The primary action: a filled accent button with a soft accent glow.
///
/// This is the only place in the app where a shadow is used - and it is the
/// accent glow, not a drop shadow.
///
/// ```dart
/// GlowButton(label: 'Ask AI', icon: Icons.auto_awesome_rounded, onPressed: _ask)
/// ```
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = false,
    this.glow = true,
    this.tonal = false,
    this.padding,
    this.color,
  });

  final String label;
  final IconData? icon;

  /// Disabled when null (or while [loading]).
  final VoidCallback? onPressed;

  /// Swaps the icon for a spinner and blocks taps.
  final bool loading;

  /// Stretch to the available width.
  final bool expand;

  /// Draw the accent glow behind the button.
  final bool glow;

  /// Tonal variant: `accentSoft` fill with accent text, no glow.
  final bool tonal;

  final EdgeInsetsGeometry? padding;

  /// Overrides the accent for this button.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color base = color ?? t.accent;
    final bool enabled = onPressed != null && !loading;

    final Widget child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                tonal ? base : t.onAccent,
              ),
            ),
          )
        else if (icon != null)
          Icon(icon, size: 18),
        if (loading || icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    final ButtonStyle style = FilledButton.styleFrom(
      backgroundColor: tonal ? base.withValues(alpha: 0.16) : base,
      foregroundColor: tonal
          ? base
          : (color == null
                ? t.onAccent
                : (base.computeLuminance() > 0.45
                      ? const Color(0xFF000000)
                      : const Color(0xFFFFFFFF))),
      disabledBackgroundColor: t.surface3,
      disabledForegroundColor: t.textTertiary,
      minimumSize: Size(expand ? double.infinity : 64, 46),
      padding:
          padding ??
          EdgeInsets.symmetric(horizontal: t.spaceXl, vertical: t.spaceM),
      shape: RoundedRectangleBorder(borderRadius: t.borderRadiusS),
      elevation: 0,
      textStyle: Theme.of(context).textTheme.labelLarge,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final Widget button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: style,
      child: child,
    );

    if (!glow || tonal || !enabled) {
      return expand ? SizedBox(width: double.infinity, child: button) : button;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: t.borderRadiusS,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: base.withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
