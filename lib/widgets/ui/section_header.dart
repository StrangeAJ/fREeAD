import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Small uppercase label that opens a section, with an optional trailing
/// action.
///
/// ```dart
/// SectionHeader(label: 'Appearance', actionLabel: 'Reset', onAction: _reset)
/// ```
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding,
    this.icon,
  });

  /// Rendered upper-cased with wide tracking.
  final String label;

  /// Optional text button on the right.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Arbitrary trailing widget (wins over [actionLabel]).
  final Widget? trailing;

  final EdgeInsetsGeometry? padding;

  /// Optional leading glyph.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;

    Widget? right = trailing;
    if (right == null && actionLabel != null) {
      right = TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: EdgeInsets.symmetric(horizontal: t.spaceS),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: text.labelMedium,
        ),
        child: Text(actionLabel!),
      );
    }

    return Padding(
      padding:
          padding ??
          EdgeInsets.fromLTRB(t.spaceL, t.spaceXl, t.spaceL, t.spaceS),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: t.textTertiary),
            SizedBox(width: t.spaceS),
          ],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: text.labelSmall?.copyWith(color: t.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (right != null) right,
        ],
      ),
    );
  }
}
