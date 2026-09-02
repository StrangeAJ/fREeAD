import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The app's dialog: surface 1, 28px radius, hairline border, no shadow.
///
/// Pass either [message] (plain text) or [content] (any widget).
///
/// ```dart
/// await showAppDialog<void>(
///   context,
///   title: 'Reset settings',
///   message: 'Every preference goes back to its default.',
///   actions: [TextButton(onPressed: ..., child: const Text('Close'))],
/// );
/// ```
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const <Widget>[],
  bool barrierDismissible = true,
  IconData? icon,
  Color? iconColor,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext dialogContext) {
      final AppTokens t = dialogContext.tokens;
      final TextTheme text = Theme.of(dialogContext).textTheme;

      return AlertDialog(
        icon: icon == null
            ? null
            : Icon(icon, color: iconColor ?? t.accent, size: 28),
        title: Text(title),
        titleTextStyle: text.headlineSmall?.copyWith(color: t.textPrimary),
        content:
            content ??
            (message == null
                ? null
                : Text(
                    message,
                    style: text.bodyMedium?.copyWith(color: t.textSecondary),
                  )),
        actionsPadding: EdgeInsets.fromLTRB(t.spaceL, 0, t.spaceL, t.spaceL),
        actions: actions.isEmpty ? null : actions,
      );
    },
  );
}

/// A yes/no confirmation. Returns true only when the user confirms.
///
/// ```dart
/// if (await showAppConfirm(context, 'Delete feed?',
///     'Its articles are removed too.', destructive: true)) { ... }
/// ```
Future<bool> showAppConfirm(
  BuildContext context,
  String title,
  String message, {
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool? result = await showAppDialog<bool>(
    context,
    title: title,
    message: message,
    actions: <Widget>[
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: context.tokens.textSecondary,
          ),
          child: Text(cancelLabel),
        ),
      ),
      Builder(
        builder: (BuildContext context) {
          final AppTokens t = context.tokens;
          return FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: t.danger,
                    foregroundColor: t.brightness == Brightness.dark
                        ? const Color(0xFF000000)
                        : const Color(0xFFFFFFFF),
                  )
                : null,
            child: Text(confirmLabel),
          );
        },
      ),
    ],
  );
  return result ?? false;
}
