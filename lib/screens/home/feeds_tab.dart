import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/category.dart';
import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../theme/app_tokens.dart';
import '../../utils/text_utils.dart';
import '../../widgets/ui/ui.dart';
import '../feeds/add_feed_sheet.dart';
import '../feeds/auto_categorize_screen.dart';
import '../feeds/category_manager_screen.dart';
import '../feeds/feed_articles_screen.dart';
import '../feeds/feed_management_screen.dart';
import '../feeds/opml_actions.dart';

/// Stand-in header for a category id that has feeds but no row in the database
/// (only reachable if a migration left an orphan).
Category _placeholderCategory(String id) =>
    Category(id: id, name: id, description: '', dateCreated: DateTime.now());

/// The second tab: subscriptions grouped by category.
class FeedsTab extends StatefulWidget {
  const FeedsTab({super.key});

  @override
  State<FeedsTab> createState() => _FeedsTabState();
}

class _FeedsTabState extends State<FeedsTab> {
  /// Categories the user collapsed this session.
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final Map<String, List<RSSFeed>> grouped = feeds.feedsByCategory;

    return AppScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: 'Feeds',
        showBack: false,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add feed',
            onPressed: () => showAddFeedSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Auto-categorize',
            onPressed: feeds.feeds.isEmpty
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AutoCategorizeScreen(),
                    ),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onPressed: _showOverflow,
          ),
        ],
      ),
      body: feeds.isLoading && feeds.feeds.isEmpty
          ? Center(child: CircularProgressIndicator(color: t.accent))
          : feeds.feeds.isEmpty
          ? EmptyState(
              icon: Icons.rss_feed_rounded,
              title: 'No subscriptions yet',
              message: 'Add a feed by URL, or start from a curated pack.',
              primaryActionLabel: 'Add feed',
              primaryActionIcon: Icons.add_rounded,
              onPrimaryAction: () => showAddFeedSheet(context),
              secondaryActionLabel: 'Starter packs',
              onSecondaryAction: () =>
                  showAddFeedSheet(context, startOnPacks: true),
            )
          : RefreshIndicator(
              onRefresh: () => context.read<FeedProvider>().loadFeeds(),
              color: t.accent,
              backgroundColor: t.surface2,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  t.spaceL,
                  t.spaceS,
                  t.spaceL,
                  t.space3xl * 3,
                ),
                children: <Widget>[
                  for (final MapEntry<String, List<RSSFeed>> entry
                      in grouped.entries)
                    _CategorySection(
                      category:
                          feeds.getCategoryById(entry.key) ??
                          _placeholderCategory(entry.key),
                      feeds: entry.value,
                      unreadFor: feeds.unreadCountFor,
                      collapsed: _collapsed.contains(entry.key),
                      onToggle: () => setState(() {
                        if (!_collapsed.remove(entry.key)) {
                          _collapsed.add(entry.key);
                        }
                      }),
                      onOpen: _openFeed,
                      onMenu: _showFeedMenu,
                    ),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _openFeed(RSSFeed feed) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FeedArticlesScreen(feedId: feed.id, feedTitle: feed.title),
      ),
    );
  }

  Future<void> _showOverflow() async {
    final String? choice = await showAppMenuSheet<String>(
      context,
      options: const <AppMenuOption<String>>[
        AppMenuOption<String>(
          value: 'manage',
          label: 'Manage feeds',
          icon: Icons.tune_rounded,
        ),
        AppMenuOption<String>(
          value: 'categories',
          label: 'Manage categories',
          icon: Icons.folder_outlined,
        ),
        AppMenuOption<String>(
          value: 'import',
          label: 'Import OPML',
          icon: Icons.file_download_outlined,
        ),
        AppMenuOption<String>(
          value: 'export',
          label: 'Export OPML',
          icon: Icons.file_upload_outlined,
        ),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'manage':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FeedManagementScreen()),
        );
      case 'categories':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CategoryManagerScreen(),
          ),
        );
      case 'import':
        await OpmlActions.import(context);
      case 'export':
        await OpmlActions.export(context);
    }
  }

  Future<void> _showFeedMenu(RSSFeed feed) async {
    final String? choice = await showAppMenuSheet<String>(
      context,
      title: feed.title,
      options: <AppMenuOption<String>>[
        const AppMenuOption<String>(
          value: 'refresh',
          label: 'Refresh',
          icon: Icons.refresh_rounded,
        ),
        const AppMenuOption<String>(
          value: 'read',
          label: 'Mark all read',
          icon: Icons.done_all_rounded,
        ),
        const AppMenuOption<String>(
          value: 'edit',
          label: 'Edit',
          icon: Icons.edit_outlined,
        ),
        AppMenuOption<String>(
          value: 'site',
          label: 'Open site',
          icon: Icons.open_in_new_rounded,
          enabled: (feed.siteUrl ?? '').isNotEmpty,
        ),
        const AppMenuOption<String>(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'refresh':
        await _refreshFeed(feed);
      case 'read':
        await _markFeedRead(feed);
      case 'edit':
        await showEditFeedSheet(context, feed);
      case 'site':
        final Uri? uri = Uri.tryParse(feed.siteUrl ?? '');
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      case 'delete':
        await _deleteFeed(feed);
    }
  }

  Future<void> _refreshFeed(RSSFeed feed) async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    AppSnackBar.show(context, 'Refreshing ${feed.title}...');
    final RefreshSummary summary = await articles.refreshFeed(feed.id);
    await feeds.loadFeeds();
    if (!mounted) return;
    AppSnackBar.success(
      context,
      summary.newArticles == 0
          ? 'No new articles'
          : '${summary.newArticles} new '
                'article${summary.newArticles == 1 ? '' : 's'}',
    );
  }

  Future<void> _markFeedRead(RSSFeed feed) async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    final int changed = await articles.markAllAsRead(feedId: feed.id);
    await feeds.loadFeeds();
    if (!mounted) return;
    AppSnackBar.success(
      context,
      changed == 0 ? 'Nothing left to mark' : 'Marked $changed as read',
    );
  }

  Future<void> _deleteFeed(RSSFeed feed) async {
    final bool confirmed = await showAppConfirm(
      context,
      'Delete ${feed.title}?',
      'Its articles, summaries, highlights and notes are removed too.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final FeedProvider feeds = context.read<FeedProvider>();
    final ArticleProvider articles = context.read<ArticleProvider>();
    final bool ok = await feeds.deleteFeed(feed.id);
    await articles.loadArticles();
    if (!mounted) return;
    if (ok) {
      AppSnackBar.success(context, 'Deleted ${feed.title}');
    } else {
      AppSnackBar.error(context, 'Could not delete ${feed.title}');
    }
  }
}

