import 'package:flutter/material.dart';
import 'futuristic_widgets.dart';

class FuturisticDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;

  const FuturisticDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        child: RefinedGlassContainer(
          padding: const EdgeInsets.all(24),
          blur: 20,
          opacity: isDark ? 0.05 : 0.8,
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                content,
                if (actions != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showFuturisticDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.4),
    builder: (context) => FuturisticDialog(
      title: title,
      content: content,
      actions: actions,
    ),
  );
}
