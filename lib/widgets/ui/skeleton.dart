import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../theme/app_tokens.dart';

/// Drives the shimmer for every [Skeleton] below it.
///
/// One [AnimationController] per group - never one per box. Wrap a whole
/// loading screen in a single `SkeletonGroup`. [Skeleton] creates one
/// implicitly when there is none above it, so a lone placeholder still works.
class SkeletonGroup extends StatefulWidget {
  const SkeletonGroup({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1400),
    this.enabled = true,
  });

  final Widget child;

  /// One full sweep of the highlight.
  final Duration period;

  /// Set to false to freeze the shimmer (e.g. for golden tests).
  final bool enabled;

  @override
  State<SkeletonGroup> createState() => _SkeletonGroupState();
}

class _SkeletonGroupState extends State<SkeletonGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant SkeletonGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.period;
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerScope(animation: _controller, child: widget.child);
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  static _ShimmerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) =>
      oldWidget.animation != animation;
}

/// A single shimmering placeholder block.
///
/// ```dart
/// const Skeleton(width: 120, height: 14)          // one bar
/// Skeleton.lines(3)                               // a paragraph
/// Skeleton.articleList(ArticleListStyle.card)     // a whole loading list
/// ```
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;

  /// Round placeholder (avatars).
  final bool circle;

  /// [count] stacked text bars; the last one is shorter.
  static Widget lines(
    int count, {
    double height = 12,
    double spacing = 10,
    double lastLineFactor = 0.55,
  }) => _SkeletonLines(
    count: count,
    height: height,
    spacing: spacing,
    lastLineFactor: lastLineFactor,
  );

  /// A placeholder article list matching [style].
  static Widget articleList(
    ArticleListStyle style, {
    int count = 6,
    bool showImages = true,
    EdgeInsetsGeometry? padding,
  }) => _SkeletonArticleList(
    style: style,
    count: count,
    showImages: showImages,
    padding: padding,
  );

  @override
  Widget build(BuildContext context) {
    final Widget box = _SkeletonBox(
      width: width,
      height: height,
      radius: circle ? (width ?? height) / 2 : radius,
    );
    // Standalone use: give it its own (single) controller.
    return _ShimmerScope.maybeOf(context) == null
        ? SkeletonGroup(child: box)
        : box;
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({this.width, required this.height, required this.radius});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final _ShimmerScope? scope = _ShimmerScope.maybeOf(context);
    final Color base = t.surface2;
    final Color highlight = Color.alphaBlend(t.hairlineStrong, t.surface3);

    if (scope == null) {
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedBuilder(
          animation: scope.animation,
          builder: (BuildContext context, Widget? child) {
            final double dx = -1.6 + 3.2 * scope.animation.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment(dx - 0.7, 0),
                  end: Alignment(dx + 0.7, 0),
                  colors: <Color>[base, highlight, base],
                  stops: const <double>[0.0, 0.5, 1.0],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SkeletonLines extends StatelessWidget {
  const _SkeletonLines({
    required this.count,
    required this.height,
    required this.spacing,
    required this.lastLineFactor,
  });

  final int count;
  final double height;
  final double spacing;
  final double lastLineFactor;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < count; i++) {
      final bool last = i == count - 1 && count > 1;
      children.add(
        last
            ? FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: lastLineFactor,
                child: _SkeletonBox(height: height, radius: height / 2),
              )
            : _SkeletonBox(height: height, radius: height / 2),
      );
      if (i != count - 1) children.add(SizedBox(height: spacing));
    }

    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    return _ShimmerScope.maybeOf(context) == null
        ? SkeletonGroup(child: column)
        : column;
  }
}

class _SkeletonArticleList extends StatelessWidget {
  const _SkeletonArticleList({
    required this.style,
    required this.count,
    required this.showImages,
    this.padding,
  });

  final ArticleListStyle style;
  final int count;
  final bool showImages;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return SkeletonGroup(
      child: ListView.separated(
        padding:
            padding ??
            EdgeInsets.symmetric(horizontal: t.spaceL, vertical: t.spaceM),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (BuildContext context, int index) =>
            SizedBox(height: t.spaceM),
        itemBuilder: (BuildContext context, int index) => switch (style) {
          ArticleListStyle.card => _cardItem(t),
          ArticleListStyle.list => _listItem(t),
          ArticleListStyle.compact => _compactItem(t),
        },
      ),
    );
  }

  Widget _cardItem(AppTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (showImages) ...<Widget>[
        const AspectRatio(
          aspectRatio: 16 / 9,
          child: _SkeletonBox(height: double.infinity, radius: 16),
        ),
        SizedBox(height: t.spaceM),
      ],
      Row(
        children: <Widget>[
          const _SkeletonBox(width: 20, height: 20, radius: 10),
          SizedBox(width: t.spaceS),
          const _SkeletonBox(width: 96, height: 10, radius: 5),
        ],
      ),
      SizedBox(height: t.spaceM),
      const _SkeletonBox(height: 16, radius: 8),
      SizedBox(height: t.spaceS),
      const FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: 0.7,
        child: _SkeletonBox(height: 16, radius: 8),
      ),
      SizedBox(height: t.spaceM),
      const _SkeletonBox(height: 11, radius: 6),
    ],
  );

  Widget _listItem(AppTokens t) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SkeletonBox(height: 14, radius: 7),
            SizedBox(height: t.spaceS),
            const FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.8,
              child: _SkeletonBox(height: 14, radius: 7),
            ),
            SizedBox(height: t.spaceM),
            const FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.45,
              child: _SkeletonBox(height: 10, radius: 5),
            ),
          ],
        ),
      ),
      if (showImages) ...<Widget>[
        SizedBox(width: t.spaceM),
        const _SkeletonBox(width: 72, height: 72, radius: 14),
      ],
    ],
  );

  Widget _compactItem(AppTokens t) => Row(
    children: <Widget>[
      const _SkeletonBox(width: 8, height: 8, radius: 4),
      SizedBox(width: t.spaceM),
      const Expanded(child: _SkeletonBox(height: 12, radius: 6)),
      SizedBox(width: t.spaceM),
      const _SkeletonBox(width: 44, height: 10, radius: 5),
    ],
  );
}
