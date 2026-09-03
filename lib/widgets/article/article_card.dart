import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../theme/app_tokens.dart';
import '../ui/ui.dart';
import 'article_item_parts.dart';

/// The "Card" list style: 16:9 image on top, meta, title, 2-line excerpt and an
/// action bar.
///
/// Stateless by design - every flag is read from [data] on each build, so a
/// star/save toggle in the provider shows up immediately.
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.data,
    required this.onTap,
    required this.onLongPress,
    required this.onStar,
    required this.onSave,
    required this.onShare,
  });

  final ArticleRowData data;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onStar;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Article article = data.article;
    final String excerpt = article.description.trim();

    return SurfaceCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.only(bottom: t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (data.hasImage)
            Hero(
              tag: 'article-image-${article.id}',
              child: ArticleThumbnail(
                url: article.imageUrl!,
                aspectRatio: 16 / 9,
                radius: 0,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.spaceL,
              t.spaceM,
              t.spaceL,
              t.spaceXs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ArticleMetaRow(data: data),
                SizedBox(height: t.spaceM),
                Text(
                  article.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: articleTitleStyle(context, isRead: article.isRead),
                ),
                if (excerpt.isNotEmpty) ...<Widget>[
                  SizedBox(height: t.spaceS),
                  Text(
                    excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: articleExcerptStyle(context, isRead: article.isRead),
                  ),
                ],
                SizedBox(height: t.spaceXs),
                ArticleActionBar(
                  article: article,
                  onStar: onStar,
                  onSave: onSave,
                  onShare: onShare,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
