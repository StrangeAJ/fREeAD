import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// List-item entrance: a short fade plus a small upward slide, staggered by
/// [index]. The stagger is capped at [maxStaggerIndex] items so long lists do
/// not animate for seconds.
///
/// ```dart
/// FadeSlideIn(index: i, child: ArticleCard(article: articles[i]))
/// ```
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = AppTokens.motionMedium,
    this.stagger = const Duration(milliseconds: 24),
    this.maxStaggerIndex = 12,
    this.offset = 12,
    this.enabled = true,
  });

  final Widget child;

  /// Position in the list - drives the delay.
  final int index;

  final Duration duration;
  final Duration stagger;
  final int maxStaggerIndex;

  /// Vertical travel in logical pixels.
  final double offset;

  /// Set to false to render the child immediately (e.g. reduced motion).
  final bool enabled;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppTokens.motionCurve,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    final int steps = widget.index.clamp(0, widget.maxStaggerIndex);
    final Duration delay = widget.stagger * steps;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
