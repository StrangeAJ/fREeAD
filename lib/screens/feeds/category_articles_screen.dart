import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/category.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/article/article_list.dart';
import '../../widgets/ui/ui.dart';

/// Every article whose feed belongs to one category.
///
/// [categoryId] must be a real category id (`general`, `technology`, ...) -
/// v2 passed a *feed* id here, which is why this screen was always empty.
class CategoryArticlesScreen extends StatefulWidget {
  const CategoryArticlesScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  State<CategoryArticlesScreen> createState() => _CategoryArticlesScreenState();
}

class _CategoryArticlesScreenState extends State<CategoryArticlesScreen> {
  List<Article> _articles = const <Article>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final List<Article> loaded = await context
        .read<ArticleProvider>()
        .getArticlesByCategory(widget.categoryId);
    if (!mounted) return;
    setState(() {
      _articles = loaded;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final FeedProvider feeds = context.watch<FeedProvider>();
    final Category? category = feeds.getCategoryById(widget.categoryId);
    final int unread = feeds.unreadCountForCategory(widget.categoryId);

    return AppScaffold(
      appBar: GlassAppBar(
        titleWidget: Row(
          children: <Widget>[
            Icon(
              category?.icon ?? Icons.rss_feed_rounded,
              size: 20,
              color: category?.colorValue ?? t.accent,
            ),
            SizedBox(width: t.spaceM),
            Expanded(
              child: Text(
                category?.name ?? widget.categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (unread > 0) AppBadge(count: unread),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all read',
            onPressed: _markAllRead,
          ),
        ],
      ),
      body: _loading
          ? Skeleton.articleList(
              settings.articleListStyle,
              showImages: settings.showImages,
              padding: EdgeInsets.all(t.spaceL),
            )
          : ArticleListWidget(
              articles: _articles,
              title: category?.name ?? widget.categoryName,
              showFilter: true,
              onRefresh: _refresh,
              emptyState: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No articles',
                message:
                    'Nothing in ${category?.name ?? widget.categoryName} yet.',
                primaryActionLabel: 'Refresh',
                primaryActionIcon: Icons.refresh_rounded,
                onPrimaryAction: _refresh,
              ),
            ),
    );
  }

  Future<void> _refresh() async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    await articles.refreshAllArticles();
    await feeds.loadFeeds();
    await _load();
  }

  Future<void> _markAllRead() async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    final int changed = await articles.markAllAsRead(
      categoryId: widget.categoryId,
    );
    await feeds.loadFeeds();
    await _load();
    if (!mounted) return;
    AppSnackBar.success(
      context,
      changed == 0 ? 'Nothing left to mark' : 'Marked $changed as read',
    );
  }
}
