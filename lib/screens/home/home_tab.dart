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
import '../feeds/add_feed_sheet.dart';
import '../feeds/feed_management_screen.dart';
import '../reader/feed_digest_sheet.dart';
import '../search/search_screen.dart';

/// The first tab: everything from every feed, with quick filters.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  ArticleFilter _filter = ArticleFilter.all;

  /// null = every category.
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    // Watched: `ArticleProvider` mutates its lists in place, so the list must
    // be re-read (and re-filtered) on every build.
    final ArticleProvider articles = context.watch<ArticleProvider>();
    final FeedProvider feeds = context.watch<FeedProvider>();
    final SettingsProvider settings = context.watch<SettingsProvider>();

    final RefreshProgress? progress = articles.refreshProgress;
    final List<Article> visible = _applyFilters(articles.articles, feeds);

    return AppScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: 'FreeAd',
        showBack: false,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          _RefreshAction(
            spinning: progress != null,
            onPressed: progress != null ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onPressed: _showOverflow,
          ),
        ],
        bottom: progress == null
            ? null
            : _RefreshProgressBar(progress: progress),
      ),
      body: Column(
        children: <Widget>[
          _FilterRow(
            selected: _filter,
            articles: articles.articles,
            onChanged: (ArticleFilter f) => setState(() => _filter = f),
          ),
          _CategoryRow(
            selected: _categoryId,
            onChanged: (String? id) => setState(() => _categoryId = id),
          ),
          Divider(height: 1, color: t.hairline),
          Expanded(
            child: _buildBody(
              context,
              articles: articles,
              feeds: feeds,
              settings: settings,
              visible: visible,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildBody(
    BuildContext context, {
    required ArticleProvider articles,
    required FeedProvider feeds,
    required SettingsProvider settings,
    required List<Article> visible,
  }) {
    final AppTokens t = context.tokens;

    if (articles.isLoading && articles.articles.isEmpty) {
      return Skeleton.articleList(
        settings.articleListStyle,
        showImages: settings.showImages,
        padding: EdgeInsets.fromLTRB(t.spaceL, t.spaceL, t.spaceL, t.spaceL),
      );
    }

    if (feeds.feeds.isEmpty && !feeds.isLoading) {
      return EmptyState(
        icon: Icons.rss_feed_rounded,
        title: 'Add your first feed',
        message:
            'Subscribe to a site and its articles show up here, '
            'ad-free and offline.',
        primaryActionLabel: 'Add feed',
        primaryActionIcon: Icons.add_rounded,
        onPrimaryAction: () => showAddFeedSheet(context),
        secondaryActionLabel: 'Starter packs',
        onSecondaryAction: () => showAddFeedSheet(context, startOnPacks: true),
      );
    }

    return ArticleListWidget(
      articles: visible,
      showFilter: false,
      groupByDate: true,
      onRefresh: _refresh,
      emptyState: articles.articles.isEmpty
          ? EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No articles yet',
              message: 'Refresh to fetch the latest from your feeds.',
              primaryActionLabel: 'Refresh',
              primaryActionIcon: Icons.refresh_rounded,
              onPrimaryAction: _refresh,
            )
          : EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing here',
              message: 'No articles match the current filters.',
              primaryActionLabel: 'Clear filters',
              onPrimaryAction: () => setState(() {
                _filter = ArticleFilter.all;
                _categoryId = null;
              }),
            ),
    );
  }

  /// Applies the tab's own chips. The list widget re-resolves each article
  /// against the provider, so filtering here never freezes read/star state.
  List<Article> _applyFilters(List<Article> source, FeedProvider feeds) {
    final String? categoryId = _categoryId;
    return source.where((Article article) {
      if (!_filter.matches(article)) return false;
      if (categoryId == null) return true;
      final String? feedCategory = feeds
          .getFeedById(article.feedId)
          ?.categoryId;
      return (feedCategory ??
              article.categoryId ??
              FeedProvider.defaultCategoryId) ==
          categoryId;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _refresh() async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();

    final RefreshSummary summary = await articles.refreshAllArticles();
    await feeds.loadFeeds();
    await settings.setLastRefreshAt(DateTime.now());
    if (!mounted) return;

    if (summary.skipped) return;
    if (summary.hasFailures) {
      AppSnackBar.error(
        context,
        '${summary.failedFeeds} feed${summary.failedFeeds == 1 ? '' : 's'} '
        'failed - see the Feeds tab',
      );
      return;
    }
    AppSnackBar.success(
      context,
      summary.newArticles == 0
          ? 'You are up to date'
          : '${summary.newArticles} new '
                'article${summary.newArticles == 1 ? '' : 's'}',
    );
  }

  Future<void> _showOverflow() async {
    final String? choice = await showAppMenuSheet<String>(
      context,
      options: const <AppMenuOption<String>>[
        AppMenuOption<String>(
          value: 'read',
          label: 'Mark all as read',
          icon: Icons.done_all_rounded,
        ),
        AppMenuOption<String>(
          value: 'digest',
          label: 'Feed digest (AI)',
          icon: Icons.auto_awesome_outlined,
        ),
        AppMenuOption<String>(
          value: 'prefetch',
          label: 'Prefetch full articles',
          icon: Icons.download_for_offline_outlined,
        ),
        AppMenuOption<String>(
          value: 'manage',
          label: 'Manage feeds',
          icon: Icons.tune_rounded,
        ),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'read':
        await _markAllRead();
      case 'digest':
        await showFeedDigestSheet(context);
      case 'prefetch':
        await _prefetch();
      case 'manage':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FeedManagementScreen()),
        );
    }
  }

  Future<void> _markAllRead() async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    final int changed = await articles.markAllAsRead(categoryId: _categoryId);
    await feeds.loadFeeds();
    if (!mounted) return;
    AppSnackBar.success(
      context,
      changed == 0 ? 'Nothing left to mark' : 'Marked $changed as read',
    );
  }

  Future<void> _prefetch() async {
    AppSnackBar.show(context, 'Prefetching full articles...');
    final int done = await context
        .read<ArticleProvider>()
        .prefetchFullArticles();
    if (!mounted) return;
    AppSnackBar.success(
      context,
      done == 0
          ? 'Nothing to prefetch'
          : 'Cached $done article${done == 1 ? '' : 's'} for offline reading',
    );
  }
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

/// Refresh icon that spins while a refresh is running.
class _RefreshAction extends StatefulWidget {
  const _RefreshAction({required this.spinning, required this.onPressed});

  final bool spinning;
  final VoidCallback? onPressed;

  @override
  State<_RefreshAction> createState() => _RefreshActionState();
}

class _RefreshActionState extends State<_RefreshAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(_RefreshAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.spinning ? 'Refreshing' : 'Refresh',
      onPressed: widget.onPressed,
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}

/// The thin "Refreshing 3/12 - The Verge" strip under the app bar.
class _RefreshProgressBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _RefreshProgressBar({required this.progress});

  final RefreshProgress progress;

  @override
  Size get preferredSize => const Size.fromHeight(26);

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String feed = progress.currentFeedTitle ?? '';

    return SizedBox(
      height: 26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(t.spaceL, 0, t.spaceL, t.spaceXs),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Refreshing ${progress.done}/${progress.total}'
                    '${feed.isEmpty ? '' : ' - $feed'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: t.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress.total == 0 ? null : progress.fraction,
            minHeight: 2,
            color: t.accent,
            backgroundColor: t.surface2,
          ),
        ],
      ),
    );
  }
}