/// Rename a feed and move it to another category.
Future<void> showEditFeedSheet(BuildContext context, RSSFeed feed) async {
  final TextEditingController titleController = TextEditingController(
    text: feed.title,
  );
  String? categoryId = feed.categoryId;

  final bool? save = await showAppBottomSheet<bool>(
    context,
    title: 'Edit feed',
    builder: (BuildContext sheetContext) {
      final AppTokens t = sheetContext.tokens;
      final List<Category> categories = sheetContext
          .read<FeedProvider>()
          .categories;

      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: t.spaceM),
            DropdownButtonFormField<String>(
              value: categories.any((Category c) => c.id == categoryId)
                  ? categoryId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: <DropdownMenuItem<String>>[
                for (final Category category in categories)
                  DropdownMenuItem<String>(
                    value: category.id,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          category.icon,
                          size: 18,
                          color: category.colorValue,
                        ),
                        SizedBox(width: t.spaceS),
                        Flexible(
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (String? id) => setSheetState(() => categoryId = id),
            ),
            SizedBox(height: t.spaceL),
            GlowButton(
              label: 'Save',
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
    },
  );

  final String newTitle = titleController.text.trim();
  titleController.dispose();
  if (save != true || !context.mounted) return;

  final FeedProvider feeds = context.read<FeedProvider>();
  final bool ok = await feeds.updateFeed(
    feed.copyWith(
      title: newTitle.isEmpty ? feed.title : newTitle,
      categoryId: categoryId ?? feed.categoryId,
    ),
  );
  if (!context.mounted) return;
  if (ok) {
    AppSnackBar.success(context, 'Feed updated');
  } else {
    AppSnackBar.error(context, 'Could not update the feed');
  }
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.feeds,
    required this.unreadFor,
    required this.collapsed,
    required this.onToggle,
    required this.onOpen,
    required this.onMenu,
  });

  final Category category;
  final List<RSSFeed> feeds;
  final int Function(String feedId) unreadFor;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<RSSFeed> onOpen;
  final ValueChanged<RSSFeed> onMenu;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final int unread = feeds.fold<int>(
      0,
      (int sum, RSSFeed f) => sum + unreadFor(f.id),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: t.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: t.borderRadiusS,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: t.spaceXs,
                vertical: t.spaceS,
              ),
              child: Row(
                children: <Widget>[
                  Icon(category.icon, size: 18, color: category.colorValue),
                  SizedBox(width: t.spaceM),
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(color: t.textPrimary),
                    ),
                  ),
                  Text(
                    '${feeds.length}',
                    style: text.labelSmall?.copyWith(color: t.textTertiary),
                  ),
                  if (unread > 0) ...<Widget>[
                    SizedBox(width: t.spaceS),
                    AppBadge(count: unread),
                  ],
                  SizedBox(width: t.spaceXs),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: AppTokens.motionFast,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: t.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            for (final RSSFeed feed in feeds)
              _FeedRow(
                feed: feed,
                unread: unreadFor(feed.id),
                categoryColor: category.colorValue,
                onTap: () => onOpen(feed),
                onLongPress: () => onMenu(feed),
              ),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.feed,
    required this.unread,
    required this.categoryColor,
    required this.onTap,
    required this.onLongPress,
  });

  final RSSFeed feed;
  final int unread;
  final Color categoryColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final String? error = feed.lastError;
    final bool hasError = error != null && error.trim().isNotEmpty;

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.symmetric(horizontal: t.spaceM, vertical: t.spaceM),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: <Widget>[
          FeedAvatar(
            title: feed.title,
            feedId: feed.id,
            imageUrl: feed.iconUrl,
            categoryColor: categoryColor,
            size: 28,
          ),
          SizedBox(width: t.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  feed.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(color: t.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  hasError
                      ? error
                      : (hostOf(feed.siteUrl ?? feed.url) ?? feed.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: hasError ? t.danger : t.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (unread > 0) ...<Widget>[
            SizedBox(width: t.spaceS),
            AppBadge(count: unread),
          ],
          Icon(Icons.chevron_right_rounded, size: 20, color: t.textTertiary),
        ],
      ),
    );
  }
}
