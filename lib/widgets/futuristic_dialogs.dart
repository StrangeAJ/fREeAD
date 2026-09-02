/// Compatibility shims for the pre-v3 dialogs. New code uses `showAppDialog` /
/// `showAppConfirm` from `lib/widgets/ui/app_dialog.dart`.
library;

import 'package:flutter/material.dart';

import 'ui/app_dialog.dart';

/// Legacy dialog body. Renders with the v3 dialog theme (surface 1, radius 28,
/// hairline border).
class FuturisticDialog extends StatelessWidget {
  const FuturisticDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: actions,
    );
  }
}

/// Legacy dialog launcher. Prefer [showAppDialog].
Future<T?> showFuturisticDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
}) {
  return showAppDialog<T>(
    context,
    title: title,
    content: content,
    actions: actions ?? const <Widget>[],
  );
}
