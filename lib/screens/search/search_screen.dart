import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/article.dart';
import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/article/article_list.dart';
import '../../widgets/ui/ui.dart';

/// Recent queries, kept for the session only (no persistence by design).
final List<String> _recentSearches = <String>[];

/// Full-text search over titles, descriptions and cached full content.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<Article> _results = const <Article>[];
  bool _searching = false;
  bool _hasSearched = false;
  bool _unreadOnly = false;
  String? _feedId;

  @override
  void initState() {
    super.initState();
    final String? initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(initial));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Searching
  // ---------------------------------------------------------------------------

  void _onChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const <Article>[];
        _hasSearched = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() => _searching = true);

    final List<Article> found = await context
        .read<ArticleProvider>()
        .searchArticles(query);
    if (!mounted) return;

    _remember(query);
    setState(() {
      _results = found;
      _searching = false;
      _hasSearched = true;
    });
  }

  static void _remember(String query) {
    _recentSearches
      ..removeWhere((String q) => q.toLowerCase() == query.toLowerCase())
      ..insert(0, query);
    if (_recentSearches.length > 8) _recentSearches.removeLast();
  }

  List<Article> get _filtered => _results.where((Article article) {
    if (_unreadOnly && article.isRead) return false;
    if (_feedId != null && article.feedId != _feedId) return false;
    return true;
  }).toList();

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();

    return AppScaffold(
      appBar: GlassAppBar(
        titleWidget: TextField(
          controller: _controller,
          autofocus: widget.initialQuery == null,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (String value) {
            _debounce?.cancel();
            if (value.trim().isNotEmpty) _search(value.trim());
          },
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            hintText: 'Search articles',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
            isDense: true,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          _buildFilters(context, feeds),
          Divider(height: 1, color: t.hairline),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, FeedProvider feeds) {
    final AppTokens t = context.tokens;
    final RSSFeed? selectedFeed = _feedId == null
        ? null
        : feeds.getFeedById(_feedId!);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: t.spaceL, vertical: t.spaceS),
        children: <Widget>[
          PillChip(
            label: 'Unread only',
            icon: Icons.mark_email_unread_outlined,
            dense: true,
            selected: _unreadOnly,
            onTap: () => setState(() => _unreadOnly = !_unreadOnly),
          ),
          SizedBox(width: t.spaceS),
          PillChip(
            label: selectedFeed?.title ?? 'Any feed',
            icon: Icons.rss_feed_rounded,
            dense: true,
            selected: _feedId != null,
            enabled: feeds.feeds.isNotEmpty,
            onTap: () => _pickFeed(feeds),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFeed(FeedProvider feeds) async {
    final String? picked = await showAppMenuSheet<String>(
      context,
      title: 'Limit to feed',
      options: <AppMenuOption<String>>[
        const AppMenuOption<String>(
          value: '',
          label: 'Any feed',
          icon: Icons.all_inclusive_rounded,
        ),
        for (final RSSFeed feed in feeds.feeds)
          AppMenuOption<String>(
            value: feed.id,
            label: feed.title,
            icon: Icons.rss_feed_rounded,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _feedId = picked.isEmpty ? null : picked);
  }

  Widget _buildBody(BuildContext context) {
    final AppTokens t = context.tokens;

    if (_searching) {
      return Skeleton.articleList(
        ArticleListStyle.compact,
        showImages: false,
        padding: EdgeInsets.all(t.spaceL),
      );
    }

    if (!_hasSearched) {
      if (_recentSearches.isEmpty) {
        return const EmptyState(
          icon: Icons.search_rounded,
          title: 'Search your articles',
          message: 'Titles, summaries and cached full text.',
        );
      }
      return ListView(
        padding: EdgeInsets.all(t.spaceL),
        children: <Widget>[
          SectionHeader(
            label: 'Recent',
            actionLabel: 'Clear',
            onAction: () => setState(_recentSearches.clear),
            padding: EdgeInsets.only(bottom: t.spaceS),
          ),
          for (final String query in _recentSearches)
            ListTile(
              leading: Icon(Icons.history_rounded, color: t.textTertiary),
              title: Text(query),
              onTap: () {
                _controller.text = query;
                _search(query);
              },
            ),
        ],
      );
    }

    final List<Article> results = _filtered;
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Nothing found for "${_controller.text.trim()}".',
        primaryActionLabel: _unreadOnly || _feedId != null
            ? 'Clear filters'
            : null,
        onPrimaryAction: _unreadOnly || _feedId != null
            ? () => setState(() {
                _unreadOnly = false;
                _feedId = null;
              })
            : null,
      );
    }

    return ArticleListWidget(
      articles: results,
      title: 'Search',
      showFilter: false,
      style: ArticleListStyle.compact,
      padding: EdgeInsets.fromLTRB(
        t.spaceL,
        t.spaceS,
        t.spaceL,
        t.space3xl * 2,
      ),
    );
  }
}
