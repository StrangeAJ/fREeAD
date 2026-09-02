/// Compatibility shims for the pre-v3 "futuristic" widgets.
///
/// These keep the old class names and constructor parameters so the screens
/// that have not been rewritten yet still compile. They now delegate to the
/// design system in `lib/widgets/ui/`. **Do not use them in new code** - they
/// are deleted once Phase 2 lands.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'ui/glass_app_bar.dart';

/// Legacy FAB. Prefer `FloatingActionButton` with the app theme.
class FuturisticFAB extends StatelessWidget {
  const FuturisticFAB({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.showPulse = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showPulse;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color bg = backgroundColor ?? t.accent;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: bg.withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onPressed,
        tooltip: tooltip,
        backgroundColor: bg,
        foregroundColor: foregroundColor ?? t.onAccent,
        elevation: 0,
        heroTag: tooltip ?? 'fab_${icon.codePoint}',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, size: 24),
      ),
    );
  }
}

/// Legacy app bar. Prefer `GlassAppBar`.
class FuturisticAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FuturisticAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return GlassAppBar(
      title: title,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
    );
  }
}

/// Legacy glass panel. Prefer `SurfaceCard`, `GlassAppBar` or
/// `GlassBottomBar`.
class RefinedGlassContainer extends StatelessWidget {
  const RefinedGlassContainer({
    super.key,
    required this.child,
    this.blur = 12,
    this.opacity = 0.1,
    this.borderRadius,
    this.padding,
    this.border,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final BorderRadius shape = borderRadius ?? t.borderRadiusM;

    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: t.surface1.withValues(alpha: t.glassOpacity),
            borderRadius: shape,
            border: border ?? t.hairlineBorder,
          ),
          child: child,
        ),
      ),
    );
  }
}
