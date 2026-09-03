import 'package:flutter/foundation.dart' hide Category;

import '../models/category.dart';
import '../models/rss_feed.dart';
import '../services/ai/categorization_service.dart';
import '../services/database_service.dart';
import '../services/rss/feed_discovery_service.dart';
import '../services/rss/rss_service.dart';
import '../utils/app_logger.dart';
import '../utils/text_utils.dart';

/// Outcome of [FeedProvider.addFeed] / [FeedProvider.addDiscoveredFeed].
///
/// Exactly one situation is true at a time:
/// * [isSuccess] - the feed was subscribed to, see [feed] and [newArticleCount];
/// * [isDuplicate] - the feed already existed, [feed] is the existing row;
/// * [needsSelection] - discovery found several feeds, ask the user which one
///   (see [candidates]) and call [FeedProvider.addDiscoveredFeed];
/// * [hasError] - nothing was added, show [error].
class AddFeedResult {
  const AddFeedResult({
    this.feed,
    this.newArticleCount = 0,
    this.candidates,
    this.error,
    this.isDuplicate = false,
  });

  /// The feed that was added, or the existing one when [isDuplicate].
  final RSSFeed? feed;

  /// Articles stored for the new feed (rows that did not exist before).
  final int newArticleCount;

  /// Feeds discovered behind the input when the user has to choose.
  final List<DiscoveredFeed>? candidates;

  /// User-facing failure message, null when the call worked.
  final String? error;

  /// True when the URL was already subscribed to.
  final bool isDuplicate;

  /// The feed was subscribed to just now.
  bool get isSuccess => feed != null && !isDuplicate && error == null;

  /// The caller must ask the user to pick one of [candidates].
  bool get needsSelection =>
      feed == null && candidates != null && candidates!.isNotEmpty;

  /// Nothing was added and [error] explains why.
  bool get hasError => error != null;

  factory AddFeedResult.success(RSSFeed feed, int newArticleCount) =>
      AddFeedResult(feed: feed, newArticleCount: newArticleCount);

  factory AddFeedResult.duplicate(RSSFeed feed) => AddFeedResult(
    feed: feed,
    isDuplicate: true,
    error: 'You are already subscribed to ${feed.title}.',
  );

  /// Several (or no) feeds were found behind the input.
  ///
  /// An empty [candidates] list means discovery came up empty; the result then
  /// carries an [error] instead and [needsSelection] is false.
  factory AddFeedResult.needsSelection(List<DiscoveredFeed> candidates) =>
      AddFeedResult(
        candidates: List<DiscoveredFeed>.unmodifiable(candidates),
        error: candidates.isEmpty
            ? 'No feed found at that address. Try the feed URL itself.'
            : null,
      );

  factory AddFeedResult.failure(String error) => AddFeedResult(error: error);

  @override
  String toString() {
    if (isSuccess) return 'AddFeedResult(${feed!.title}, +$newArticleCount)';
    if (isDuplicate) return 'AddFeedResult(duplicate: ${feed?.title})';
    if (needsSelection) {
      return 'AddFeedResult(${candidates!.length} candidates)';
    }
    return 'AddFeedResult(error: $error)';
  }
}

/// Owns subscriptions, categories and unread counts.
class FeedProvider with ChangeNotifier {
  FeedProvider({
    DatabaseService? database,
    RssService? rssService,
    FeedDiscoveryService? discovery,
  }) : _databaseService = database ?? DatabaseService(),
       _rssService = rssService ?? RssService(),
       _discovery = discovery ?? FeedDiscoveryService();

  final DatabaseService _databaseService;
  final RssService _rssService;
  final FeedDiscoveryService _discovery;

  /// Category every orphaned feed falls back to. Cannot be deleted.
  static const String defaultCategoryId = 'general';

  List<RSSFeed> _feeds = <RSSFeed>[];
  List<Category> _categories = <Category>[];
  Map<String, int> _unreadByFeed = <String, int>{};
  Map<String, int> _unreadByCategory = <String, int>{};

  bool _isLoading = false;
  bool _disposed = false;
  String? _error;

  /// All subscriptions, ordered by title.
  List<RSSFeed> get feeds => _feeds;

  /// All categories, ordered by `sortOrder` then name.
  List<Category> get categories => _categories;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Unread articles for one feed.
  int unreadCountFor(String feedId) => _unreadByFeed[feedId] ?? 0;

