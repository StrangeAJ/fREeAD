import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// A single-select segmented control drawn as pills inside a hairline track.
///
/// ```dart
/// SegmentedPills<ReadingFont>(
///   values: ReadingFont.values,
///   selected: settings.readingFont,
///   labelBuilder: (f) => f.label,
///   onChanged: settings.setReadingFont,
/// )
/// ```
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.values,
    this.selected,
    this.value,
    required this.onChanged,
    required this.labelBuilder,
    this.iconBuilder,
    this.expand = true,
    this.dense = false,
    this.compact = false,
  });

  /// The list of options to display.
  final List<T> values;
  /// Alias for [values] for API compatibility.
  List<T> get options => values;

  /// The currently selected value (primary parameter).
  final T? selected;
  /// Alias for [selected] for API compatibility.
  final T? value;

  final ValueChanged<T> onChanged;

  final String Function(T value) labelBuilder;
  final IconData? Function(T value)? iconBuilder;

  /// Stretch the segments to fill the width.
  final bool expand;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final T? currentSelected = selected ?? value;

    List<Widget> buildSegments() => <Widget>[
      for (final T value in values)
        _segment(context, t, text, value, value == currentSelected),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.hairline),
      ),
      child: expand
          ? Row(
              children: <Widget>[
                for (final Widget w in buildSegments()) Expanded(child: w),
              ],
            )
          : Row(mainAxisSize: MainAxisSize.min, children: buildSegments()),
    );
  }

  Widget _segment(
    BuildContext context,
    AppTokens t,
    TextTheme text,
    T value,
    bool isSelected,
  ) {
    final IconData? icon = iconBuilder?.call(value);
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? t.surface1 : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? t.hairlineStrong : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(value),
          splashColor: t.accentSoft,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? t.spaceM : t.spaceL,
              vertical: dense ? 6 : t.spaceS + 1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? t.accent : t.textSecondary,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    labelBuilder(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.labelLarge?.copyWith(
                      color: isSelected ? t.accent : t.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
