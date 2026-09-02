import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// A small count pill, e.g. unread counts next to a feed.
///
/// ```dart
/// AppBadge(count: 12)
/// AppBadge(label: 'NEW', color: context.tokens.success)
/// ```
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    this.count,
    this.label,
    this.color,
    this.foregroundColor,
    this.max = 999,
    this.soft = true,
  }) : assert(count != null || label != null, 'count or label is required');

  /// Numeric count. Values above [max] render as `999+`.
  final int? count;

  /// Free-form label (wins over [count]).
  final String? label;

  /// Base colour. Defaults to the accent.
  final Color? color;

  /// Text colour. Defaults to [color] when [soft], else the on-accent colour.
  final Color? foregroundColor;

  final int max;

  /// Soft = tinted background + coloured text. Otherwise solid.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color base = color ?? t.accent;
    final String text =
        label ?? (count! > max ? '$max+' : count!.toStringAsFixed(0));

    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: soft ? base.withValues(alpha: 0.16) : base,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          letterSpacing: 0,
          height: 1.3,
          color:
              foregroundColor ??
              (soft ? base : (base == t.accent ? t.onAccent : t.surface1)),
        ),
      ),
    );
  }
}