/// All / Unread / Starred / Saved.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selected,
    required this.articles,
    required this.onChanged,
  });

  final ArticleFilter selected;
  final List<Article> articles;
  final ValueChanged<ArticleFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: t.spaceL, vertical: t.spaceS),
        children: <Widget>[
          for (final ArticleFilter filter in ArticleFilter.values) ...<Widget>[
            PillChip(
              label: filter.label,
              selected: selected == filter,
              count: filter == ArticleFilter.unread
                  ? articles.where(filter.matches).length
                  : null,
              onTap: () => onChanged(filter),
            ),
            SizedBox(width: t.spaceS),
          ],
        ],
      ),
    );
  }
}

/// All + one chip per category that actually has feeds.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final Set<String> withFeeds = feeds.feedsByCategory.keys.toSet();
    final List<Category> categories = feeds.categories
        .where((Category c) => withFeeds.contains(c.id))
        .toList();

    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(t.spaceL, 0, t.spaceL, t.spaceS),
        children: <Widget>[
          PillChip(
            label: 'All',
            dense: true,
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          SizedBox(width: t.spaceS),
          for (final Category category in categories) ...<Widget>[
            PillChip(
              label: category.name,
              dense: true,
              dotColor: category.colorValue,
              selected: selected == category.id,
              count: feeds.unreadCountForCategory(category.id),
              onTap: () => onChanged(category.id),
            ),
            SizedBox(width: t.spaceS),
          ],
        ],
      ),
    );
  }
}