  /// Unread articles across every feed in [categoryId].
  ///
  /// Summed from the per-feed counts so the number always agrees with the feed
  /// rows on screen, even right after a feed was moved between categories.
  int unreadCountForCategory(String categoryId) {
    var total = 0;
    var sawFeed = false;
    for (final feed in _feeds) {
      if ((feed.categoryId ?? defaultCategoryId) != categoryId) continue;
      sawFeed = true;
      total += _unreadByFeed[feed.id] ?? 0;
    }
    if (!sawFeed) return _unreadByCategory[categoryId] ?? 0;
    return total;
  }

  /// Unread articles across every feed.
  int get totalUnread =>
      _unreadByFeed.values.fold<int>(0, (sum, count) => sum + count);

  /// Feeds grouped by category id, in category `sortOrder`.
  ///
  /// Feeds with no (or an unknown) category land under [defaultCategoryId].
  /// Categories without feeds are omitted.
  Map<String, List<RSSFeed>> get feedsByCategory {
    final known = <String>{for (final category in _categories) category.id};
    final buckets = <String, List<RSSFeed>>{};
    for (final feed in _feeds) {
      final id = feed.categoryId;
      final key = (id != null && (known.isEmpty || known.contains(id)))
          ? id
          : defaultCategoryId;
      buckets.putIfAbsent(key, () => <RSSFeed>[]).add(feed);
    }

    // A plain map literal keeps insertion order, which is category order here.
    final ordered = <String, List<RSSFeed>>{};
    for (final category in _categories) {
      final bucket = buckets.remove(category.id);
      if (bucket != null && bucket.isNotEmpty) ordered[category.id] = bucket;
    }
    // Anything left belongs to a category row we do not have.
    ordered.addAll(buckets);
    return ordered;
  }

  RSSFeed? getFeedById(String id) {
    for (final feed in _feeds) {
      if (feed.id == id) return feed;
    }
    return null;
  }

  Category? getCategoryById(String? id) {
    if (id == null) return null;
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _rssService.dispose();
    _discovery.dispose();
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads feeds, categories and unread counts.
  Future<void> loadFeeds() async {
    _setLoading(true);
    try {
      await _reload();
      _error = null;
    } catch (e) {
      _error = 'Failed to load feeds: $e';
      AppLog.w('Failed to load feeds', e);
    } finally {
      _setLoading(false);
    }
  }

  /// Re-reads everything without touching [isLoading]; used after mutations.
  Future<void> _reload() async {
    final feeds = await _databaseService.getAllFeeds();
    final categories = await _databaseService.getAllCategories();
    final unreadByFeed = await _databaseService.getUnreadCountsByFeed();
    final unreadByCategory = await _databaseService.getUnreadCountsByCategory();

    categories.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.name.compareTo(b.name);
    });

    _feeds = feeds;
    _categories = categories;
    _unreadByFeed = unreadByFeed;
    _unreadByCategory = unreadByCategory;

