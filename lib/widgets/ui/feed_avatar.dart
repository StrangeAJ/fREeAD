import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';

/// Favicon (or feed image) with an initials fallback.
///
/// Sizes used across the app: 20 (compact rows), 28 (meta rows), 40 (feed
/// lists).
///
/// ```dart
/// FeedAvatar(title: feed.title, imageUrl: feed.iconUrl, size: 28)
/// ```
class FeedAvatar extends StatelessWidget {
  const FeedAvatar({
    super.key,
    this.title,
    this.feedId,
    this.imageUrl,
    this.size = 28,
    this.color,
    this.categoryColor,
    this.radius,
  });

  /// Used for the initials fallback.
  final String? title;

  /// Feed ID (for future lookups or accessibility).
  final String? feedId;

  /// Favicon / feed image. Null or empty renders the fallback immediately.
  final String? imageUrl;

  final double size;

  /// Category colour used to tint the fallback. Defaults to a neutral slate.
  final Color? color;

  /// Category colour (alias for [color]).
  final Color? categoryColor;

  /// Corner radius. Defaults to a squircle (size / 3).
  final double? radius;

  String get _initials {
    final String source = (title ?? feedId ?? '').trim();
    if (source.isEmpty) return '?';
    final List<String> words = source
        .split(RegExp(r'[\s\-_.]+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return source.substring(0, 1).toUpperCase();
    if (words.length == 1 || size < 24) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color tint = categoryColor ?? color ?? AppColors.neutral;
    final BorderRadius shape = BorderRadius.circular(radius ?? size / 3);

    final Widget fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: shape,
        border: Border.all(color: tint.withValues(alpha: 0.24)),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            height: 1,
            letterSpacing: 0,
            color: tint,
          ),
        ),
      ),
    );

    final String? url = imageUrl;
    final Widget content = (url == null || url.isEmpty)
        ? fallback
        : ClipRRect(
            borderRadius: shape,
            child: CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              fadeInDuration: AppTokens.motionFast,
              placeholder: (context, url) => DecoratedBox(
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: shape,
                ),
              ),
              errorWidget: (context, url, error) => fallback,
            ),
          );

    return SizedBox(width: size, height: size, child: content);
  }
}
