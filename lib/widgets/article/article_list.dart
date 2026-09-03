import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/article.dart';
import '../../models/category.dart';
import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_tokens.dart';
import '../../utils/text_utils.dart';
import '../ui/ui.dart';
import 'article_actions.dart';
import 'article_card.dart';
import 'article_compact_tile.dart';
import 'article_item_parts.dart';
import 'article_list_tile.dart';

/// Built-in filters offered by the (optional) filter bar.
enum ArticleFilter { all, unread, starred, saved }

extension ArticleFilterX on ArticleFilter {
  String get label => switch (this) {
    ArticleFilter.all => 'All',
    ArticleFilter.unread => 'Unread',
    ArticleFilter.starred => 'Starred',
    ArticleFilter.saved => 'Saved',
  };

  bool matches(Article article) => switch (this) {
    ArticleFilter.all => true,
    ArticleFilter.unread => !article.isRead,
    ArticleFilter.starred => article.isStarred,
    ArticleFilter.saved => article.isSaved,
  };
}

/// Sort orders offered by the filter bar's sort button.
enum ArticleSort { newest, oldest, title }

extension ArticleSortX on ArticleSort {
  String get label => switch (this) {
    ArticleSort.newest => 'Newest first',
    ArticleSort.oldest => 'Oldest first',
    ArticleSort.title => 'Title (A-Z)',
  };
}

/// The one article list in the app. Renders [ArticleListStyle.card],
/// `.list` or `.compact` rows with swipe actions, an optional filter bar and
/// optional date group headers.
///
/// ## Why there is no cached filtered list
///
/// `ArticleProvider._replaceInLists` updates its lists **in place**
/// (`list[index] = article`), so the `List` object identity never changes when
/// an article is starred, saved or read. Any `didUpdateWidget` check of the
/// form `oldWidget.articles != widget.articles` is therefore permanently false,
/// and a cached filtered copy goes stale forever - that was the "starring is
/// flaky" bug in v2.
///
/// This widget instead derives everything inside [build]: the visible rows are
/// recomputed from `widget.articles` on every frame, each row is keyed by
/// `article.id`, and every row reads `isStarred` / `isSaved` / `isRead` off the
/// instance it was handed. Filtering a few hundred articles per build costs
/// nothing next to laying the rows out.
///
/// The parent must pass `articles` straight from
/// `context.watch<ArticleProvider>()` (never a field cached in its own state)
/// - this widget also re-resolves each article against the provider by id, so
/// lists loaded from a one-shot `Future` stay live too.
class ArticleListWidget extends StatefulWidget {
  const ArticleListWidget({
    super.key,
    required this.articles,
    this.title,
    this.showFilter = true,
    this.style,
    this.groupByDate = false,
    this.padding,
    this.header,
    this.emptyState,
    this.onRefresh,
    this.scrollController,
    this.shrinkWrap = false,
    this.physics,
    this.resolveAgainstProvider = true,
  });

  /// The articles to show, newest-first by convention.
  final List<Article> articles;

  /// Kept for API compatibility with v2; used in empty-state copy.
  final String? title;

  /// Shows the All / Unread / Starred / Saved chips plus a sort button.
  final bool showFilter;

  /// Defaults to `SettingsProvider.articleListStyle`.
  final ArticleListStyle? style;

  /// Inserts Today / Yesterday / This week / Earlier headers.
  final bool groupByDate;

  final EdgeInsetsGeometry? padding;

  /// Pinned above the rows, inside the scroll view.
  final Widget? header;

  /// Shown instead of the rows when nothing matches.
  final Widget? emptyState;

  /// Enables pull-to-refresh.
  final Future<void> Function()? onRefresh;

  final ScrollController? scrollController;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Re-reads each article from [ArticleProvider] by id so rows stay live even
  /// when [articles] came from a one-shot database query. Turn off only for
  /// lists that must not be affected by provider state (tests, previews).
  final bool resolveAgainstProvider;

  @override
  State<ArticleListWidget> createState() => _ArticleListWidgetState();
}

/// One row in the flattened list: either a date header or an article.
@immutable
class _Entry {
  const _Entry.header(this.header) : article = null;
  const _Entry.article(this.article) : header = null;

  final String? header;
  final Article? article;

  bool get isHeader => header != null;
}