    for (final feed in _feeds) {
      feed.unreadCount = unreadByFeed[feed.id] ?? 0;
    }
    final feedsPerCategory = <String, int>{};
    for (final feed in _feeds) {
      final key = feed.categoryId ?? defaultCategoryId;
      feedsPerCategory[key] = (feedsPerCategory[key] ?? 0) + 1;
    }
    for (final category in _categories) {
      category.feedsCount = feedsPerCategory[category.id] ?? 0;
    }
  }

  /// Reloads subscriptions and counts. Article refresh lives in
  /// `ArticleProvider.refreshAllArticles`.
  Future<void> refreshAllFeeds() => loadFeeds();

  /// Categories to categorise against, falling back to the built-in list when
  /// the database has not been read yet.
  List<Category> get _categoriesForMatching =>
      _categories.isNotEmpty ? _categories : Category.defaultCategories;

  // ---------------------------------------------------------------------------
  // Adding feeds
  // ---------------------------------------------------------------------------

  /// Resolves [input] (a feed URL, a site URL or a bare host) and subscribes.
  ///
  /// When discovery finds more than one feed the result carries the
  /// [AddFeedResult.candidates] and nothing is written; call
  /// [addDiscoveredFeed] with the user's pick.
  Future<AddFeedResult> addFeed(String input, {String? categoryId}) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      _error = 'Enter a feed or website address.';
      _notify();
      return AddFeedResult.failure(_error!);
    }

    _setLoading(true);
    try {
      final candidates = await _discovery.discover(trimmed);
      if (candidates.length != 1) {
        final result = AddFeedResult.needsSelection(candidates);
        _error = result.error;
        return result;
      }
      return await _subscribe(
        candidates.first.url,
        categoryId: categoryId,
        discovered: candidates.first,
      );
    } catch (e, st) {
      AppLog.e('Failed to add feed $trimmed', e, st);
      _error = 'Failed to add feed: ${_friendly(e)}';
      return AddFeedResult.failure(_error!);
    } finally {
      _setLoading(false);
    }
  }

  /// Subscribes to a feed the user picked from [AddFeedResult.candidates].
  Future<AddFeedResult> addDiscoveredFeed(
    DiscoveredFeed discovered, {
    String? categoryId,
  }) async {
    _setLoading(true);
    try {
      return await _subscribe(
        discovered.url,
        categoryId: categoryId,
        discovered: discovered,
      );
    } catch (e, st) {
      AppLog.e('Failed to add feed ${discovered.url}', e, st);
      _error = 'Failed to add feed: ${_friendly(e)}';
      return AddFeedResult.failure(_error!);
    } finally {
      _setLoading(false);
    }
  }

  /// Shared body of [addFeed] / [addDiscoveredFeed]. Does not touch
  /// [isLoading]; callers own that.
  Future<AddFeedResult> _subscribe(
    String url, {
    String? categoryId,
    DiscoveredFeed? discovered,
  }) async {
    final feedId = RssService.feedIdFor(url);

    final existing = await _findExisting(feedId, url);
    if (existing != null) {
      final result = AddFeedResult.duplicate(existing);
      _error = result.error;
      return result;
    }

    RSSFeed info;
    try {
      info = await _rssService.fetchFeedInfo(url);
    } catch (e) {
      if (discovered == null) rethrow;
      // Discovery already parsed this document; fall back to its metadata
      // rather than failing on a second fetch.
      AppLog.w('Could not re-read feed info for $url', e);
      info = RSSFeed(
        id: feedId,
        title: discovered.title,
        url: url,
        description: '',
        siteUrl: discovered.siteUrl,
        dateAdded: DateTime.now(),
      );
    }

    final now = DateTime.now();
    final resolvedCategory =
        categoryId ?? quickCategorizeOne(info, _categoriesForMatching);
    final feed = RSSFeed(
      id: feedId,
      title: info.title.trim().isEmpty ? (hostOf(url) ?? url) : info.title,
      url: url,
      description: info.description,
      imageUrl: info.imageUrl ?? faviconUrlFor(info.siteUrl ?? url),
      categoryId: resolvedCategory,
      siteUrl: info.siteUrl ?? discovered?.siteUrl,
      language: info.language,
      dateAdded: now,
      lastUpdated: now,
      lastFetchedAt: now,
      isActive: true,
    );

    await _databaseService.insertFeed(feed);

    var newArticleCount = 0;
    try {
      final articles = await _rssService.fetchFeedArticles(
        url,
        feed.id,
        categoryId: feed.categoryId,
      );
      if (articles.isNotEmpty) {
        newArticleCount = await _databaseService.insertArticlesBatch(articles);
      }
    } catch (e) {
      // The subscription is valid even when the first fetch fails.
      AppLog.w('Could not load articles for $url', e);
      await _safe(
        () =>
            _databaseService.updateFeedStatus(feed.id, lastError: _friendly(e)),
      );
    }

    await _reload();
    _error = null;
    _notify();
    return AddFeedResult.success(getFeedById(feed.id) ?? feed, newArticleCount);
  }

  Future<RSSFeed?> _findExisting(String feedId, String url) async {
    for (final feed in _feeds) {
      if (feed.id == feedId || feed.url.trim() == url.trim()) return feed;
    }
    final byId = await _safe<RSSFeed?>(
      () => _databaseService.getFeedById(feedId),
    );
    if (byId != null) return byId;
    return await _safe<RSSFeed?>(() => _databaseService.getFeedByUrl(url));
  }

  // ---------------------------------------------------------------------------
  // Editing feeds
  // ---------------------------------------------------------------------------

  /// Persists title / category / active changes for [feed].
  ///
  /// When the category changed, the feed's articles are re-tagged so category
  /// article lists stay correct.
  Future<bool> updateFeed(RSSFeed feed) async {
    try {
      final previous = getFeedById(feed.id);
      await _databaseService.updateFeed(feed);
      if (previous == null || previous.categoryId != feed.categoryId) {
        await _databaseService.updateArticleCategoryForFeed(
          feed.id,
          feed.categoryId,
        );
      }
      await _reload();
      _error = null;
      _notify();
      return true;
    } catch (e) {
      _error = 'Failed to update feed: ${_friendly(e)}';
      AppLog.w('Failed to update feed ${feed.id}', e);
      _notify();
      return false;
    }
  }

  /// Re-reads a feed's own metadata (title, description, icon, site, language).
  Future<bool> refreshFeedInfo(String feedId) async {
    final feed =
        getFeedById(feedId) ??
        await _safe<RSSFeed?>(() => _databaseService.getFeedById(feedId));
    if (feed == null) {
      _error = 'Feed not found.';
      _notify();
      return false;
    }

    try {
      final info = await _rssService.fetchFeedInfo(feed.url);
      final now = DateTime.now();
      final updated = RSSFeed(
        id: feed.id,
        title: info.title.trim().isEmpty ? feed.title : info.title,
        url: feed.url,
        description: info.description.trim().isEmpty
            ? feed.description
            : info.description,
        imageUrl:
            info.imageUrl ??
            feed.imageUrl ??
            faviconUrlFor(info.siteUrl ?? feed.url),
        categoryId: feed.categoryId,
        siteUrl: info.siteUrl ?? feed.siteUrl,
        language: info.language ?? feed.language,
        dateAdded: feed.dateAdded,
        lastUpdated: now,
        lastFetchedAt: now,
        isActive: feed.isActive,
      );
      await _databaseService.updateFeed(updated);
      await _safe(
        () => _databaseService.updateFeedStatus(
          feed.id,
          lastFetchedAt: now,
          clearError: true,
        ),
      );
      await _reload();
      _error = null;
      _notify();
      return true;
    } catch (e) {
      final message = _friendly(e);
      AppLog.w('Failed to refresh feed info for ${feed.url}', e);
      await _safe(
        () => _databaseService.updateFeedStatus(feed.id, lastError: message),
      );
      await _safe(_reload);
      _error = 'Failed to refresh feed: $message';
      _notify();
      return false;
    }
  }

  /// Deletes a single feed (and its articles) by [id]. Returns true on success.
  Future<bool> deleteFeed(String id) async {
    try {
      await _databaseService.deleteFeed(id);
      await _reload();
      _error = null;
      _notify();
      return true;
    } catch (e) {
      _error = 'Failed to delete feed: ${_friendly(e)}';
      AppLog.w('Failed to delete feed $id', e);
      _feeds.removeWhere((f) => f.id == id);
      _notify();
      return false;
    }
  }

  /// Deletes multiple feeds. Returns counts of successful and failed deletions.
  Future<Map<String, int>> deleteFeeds(List<String> ids) async {
    var success = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await _databaseService.deleteFeed(id);
        success++;
      } catch (e) {
        AppLog.w('Error deleting feed $id', e);
        failed++;
      }
    }
    if (ids.isNotEmpty) await _safe(_reload);
    _notify();
    return {'success': success, 'failed': failed};
  }

  /// Moves multiple feeds into [category], re-tagging their articles.
  Future<Map<String, int>> updateFeedsCategory(
    List<String> ids,
    String category,
  ) async {
    var success = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        final feed = getFeedById(id);
        if (feed == null) {
          failed++;
          continue;
        }
        await _databaseService.updateFeed(feed.copyWith(categoryId: category));
        await _databaseService.updateArticleCategoryForFeed(id, category);
        success++;
      } catch (e) {
        AppLog.w('Error updating feed category for $id', e);
        failed++;
      }
    }
    if (ids.isNotEmpty) await _safe(_reload);
    _notify();
    return {'success': success, 'failed': failed};
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  /// Imports feeds (e.g. parsed from an OPML file), skipping URLs that
  /// already exist. Returns counts of imported and skipped feeds.
  ///
  /// Feeds whose category is missing or unknown are categorised offline.
  Future<Map<String, int>> importFeeds(List<RSSFeed> feedsToImport) async {
    _setLoading(true);
    var imported = 0;
    var skipped = 0;
    try {
      final existing = await _databaseService.getAllFeeds();
      final existingUrls = existing.map((f) => f.url.trim()).toSet();
      final existingIds = existing.map((f) => f.id).toSet();

      final categories = await _safe(_databaseService.getAllCategories);
      final matchAgainst = (categories == null || categories.isEmpty)
          ? _categoriesForMatching
          : categories;
      final knownCategoryIds = <String>{for (final c in matchAgainst) c.id};

      for (final feed in feedsToImport) {
        final url = feed.url.trim();
        if (url.isEmpty) {
          skipped++;
          continue;
        }
        final id = feed.id.trim().isEmpty ? RssService.feedIdFor(url) : feed.id;
        if (existingUrls.contains(url) || existingIds.contains(id)) {
          skipped++;
          continue;
        }

        final categoryId =
            (feed.categoryId != null &&
                knownCategoryIds.contains(feed.categoryId))
            ? feed.categoryId!
            : quickCategorizeOne(feed, matchAgainst);

        await _databaseService.insertFeed(
          feed.copyWith(id: id, categoryId: categoryId),
        );
        existingUrls.add(url);
        existingIds.add(id);
        imported++;
      }
      await _reload();
      _error = null;
    } catch (e) {
      _error = 'Failed to import feeds: ${_friendly(e)}';
      AppLog.w('Failed to import feeds', e);
    } finally {
      _setLoading(false);
    }
    return {'imported': imported, 'skipped': skipped};
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  /// Creates a category and returns it, or null when it could not be stored.
  Future<Category?> addCategory(
    String name, {
    String? iconName,
    String? color,
  }) async {
    final label = name.trim();
    if (label.isEmpty) {
      _error = 'Enter a category name.';
      _notify();
      return null;
    }

    try {
      final id = _uniqueCategoryId(label);
      final maxOrder = _categories.fold<int>(
        -1,
        (max, c) => c.sortOrder > max ? c.sortOrder : max,
      );
      final category = Category(
        id: id,
        name: label,
        description: '',
        iconName: iconName,
        color: color,
        dateCreated: DateTime.now(),
        sortOrder: maxOrder + 1,
      );
      await _databaseService.insertCategory(category);
      await _reload();
      _error = null;
      _notify();
      return getCategoryById(id) ?? category;
    } catch (e) {
      _error = 'Failed to add category: ${_friendly(e)}';
      AppLog.w('Failed to add category $label', e);
      _notify();
      return null;
    }
  }

  Future<bool> updateCategory(Category category) async {
    try {
      await _databaseService.updateCategory(category);
      await _reload();
      _error = null;
      _notify();
      return true;
    } catch (e) {
      _error = 'Failed to update category: ${_friendly(e)}';
      AppLog.w('Failed to update category ${category.id}', e);
      _notify();
      return false;
    }
  }

  /// Deletes [id] and moves its feeds (and their articles) to
  /// [defaultCategoryId]. Refuses to delete the default category itself.
  Future<bool> deleteCategory(String id) async {
    if (id == defaultCategoryId) {
      _error = 'The General category cannot be deleted.';
      _notify();
      return false;
    }

    try {
      final affected = _feeds.where((f) => f.categoryId == id).toList();
      for (final feed in affected) {
        await _databaseService.updateFeed(
          feed.copyWith(categoryId: defaultCategoryId),
        );
        await _databaseService.updateArticleCategoryForFeed(
          feed.id,
          defaultCategoryId,
        );
      }
      await _databaseService.deleteCategory(id);
      await _reload();
      _error = null;
      _notify();
      return true;
    } catch (e) {
      _error = 'Failed to delete category: ${_friendly(e)}';
      AppLog.w('Failed to delete category $id', e);
      _notify();
      return false;
    }
  }

  /// Applies a new order; [orderedIds] lists category ids top to bottom.
  Future<bool> reorderCategories(List<String> orderedIds) async {
    try {
      for (var i = 0; i < orderedIds.length; i++) {
        final category = getCategoryById(orderedIds[i]);
        if (category == null || category.sortOrder == i) continue;
        await _databaseService.updateCategory(category.copyWith(sortOrder: i));
      }
      await _reload();
      _error = null;
      _notify();
      return true;
    } catch (e) {
      _error = 'Failed to reorder categories: ${_friendly(e)}';
      AppLog.w('Failed to reorder categories', e);
      _notify();
      return false;
    }
  }

  String _uniqueCategoryId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final slug = base.isEmpty ? 'category' : base;
    final taken = <String>{for (final c in _categories) c.id};
    if (!taken.contains(slug)) return slug;
    for (var i = 2; i < 100; i++) {
      if (!taken.contains('${slug}_$i')) return '${slug}_$i';
    }
    return '${slug}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Runs [action], swallowing failures (used for best-effort DB writes that
  /// must not mask the real result of an operation).
  Future<T?> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      AppLog.d('Ignored provider failure: $e');
      return null;
    }
  }

  static String _friendly(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
}
