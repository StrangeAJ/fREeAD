import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// A 2px accent line showing how far through an article the reader is.
///
/// Implements [PreferredSizeWidget] so it can be dropped into
/// `GlassAppBar(bottom: ReadingProgressBar(progress: p))`.
///
/// ```dart
/// ReadingProgressBar(progress: 0.42)
/// ```
class ReadingProgressBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ReadingProgressBar({
    super.key,
    required this.progress,
    this.height = 2,
    this.animate = true,
    this.color,
  });

  /// 0.0 - 1.0. Values outside the range are clamped.
  final double progress;

  final double height;

  /// Animate changes with the standard 200 ms `easeOutCubic`.
  final bool animate;

  final Color? color;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double value = progress.isNaN ? 0 : progress.clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: animate
            ? TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: value),
                duration: AppTokens.motionFast,
                curve: AppTokens.motionCurve,
                builder: (BuildContext context, double v, _) =>
                    FractionallySizedBox(
                      widthFactor: v,
                      child: ColoredBox(color: color ?? t.accent),
                    ),
              )
            : FractionallySizedBox(
                widthFactor: value,
                child: ColoredBox(color: color ?? t.accent),
              ),
      ),
    );
  }
}
