import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../theme/app_tokens.dart';
import '../../utils/text_utils.dart';
import '../ui/ui.dart';

/// Everything a row needs to draw one article, resolved once by the list.
///
/// The [article] is always the instance the list was handed on this build, so
/// `isRead` / `isSaved` / `isStarred` are never stale.
@immutable
class ArticleRowData {
  const ArticleRowData({
    required this.article,
    this.feedTitle,
    this.feedIconUrl,
    this.categoryColor,
    this.showImages = true,
  });

  final Article article;
  final String? feedTitle;
  final String? feedIconUrl;
  final Color? categoryColor;
  final bool showImages;

  /// True when this row should draw an image.
  bool get hasImage =>
      showImages && (article.imageUrl?.trim().isNotEmpty ?? false);

  String get sourceLabel {
    final String? title = feedTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    return hostOf(article.url) ?? 'Unknown source';
  }
}

/// A network image that fades in, shows a soft placeholder and *collapses*
/// (shrinks to nothing) when the URL is broken, so rows never keep dead space.
class ArticleThumbnail extends StatelessWidget {
  const ArticleThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.aspectRatio,
    this.radius,
  });

  final String url;
  final double? width;
  final double? height;
  final double? aspectRatio;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final BorderRadius shape = BorderRadius.circular(radius ?? t.radiusS);

    Widget image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      fadeInDuration: AppTokens.motionFast,
      placeholder: (BuildContext context, String _) =>
          ColoredBox(color: t.surface2, child: const SizedBox.expand()),
      // A broken image collapses rather than leaving a grey hole.
      errorWidget: (BuildContext context, String _, Object __) =>
          const SizedBox.shrink(),
    );

    if (aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio!, child: image);
    }

    return ClipRRect(borderRadius: shape, child: image);
  }
}

/// `[avatar] Feed name  ·  3h ago` - the line every style shares.
class ArticleMetaRow extends StatelessWidget {
  const ArticleMetaRow({super.key, required this.data, this.avatarSize = 18});

  final ArticleRowData data;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = text.labelSmall?.copyWith(
      color: t.textTertiary,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );

    return Row(
      children: <Widget>[
        FeedAvatar(
          title: data.sourceLabel,
          feedId: data.article.feedId,
          imageUrl: data.feedIconUrl,
          categoryColor: data.categoryColor,
          size: avatarSize,
        ),
        SizedBox(width: t.spaceS),
        Flexible(
          child: Text(
            data.sourceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: t.textSecondary),
          ),
        ),
        SizedBox(width: t.spaceS),
        Text('·', style: style),
        SizedBox(width: t.spaceS),
        Text(relativeTime(data.article.publishedDate), style: style),
      ],
    );
  }
}

/// Title style. Read articles step down in weight and colour.
TextStyle? articleTitleStyle(BuildContext context, {required bool isRead}) {
  final AppTokens t = context.tokens;
  return Theme.of(context).textTheme.titleMedium?.copyWith(
    height: 1.28,
    fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
    color: isRead ? t.textSecondary : t.textPrimary,
  );
}

TextStyle? articleExcerptStyle(BuildContext context, {required bool isRead}) {
  final AppTokens t = context.tokens;
  return Theme.of(context).textTheme.bodySmall?.copyWith(
    height: 1.4,
    color: isRead ? t.textTertiary : t.textSecondary,
  );
}

/// The star / save / share trio used by the card style.
class ArticleActionBar extends StatelessWidget {
  const ArticleActionBar({
    super.key,
    required this.article,
    required this.onStar,
    required this.onSave,
    required this.onShare,
  });

  final Article article;
  final VoidCallback onStar;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Row(
      children: <Widget>[
        if (!article.isRead)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
          ),
        const Spacer(),
        _ActionIcon(
          // Key by slot *and* state: a bare ValueKey<bool> collides with the
          // save icon's key below whenever isStarred == isSaved (the common
          // case), which throws "Duplicate keys found" in the shared Row.
          key: ValueKey<String>('star_${article.isStarred}'),
          icon: article.isStarred
              ? Icons.star_rounded
              : Icons.star_border_rounded,
          tooltip: article.isStarred ? 'Unstar' : 'Star',
          active: article.isStarred,
          onPressed: onStar,
        ),
        _ActionIcon(
          key: ValueKey<String>('save_${article.isSaved}'),
          icon: article.isSaved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          tooltip: article.isSaved ? 'Remove from saved' : 'Save',
          active: article.isSaved,
          onPressed: onSave,
        ),
        _ActionIcon(
          icon: Icons.ios_share_rounded,
          tooltip: 'Share',
          active: false,
          onPressed: onShare,
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      color: active ? t.accent : t.textTertiary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
