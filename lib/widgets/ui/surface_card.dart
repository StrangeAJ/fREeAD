import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// A layered surface with a hairline border and no shadow.
///
/// ```dart
/// SurfaceCard(level: 1, onTap: open, child: Text('Hello'))
/// ```
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.level = 1,
    this.padding,
    this.margin,
    this.radius,
    this.onTap,
    this.onLongPress,
    this.showBorder = true,
    this.color,
    this.borderColor,
    this.width,
    this.height,
    this.clipBehavior = Clip.antiAlias,
  }) : assert(level >= 1 && level <= 3, 'level must be 1, 2 or 3');

  final Widget child;

  /// Surface layer: 1 = card, 2 = nested/input, 3 = highest.
  final int level;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Corner radius. Defaults to `AppTokens.radiusM` (20).
  final double? radius;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Draw the 1px hairline. Turn off for cards sitting on a matching surface.
  final bool showBorder;

  /// Explicit background, overriding [level].
  final Color? color;

  /// Explicit border colour, overriding the hairline.
  final Color? borderColor;

  final double? width;
  final double? height;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final BorderRadius shape = BorderRadius.circular(radius ?? t.radiusM);

    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (onTap != null || onLongPress != null) {
      content = InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: shape,
        splashColor: t.accentSoft,
        highlightColor: t.accent.withValues(alpha: 0.06),
        child: content,
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color ?? t.surfaceForLevel(level),
        borderRadius: shape,
        border: showBorder
            ? Border.all(color: borderColor ?? t.hairline, width: 1)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        child: content,
      ),
    );
  }
}
