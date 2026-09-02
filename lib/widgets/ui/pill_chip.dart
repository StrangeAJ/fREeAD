import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The one chip in the app: a pill with a hairline border that fills with
/// `accentSoft` when selected.
///
/// ```dart
/// PillChip(label: 'Unread', count: 12, selected: true, onTap: () {})
/// ```
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.count,
    this.dotColor,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.color,
    this.trailing,
    this.dense = false,
  });

  final String label;

  /// Optional leading glyph.
  final IconData? icon;

  final bool selected;

  /// Optional trailing count, rendered inside the pill.
  final int? count;

  /// Optional colour dot (categories).
  final Color? dotColor;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final bool enabled;

  /// Overrides the accent for this chip (e.g. the danger colour for errors).
  final Color? color;

  /// Arbitrary trailing widget, drawn after [count].
  final Widget? trailing;

  /// Tighter padding for dense rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color base = color ?? t.accent;
    final Color fg = !enabled
        ? t.textTertiary
        : selected
        ? base
        : t.textSecondary;

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? base.withValues(alpha: 0.16) : t.surface2,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? base.withValues(alpha: 0.45) : t.hairline,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          splashColor: base.withValues(alpha: 0.12),
          highlightColor: base.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? t.spaceM : t.spaceL - 2,
              vertical: dense ? 6 : t.spaceS,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (dotColor != null) ...<Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    count! > 999 ? '999+' : '$count',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0,
                      color: selected ? base : t.textTertiary,
                    ),
                  ),
                ],
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
