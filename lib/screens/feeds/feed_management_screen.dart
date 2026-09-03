import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../theme/app_tokens.dart';
import '../../utils/text_utils.dart';
import '../../widgets/ui/ui.dart';
import '../home/feeds_tab.dart' show showEditFeedSheet;
import 'add_feed_sheet.dart';
import 'opml_actions.dart';

/// Bulk feed maintenance: search, filter by category, multi-select, then
/// change category / mark read / delete in one go.
class FeedManagementScreen extends StatefulWidget {
  const FeedManagementScreen({super.key});

  @override
  State<FeedManagementScreen> createState() => _FeedManagementScreenState();
}

class _FeedManagementScreenState extends State<FeedManagementScreen> {
  final TextEditingController _search = TextEditingController();

  String _query = '';
  String? _categoryFilter;
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FeedProvider>().loadFeeds();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final List<RSSFeed> visible = _visibleFeeds(feeds);

    return AppScaffold(
      appBar: GlassAppBar(
        title: _selectionMode ? '${_selected.length} selected' : 'Manage Feeds',
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cancel selection',
                onPressed: _exitSelection,
              )
            : null,
        actions: _selectionMode
            ? <Widget>[
                IconButton(
                  icon: const Icon(Icons.select_all_rounded),
                  tooltip: 'Select all',
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(visible.map((RSSFeed f) => f.id));
                  }),
                ),
              ]
            : <Widget>[
                IconButton(
                  icon: const Icon(Icons.checklist_rounded),
                  tooltip: 'Select feeds',
                  onPressed: feeds.feeds.isEmpty
                      ? null
                      : () => setState(() => _selectionMode = true),
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: 'Import OPML',
                  onPressed: () => OpmlActions.import(context),
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'Export OPML',
                  onPressed: () => OpmlActions.export(context),
                ),
              ],
      ),
      bottomBar: _selectionMode ? _buildBulkBar(context) : null,
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.spaceL,
              t.spaceS,
              t.spaceL,
              t.spaceS,
            ),
            child: TextField(
              controller: _search,
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search feeds',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
          _buildCategoryFilter(context, feeds),
          Expanded(
            child: feeds.isLoading && feeds.feeds.isEmpty
                ? Center(child: CircularProgressIndicator(color: t.accent))
                : feeds.feeds.isEmpty
                ? EmptyState(
                    icon: Icons.rss_feed_rounded,
                    title: 'No feeds to manage',
                    message: 'Subscribe to something first.',
                    primaryActionLabel: 'Add feed',
                    primaryActionIcon: Icons.add_rounded,
                    onPrimaryAction: () => showAddFeedSheet(context),
                  )
                : visible.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message: 'Try a different search or category.',
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      t.spaceL,
                      t.spaceS,
                      t.spaceL,
                      t.space3xl * 3,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (BuildContext context, int index) {
                      final RSSFeed feed = visible[index];
                      return _ManageRow(
                        key: ValueKey<String>('manage-${feed.id}'),
                        feed: feed,
                        category: feeds.getCategoryById(feed.categoryId),
                        unread: feeds.unreadCountFor(feed.id),
                        selectionMode: _selectionMode,
                        selected: _selected.contains(feed.id),
                        onTap: () => _selectionMode
                            ? _toggleSelected(feed.id)
                            : showEditFeedSheet(context, feed),
                        onLongPress: () {
                          setState(() => _selectionMode = true);
                          _toggleSelected(feed.id);
                        },
                        onDelete: () => _deleteOne(feed),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(BuildContext context, FeedProvider feeds) {
    final AppTokens t = context.tokens;
    if (feeds.categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(t.spaceL, 0, t.spaceL, t.spaceS),
        children: <Widget>[
          PillChip(
            label: 'All',
            dense: true,
            selected: _categoryFilter == null,
            onTap: () => setState(() => _categoryFilter = null),
          ),
          SizedBox(width: t.spaceS),
          for (final Category category in feeds.categories) ...<Widget>[
            PillChip(
              label: category.name,
              dense: true,
              dotColor: category.colorValue,
              selected: _categoryFilter == category.id,
              onTap: () => setState(() => _categoryFilter = category.id),
            ),
            SizedBox(width: t.spaceS),
          ],
        ],
      ),
    );
  }

  Widget _buildBulkBar(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool enabled = _selected.isNotEmpty && !_busy;

    return GlassBottomBar(
      opaque: true,
      padding: EdgeInsets.symmetric(horizontal: t.spaceM, vertical: t.spaceS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _BulkAction(
            icon: Icons.folder_outlined,
            label: 'Category',
            onPressed: enabled ? _bulkChangeCategory : null,
          ),
          _BulkAction(
            icon: Icons.done_all_rounded,
            label: 'Mark read',
            onPressed: enabled ? _bulkMarkRead : null,
          ),
          _BulkAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            destructive: true,
            onPressed: enabled ? _bulkDelete : null,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filtering / selection
  // ---------------------------------------------------------------------------

  List<RSSFeed> _visibleFeeds(FeedProvider feeds) {
    final String query = _query.trim().toLowerCase();
    return feeds.feeds.where((RSSFeed feed) {
      if (_categoryFilter != null &&
          (feed.categoryId ?? FeedProvider.defaultCategoryId) !=
              _categoryFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return feed.title.toLowerCase().contains(query) ||
          feed.url.toLowerCase().contains(query);
    }).toList();
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Bulk actions
  // ---------------------------------------------------------------------------

  Future<void> _bulkChangeCategory() async {
    final List<Category> categories = context.read<FeedProvider>().categories;
    final String? categoryId = await showAppMenuSheet<String>(
      context,
      title: 'Move to category',
      options: <AppMenuOption<String>>[
        for (final Category category in categories)
          AppMenuOption<String>(
            value: category.id,
            label: category.name,
            icon: category.icon,
          ),
      ],
    );
    if (categoryId == null || !mounted) return;

    setState(() => _busy = true);
    final Map<String, int> result = await context
        .read<FeedProvider>()
        .updateFeedsCategory(_selected.toList(), categoryId);
    if (!mounted) return;
    setState(() => _busy = false);
    _exitSelection();
    AppSnackBar.success(context, 'Moved ${result['success'] ?? 0} feed(s)');
  }

  Future<void> _bulkMarkRead() async {
    final ArticleProvider articles = context.read<ArticleProvider>();
    final FeedProvider feeds = context.read<FeedProvider>();
    setState(() => _busy = true);
    var changed = 0;
    for (final String id in _selected) {
      changed += await articles.markAllAsRead(feedId: id);
    }
    await feeds.loadFeeds();
    if (!mounted) return;
    setState(() => _busy = false);
    _exitSelection();
    AppSnackBar.success(context, 'Marked $changed article(s) as read');
  }

  Future<void> _bulkDelete() async {
    final int count = _selected.length;
    final bool confirmed = await showAppConfirm(
      context,
      'Delete $count feed${count == 1 ? '' : 's'}?',
      'Their articles, summaries, highlights and notes are removed too.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final FeedProvider feeds = context.read<FeedProvider>();
    final ArticleProvider articles = context.read<ArticleProvider>();
    final Map<String, int> result = await feeds.deleteFeeds(_selected.toList());
    await articles.loadArticles();
    if (!mounted) return;
    setState(() => _busy = false);
    _exitSelection();

    final int failed = result['failed'] ?? 0;
    if (failed > 0) {
      AppSnackBar.error(
        context,
        'Deleted ${result['success'] ?? 0}, $failed failed',
      );
    } else {
      AppSnackBar.success(context, 'Deleted ${result['success'] ?? 0} feed(s)');
    }
  }

  Future<void> _deleteOne(RSSFeed feed) async {
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

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    super.key,
    required this.feed,
    required this.category,
    required this.unread,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final RSSFeed feed;
  final Category? category;
  final int unread;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.symmetric(horizontal: t.spaceM, vertical: t.spaceS),
      borderColor: selected ? t.accent : null,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: <Widget>[
          if (selectionMode)
            Padding(
              padding: EdgeInsets.only(right: t.spaceXs),
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? t.accent : t.textTertiary,
              ),
            )
          else
            Padding(
              padding: EdgeInsets.only(right: t.spaceM),
              child: FeedAvatar(
                title: feed.title,
                feedId: feed.id,
                imageUrl: feed.iconUrl,
                categoryColor: category?.colorValue,
                size: 28,
              ),
            ),
          if (selectionMode) SizedBox(width: t.spaceM),
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
                Text(
                  '${category?.name ?? 'General'} · '
                  '${hostOf(feed.siteUrl ?? feed.url) ?? feed.url}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
          if (unread > 0 && !selectionMode) ...<Widget>[
            AppBadge(count: unread),
            SizedBox(width: t.spaceXs),
          ],
          if (!selectionMode)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              tooltip: 'Delete',
              color: t.textTertiary,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _BulkAction extends StatelessWidget {
  const _BulkAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = onPressed == null
        ? t.textTertiary
        : (destructive ? t.danger : t.accent);

    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color),
      label: Text(label, style: TextStyle(color: color)),
    );
  }
}
