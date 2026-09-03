import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../theme/app_tokens.dart';
import '../ui/ui.dart';
import 'article_item_parts.dart';

/// The "List" style (the default): text on the left, a 72x72 thumbnail on the
/// right, one line of excerpt.
class ArticleListTile extends StatelessWidget {
  const ArticleListTile({
    super.key,
    required this.data,
    required this.onTap,
    required this.onLongPress,
  });

  final ArticleRowData data;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const double _thumbSize = 72;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Article article = data.article;
    final String excerpt = article.description.trim();

    return SurfaceCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: EdgeInsets.all(t.spaceM),
      margin: EdgeInsets.only(bottom: t.spaceS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  article.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: articleTitleStyle(context, isRead: article.isRead),
                ),
                if (excerpt.isNotEmpty) ...<Widget>[
                  SizedBox(height: t.spaceXs),
                  Text(
                    excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: articleExcerptStyle(context, isRead: article.isRead),
                  ),
                ],
                SizedBox(height: t.spaceS),
                Row(
                  children: <Widget>[
                    Expanded(child: ArticleMetaRow(data: data, avatarSize: 16)),
                    if (article.isStarred)
                      Padding(
                        padding: EdgeInsets.only(left: t.spaceXs),
                        child: Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: t.accent,
                        ),
                      ),
                    if (article.isSaved)
                      Padding(
                        padding: EdgeInsets.only(left: t.spaceXs),
                        child: Icon(
                          Icons.bookmark_rounded,
                          size: 14,
                          color: t.accent,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (data.hasImage) ...<Widget>[
            SizedBox(width: t.spaceM),
            Hero(
              tag: 'article-image-${article.id}',
              child: ArticleThumbnail(
                url: article.imageUrl!,
                width: _thumbSize,
                height: _thumbSize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
