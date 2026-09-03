import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_tokens.dart';
import '../../utils/text_utils.dart';
import '../../widgets/article/article_list.dart';
import '../../widgets/ui/ui.dart';
import '../home/feeds_tab.dart' show showEditFeedSheet;

/// Every article from one feed.
class FeedArticlesScreen extends StatefulWidget {
  const FeedArticlesScreen({
    super.key,
    required this.feedId,
    required this.feedTitle,
  });

  final String feedId;
  final String feedTitle;

  @override
  State<FeedArticlesScreen> createState() => _FeedArticlesScreenState();
}

class _FeedArticlesScreenState extends State<FeedArticlesScreen> {
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
        .getArticlesByFeed(widget.feedId);
    if (!mounted) return;
    setState(() {
      _articles = loaded;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final RSSFeed? feed = feeds.getFeedById(widget.feedId);
    final int unread = feeds.unreadCountFor(widget.feedId);

    return AppScaffold(
      appBar: GlassAppBar(
        titleWidget: Row(
          children: <Widget>[
            FeedAvatar(
              title: feed?.title ?? widget.feedTitle,
              feedId: widget.feedId,
              imageUrl: feed?.iconUrl,
              size: 28,
            ),
            SizedBox(width: t.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    feed?.title ?? widget.feedTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    unread > 0
                        ? '$unread unread'
                        : (hostOf(feed?.siteUrl ?? feed?.url) ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: t.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all read',
            onPressed: _markAllRead,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onPressed: () => _showMenu(feed),
          ),
        ],
      ),
      body: _loading
          ? Skeleton.articleList(
              context.watch<SettingsProvider>().articleListStyle,
              showImages: context.watch<SettingsProvider>().showImages,
              padding: EdgeInsets.all(t.spaceL),
            )
          : ArticleListWidget(
              articles: _articles,
              title: feed?.title ?? widget.feedTitle,
              showFilter: true,
              onRefresh: _refresh,
              emptyState: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No articles',
                message: 'Refresh to fetch the latest from this feed.',
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
    await articles.refreshFeed(widget.feedId);
    await feeds.loadFeeds();
    await _load();
  }

  Future<void> _markAllRead() async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    final int changed = await articles.markAllAsRead(feedId: widget.feedId);
    await feeds.loadFeeds();
    await _load();
    if (!mounted) return;
    AppSnackBar.success(
      context,
      changed == 0 ? 'Nothing left to mark' : 'Marked $changed as read',
    );
  }

  Future<void> _showMenu(RSSFeed? feed) async {
    if (feed == null) return;
    final String? choice = await showAppMenuSheet<String>(
      context,
      title: feed.title,
      options: const <AppMenuOption<String>>[
        AppMenuOption<String>(
          value: 'refresh',
          label: 'Refresh feed',
          icon: Icons.refresh_rounded,
        ),
        AppMenuOption<String>(
          value: 'edit',
          label: 'Feed settings',
          icon: Icons.tune_rounded,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'refresh') {
      await _refresh();
    } else {
      await showEditFeedSheet(context, feed);
      await _load();
    }
  }
}
