import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The app bar for every screen: blurred glass over the content, a hairline at
/// the bottom, no shadow.
///
/// ```dart
/// GlassAppBar(title: 'FreeAd', actions: [IconButton(...)])
/// ```
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.bottom,
    this.showBack = true,
    this.centerTitle = false,
    this.opaque = false,
    this.showHairline = true,
    this.toolbarHeight = kToolbarHeight,
  });

  /// Plain text title (rendered in Space Grotesk via the app bar theme).
  final String? title;

  /// Custom title widget - wins over [title].
  final Widget? titleWidget;

  final List<Widget>? actions;

  /// Custom leading widget. When null and [showBack] is true a back button is
  /// implied by the route.
  final Widget? leading;

  /// Extra row below the toolbar (filter chips, a progress bar, ...).
  final PreferredSizeWidget? bottom;

  final bool showBack;
  final bool centerTitle;

  /// Skip the blur and paint a solid surface (cheaper, used for sheets).
  final bool opaque;

  final bool showHairline;

  final double toolbarHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    final Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque
            ? t.surface1
            : t.surface1.withValues(alpha: t.glassOpacity),
        border: showHairline
            ? Border(bottom: BorderSide(color: t.hairline, width: 1))
            : null,
      ),
      child: AppBar(
        title: titleWidget ?? (title != null ? Text(title!) : null),
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: showBack,
        centerTitle: centerTitle,
        toolbarHeight: toolbarHeight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: bottom,
      ),
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