class _ArticleListWidgetState extends State<ArticleListWidget> {
  // Only *view* state lives here. The visible rows are never cached.
  ArticleFilter _filter = ArticleFilter.all;
  ArticleSort _sort = ArticleSort.newest;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final FeedProvider feeds = context.watch<FeedProvider>();
    // Watched so an in-place star/save/read change repaints this list.
    final ArticleProvider articleProvider = context.watch<ArticleProvider>();

    final ArticleListStyle style = widget.style ?? settings.articleListStyle;
    final bool showImages = settings.showImages;

    final List<Article> visible = _visibleArticles(articleProvider);
    final List<_Entry> entries = _entriesFor(visible);

    final Widget list = visible.isEmpty
        ? _buildEmpty(context)
        : _buildRows(
            context,
            entries: entries,
            ordered: visible,
            style: style,
            showImages: showImages,
            feeds: feeds,
            tokens: t,
          );

    final Widget body = Column(
      children: <Widget>[
        if (widget.showFilter) _buildFilterBar(context, articleProvider),
        Expanded(child: list),
      ],
    );

    if (widget.onRefresh == null) return body;
    return RefreshIndicator(
      onRefresh: widget.onRefresh!,
      color: t.accent,
      backgroundColor: t.surface2,
      child: body,
    );
  }

  // ---------------------------------------------------------------------------
  // Derivation - runs on every build, deliberately
  // ---------------------------------------------------------------------------

  /// Resolves, filters and sorts [ArticleListWidget.articles]. Never cached.
  List<Article> _visibleArticles(ArticleProvider provider) {
    // Resolving by id keeps rows live for lists that came from a Future.
    Map<String, Article>? byId;
    if (widget.resolveAgainstProvider) {
      byId = <String, Article>{
        for (final Article a in provider.articles) a.id: a,
      };
    }

    final List<Article> result = <Article>[];
    for (final Article passed in widget.articles) {
      final Article article = byId?[passed.id] ?? passed;
      if (_filter.matches(article)) result.add(article);
    }

    switch (_sort) {
      case ArticleSort.newest:
        result.sort(
          (Article a, Article b) => b.publishedDate.compareTo(a.publishedDate),
        );
      case ArticleSort.oldest:
        result.sort(
          (Article a, Article b) => a.publishedDate.compareTo(b.publishedDate),
        );
      case ArticleSort.title:
        result.sort(
          (Article a, Article b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return result;
  }

  List<_Entry> _entriesFor(List<Article> articles) {
    if (!widget.groupByDate) {
      return <_Entry>[for (final Article a in articles) _Entry.article(a)];
    }
    final List<_Entry> entries = <_Entry>[];
    String? currentGroup;
    for (final Article article in articles) {
      final String group = dateGroupLabel(article.publishedDate);
      if (group != currentGroup) {
        entries.add(_Entry.header(group));
        currentGroup = group;
      }
      entries.add(_Entry.article(article));
    }
    return entries;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  Widget _buildRows(
    BuildContext context, {
    required List<_Entry> entries,
    required List<Article> ordered,
    required ArticleListStyle style,
    required bool showImages,
    required FeedProvider feeds,
    required AppTokens tokens,
  }) {
    final int headerCount = widget.header == null ? 0 : 1;

    return ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      physics:
          widget.physics ??
          (widget.onRefresh == null
              ? null
              : const AlwaysScrollableScrollPhysics()),
      padding:
          widget.padding ??
          EdgeInsets.fromLTRB(
            tokens.spaceL,
            tokens.spaceS,
            tokens.spaceL,
            tokens.space3xl * 3,
          ),
      itemCount: entries.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (headerCount == 1 && index == 0) return widget.header!;
        final _Entry entry = entries[index - headerCount];

        if (entry.isHeader) {
          return SectionHeader(
            label: entry.header!,
            padding: EdgeInsets.fromLTRB(0, tokens.spaceL, 0, tokens.spaceS),
          );
        }

        final Article article = entry.article!;
        final RSSFeed? feed = feeds.getFeedById(article.feedId);
        final Category? category = feeds.getCategoryById(
          feed?.categoryId ?? article.categoryId,
        );

        final ArticleRowData data = ArticleRowData(
          article: article,
          feedTitle: feed?.title,
          feedIconUrl: feed?.iconUrl,
          categoryColor: category?.colorValue,
          showImages: showImages,
        );

        return _SwipeableRow(
          // Keyed by id: the element survives filter/sort changes and always
          // rebuilds from the article instance handed in on this build.
          key: ValueKey<String>('article-${article.id}'),
          article: article,
          child: _buildRow(context, data, style, ordered),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    ArticleRowData data,
    ArticleListStyle style,
    List<Article> ordered,
  ) {
    final Article article = data.article;
    void open() => ArticleActions.open(context, article);
    void menu() => ArticleActions.showMenu(context, article, ordered: ordered);

    switch (style) {
      case ArticleListStyle.card:
        return ArticleCard(
          data: data,
          onTap: open,
          onLongPress: menu,
          onStar: () => ArticleActions.toggleStar(context, article),
          onSave: () => ArticleActions.toggleSaved(context, article),
          onShare: () => ArticleActions.share(context, article),
        );
      case ArticleListStyle.list:
        return ArticleListTile(data: data, onTap: open, onLongPress: menu);
      case ArticleListStyle.compact:
        return ArticleCompactTile(data: data, onTap: open, onLongPress: menu);
    }
  }

  Widget _buildEmpty(BuildContext context) {
    if (widget.emptyState != null) return widget.emptyState!;

    final bool filtered = _filter != ArticleFilter.all;
    return EmptyState(
      icon: filtered ? Icons.filter_alt_off_outlined : Icons.article_outlined,
      title: filtered ? 'Nothing here' : 'No articles yet',
      message: filtered
          ? 'No ${_filter.label.toLowerCase()} articles'
                '${widget.title == null ? '' : ' in ${widget.title}'}.'
          : 'Pull down to refresh, or add a feed to get started.',
      primaryActionLabel: filtered ? 'Show all' : null,
      onPrimaryAction: filtered
          ? () => setState(() => _filter = ArticleFilter.all)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Filter bar
  // ---------------------------------------------------------------------------

  Widget _buildFilterBar(BuildContext context, ArticleProvider provider) {
    final AppTokens t = context.tokens;

    int countFor(ArticleFilter filter) => filter == ArticleFilter.all
        ? widget.articles.length
        : widget.articles.where(filter.matches).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, t.spaceS, t.spaceS, t.spaceS),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: t.spaceL),
              child: Row(
                children: <Widget>[
                  for (final ArticleFilter filter in ArticleFilter.values) ...[
                    PillChip(
                      label: filter.label,
                      selected: _filter == filter,
                      count: filter == ArticleFilter.unread
                          ? countFor(filter)
                          : null,
                      onTap: () => setState(() => _filter = filter),
                    ),
                    SizedBox(width: t.spaceS),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_vert_rounded),
            tooltip: 'Sort',
            color: t.textSecondary,
            onPressed: _showSortSheet,
          ),
        ],
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final ArticleSort? picked = await showAppMenuSheet<ArticleSort>(
      context,
      title: 'Sort by',
      options: <AppMenuOption<ArticleSort>>[
        for (final ArticleSort sort in ArticleSort.values)
          AppMenuOption<ArticleSort>(
            value: sort,
            label: sort.label,
            icon: sort == _sort ? Icons.check_rounded : null,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }
}

/// Wraps a row in swipe actions: right toggles read, left toggles saved.
///
/// `confirmDismiss` always returns false so the row springs back instead of
/// disappearing - the list is the source of truth, not the gesture.
class _SwipeableRow extends StatelessWidget {
  const _SwipeableRow({super.key, required this.article, required this.child});

  final Article article;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Dismissible(
      key: ValueKey<String>('swipe-${article.id}'),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: t.accentSoft,
        iconColor: t.accent,
        icon: article.isRead
            ? Icons.mark_email_unread_outlined
            : Icons.mark_email_read_outlined,
        label: article.isRead ? 'Unread' : 'Read',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: t.accentSoft,
        iconColor: t.accent,
        icon: article.isSaved
            ? Icons.bookmark_remove_outlined
            : Icons.bookmark_add_outlined,
        label: article.isSaved ? 'Unsave' : 'Save',
      ),
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      confirmDismiss: (DismissDirection direction) async {
        if (direction == DismissDirection.startToEnd) {
          await ArticleActions.toggleRead(context, article);
        } else {
          if (context.mounted) ArticleActions.toggleSaved(context, article);
        }
        // Never actually remove the row.
        return false;
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final Color iconColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      alignment: alignment,
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.symmetric(horizontal: t.spaceXl),
      decoration: BoxDecoration(color: color, borderRadius: t.borderRadiusM),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: iconColor, size: 20),
          SizedBox(width: t.spaceS),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: iconColor),
          ),
        ],
      ),
    );
  }
}
