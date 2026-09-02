import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The scaffold every screen uses.
///
/// Defaults to edge-to-edge: the body extends behind the (glass) app bar and
/// bottom bar so content blurs underneath them. Add the app bar height to your
/// scroll padding, or pass `extendBodyBehindAppBar: false` for simple screens.
///
/// ```dart
/// AppScaffold(
///   appBar: const GlassAppBar(title: 'Settings'),
///   body: ListView(...),
/// )
/// ```
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.backgroundColor,
    this.extendBody = true,
    this.extendBodyBehindAppBar = true,
    this.resizeToAvoidBottomInset,
    this.safeAreaTop = false,
    this.safeAreaBottom = false,
  });

  /// Usually a `GlassAppBar`.
  final PreferredSizeWidget? appBar;

  final Widget? body;

  /// Usually a `GlassBottomBar`.
  final Widget? bottomBar;

  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? drawer;

  /// Defaults to the `bg` token.
  final Color? backgroundColor;

  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;

  /// Wrap [body] in a `SafeArea` for the status bar / notch.
  final bool safeAreaTop;

  /// Wrap [body] in a `SafeArea` for the gesture bar.
  final bool safeAreaBottom;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    Widget? content = body;
    if (content != null && (safeAreaTop || safeAreaBottom)) {
      content = SafeArea(
        top: safeAreaTop,
        bottom: safeAreaBottom,
        left: false,
        right: false,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? t.bg,
      appBar: appBar,
      body: content,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      drawer: drawer,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}
