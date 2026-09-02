import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Tone of an [AppSnackBar].
enum AppSnackKind { info, success, error }

/// The only snackbar in the app: floating, surface 3, hairline, radius 12, with
/// a small leading glyph tinted by [AppSnackKind].
///
/// ```dart
/// AppSnackBar.show(context, '12 new articles');
/// AppSnackBar.show(context, 'Could not reach the site',
///     kind: AppSnackKind.error, action: 'Open in browser', onAction: _open);
/// ```
abstract final class AppSnackBar {
  static void show(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onAction,
    AppSnackKind kind = AppSnackKind.info,
    Duration? duration,
  }) {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    if (messenger == null) return;

    final AppTokens t = context.tokens;
    final Color tint = switch (kind) {
      AppSnackKind.info => t.accent,
      AppSnackKind.success => t.success,
      AppSnackKind.error => t.danger,
    };
    final IconData icon = switch (kind) {
      AppSnackKind.info => Icons.info_outline_rounded,
      AppSnackKind.success => Icons.check_circle_outline_rounded,
      AppSnackKind.error => Icons.error_outline_rounded,
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: tint),
              SizedBox(width: t.spaceM),
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: t.textPrimary),
                ),
              ),
            ],
          ),
          backgroundColor: t.surface3,
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          margin: EdgeInsets.all(t.spaceL),
          padding: EdgeInsets.symmetric(
            horizontal: t.spaceL,
            vertical: t.spaceM,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: t.borderRadiusS,
            side: BorderSide(color: tint.withValues(alpha: 0.28)),
          ),
          duration:
              duration ?? Duration(seconds: kind == AppSnackKind.error ? 6 : 3),
          action: action == null
              ? null
              : SnackBarAction(
                  label: action,
                  textColor: tint,
                  onPressed: onAction ?? () {},
                ),
        ),
      );
  }

  /// Shorthand for `show(..., kind: AppSnackKind.success)`.
  static void success(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    action: action,
    onAction: onAction,
    kind: AppSnackKind.success,
  );

  /// Shorthand for `show(..., kind: AppSnackKind.error)`.
  static void error(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    action: action,
    onAction: onAction,
    kind: AppSnackKind.error,
  );

  /// Removes whatever is on screen.
  static void hide(BuildContext context) =>
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}
