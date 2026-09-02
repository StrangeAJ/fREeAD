import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Blurred bar pinned to the bottom of the screen: navigation bars, reader
/// action bars, sticky footers.
///
/// ```dart
/// GlassBottomBar(child: NavigationBar(...))
/// ```
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.child,
    this.padding,
    this.showHairline = true,
    this.safeArea = true,
    this.opaque = false,
  });

  final Widget child;

  /// Padding around [child], inside the blur.
  final EdgeInsetsGeometry? padding;

  final bool showHairline;

  /// Adds the bottom safe-area inset (gesture bar).
  final bool safeArea;

  /// Skip the blur and paint a solid surface.
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (safeArea) {
      content = SafeArea(top: false, left: false, right: false, child: content);
    }

    final Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque
            ? t.surface1
            : t.surface1.withValues(alpha: t.glassOpacity),
        border: showHairline
            ? Border(top: BorderSide(color: t.hairline, width: 1))
            : null,
      ),
      child: content,
    );

    if (opaque) return bar;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: t.glassBlur, sigmaY: t.glassBlur),
        child: bar,
      ),
    );
  }
}
