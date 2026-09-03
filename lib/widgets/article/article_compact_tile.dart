import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../theme/app_tokens.dart';
import '../../utils/text_utils.dart';
import 'article_item_parts.dart';

/// The "Compact" style: unread dot, one line of title, feed + time underneath.
/// No images, no card - the densest way to scan a lot of headlines.
class ArticleCompactTile extends StatelessWidget {
  const ArticleCompactTile({
    super.key,
    required this.data,
    required this.onTap,
    required this.onLongPress,
  });

  final ArticleRowData data;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final Article article = data.article;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: t.borderRadiusS,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.spaceS, vertical: t.spaceM),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(top: t.spaceXs + 2, right: t.spaceM),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: article.isRead ? Colors.transparent : t.accent,
                  shape: BoxShape.circle,
                  border: article.isRead
                      ? Border.all(color: t.hairlineStrong)
                      : null,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: article.isRead
                          ? FontWeight.w500
                          : FontWeight.w600,
                      color: article.isRead ? t.textSecondary : t.textPrimary,
                    ),
                  ),
                  SizedBox(height: t.spaceXs),
                  Text(
                    '${data.sourceLabel} · '
                    '${relativeTime(article.publishedDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: t.textTertiary,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            if (article.isStarred)
              Padding(
                padding: EdgeInsets.only(left: t.spaceS),
                child: Icon(Icons.star_rounded, size: 15, color: t.accent),
              ),
            if (article.isSaved)
              Padding(
                padding: EdgeInsets.only(left: t.spaceXs),
                child: Icon(Icons.bookmark_rounded, size: 15, color: t.accent),
              ),
          ],
        ),
      ),
    );
  }
}
