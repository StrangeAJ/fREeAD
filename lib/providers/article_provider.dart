import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../models/app_settings.dart';
import '../models/rss_feed.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/rss/rss_service.dart';
import '../services/extraction/article_extractor.dart';
import '../services/extraction/extraction_result.dart';
import '../services/extraction/webview_extractor.dart';
import '../utils/app_logger.dart';
import '../utils/concurrency_utils.dart';

/// Live progress of a refresh run.
class RefreshProgress {
  const RefreshProgress({
    required this.done,
    required this.total,
    this.currentFeedTitle,
    this.newArticles = 0,
    this.failedFeeds = const <String>[],
  });

  final int done;
  final int total;
  final String? currentFeedTitle;
  final int newArticles;
  final List<String> failedFeeds;

  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  @override
  String toString() => 'RefreshProgress($done/$total, +$newArticles)';
}

/// Result of a completed refresh run.
class RefreshSummary {
  const RefreshSummary({
    required this.totalFeeds,
    required this.newArticles,
    this.failedFeedTitles = const <String>[],
    this.skipped = false,
  });

  final int totalFeeds;
  final int newArticles;
  final List<String> failedFeedTitles;

  /// True when the refresh was skipped because nothing was stale.
  final bool skipped;

  int get failedFeeds => failedFeedTitles.length;

  bool get hasFailures => failedFeedTitles.isNotEmpty;

  @override
  String toString() =>
      'RefreshSummary(feeds: $totalFeeds, new: $newArticles, '
      'failed: $failedFeeds, skipped: $skipped)';
}

/// Owns the article lists, refresh orchestration and full-article extraction.
class ArticleProvider with ChangeNotifier {
  ArticleProvider({
    DatabaseService? database,
    RssService? rssService,
    ArticleExtractor? extractor,
  }) : _database = database ?? DatabaseService(),
        _rss = rssService ?? RssService(),
        _extractor =
            extractor ?? ArticleExtractor(webview: WebviewExtractor());

  final DatabaseService _database;
  final RssService _rss;
  final ArticleExtractor _extractor;

  List<Article> _articles = <Article>[];
  List<Article> _savedArticles = <Article>[];
  List<Article> _starredArticles = <Article>[];

  final Set<String> _loadingFullArticles = <String>{};
  final Map<String, String> _extractionErrors = <String, String>{};
  final Map<String, Debouncer> _scrollDebouncers = <String, Debouncer>{};

  bool _isLoading = false;
  bool _disposed = false;
  String? _error;
  RefreshProgress? _refreshProgress;

  /// Concurrent feed fetches during a refresh.
  static const int refreshConcurrency = 4;

  List<Article> get articles => _articles;
  List<Article> get savedArticles => _savedArticles;
  List<Article> get starredArticles => _starredArticles;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Non-null while a refresh is running.
  RefreshProgress? get refreshProgress => _refreshProgress;

  bool get isRefreshing => _refreshProgress != null;

  int get unreadCount => _articles.where((a) => !a.isRead).length;

  @override
  void dispose() {
    _disposed = true;
    for (final debouncer in _scrollDebouncers.values) {
      debouncer.dispose();
    }
    _scrollDebouncers.clear();
    _rss.dispose();
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

  Future<void> loadArticles() async {
    _setLoading(true);
    try {
      _articles = await _database.getAllArticles();
      _savedArticles = await _database.getSavedArticles();
      _starredArticles = await _database.getStarredArticles();
      _error = null;
    } catch (e) {
      _error = 'Failed to load articles: ${_short(e)}';
      AppLog.e('Failed to load articles', e);
    } finally {
      _setLoading(false);
    }
  }

  Article? getArticleById(String id) {
    for (final article in _articles) {
      if (article.id == id) return article;
    }
    for (final article in _savedArticles) {
      if (article.id == id) return article;
    }
    for (final article in _starredArticles) {
      if (article.id == id) return article;
    }
    return null;
  }

  Future<List<Article>> searchArticles(String query) =>
      _database.searchArticles(query);

  Future<List<Article>> getArticlesByCategory(String categoryId) =>
      _database.getArticlesByCategory(categoryId);

  Future<List<Article>> getArticlesByFeed(String feedId) =>
      _database.getArticlesByFeed(feedId);

  /// Re-reads one article from the database into the in-memory lists.
  Future<void> refreshArticle(String id) async {
    try {
      final updated = await _database.getArticleById(id);
      if (updated == null) return;
      _replaceInLists(updated);
      _notify();
    } catch (e) {
      AppLog.d('Could not refresh article $id: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------

  /// Refreshes every active feed with [refreshConcurrency] fetches in flight.
  Future<RefreshSummary> refreshAllArticles() async {
    if (_refreshProgress != null) {
      return const RefreshSummary(
        totalFeeds: 0,
        newArticles: 0,
        skipped: true,
      );
    }

    List<RSSFeed> feeds;
    try {
      feeds = await _database.getAllFeeds();
    } catch (e) {
      _error = 'Failed to load feeds: ${_short(e)}';
      _notify();
      return const RefreshSummary(totalFeeds: 0, newArticles: 0);
    }

    final active = feeds.where((f) => f.isActive).toList();
    if (active.isEmpty) {
      await loadArticles();
      return const RefreshSummary(totalFeeds: 0, newArticles: 0);
    }

    var newArticles = 0;
    final failed = <String>[];
    _refreshProgress = RefreshProgress(done: 0, total: active.length);
    _notify();

    await mapWithConcurrency<void, RSSFeed>(
      active,
      refreshConcurrency,
      (feed) async {
        _refreshProgress = RefreshProgress(
          done: _refreshProgress?.done ?? 0,
          total: active.length,
          currentFeedTitle: feed.title,
          newArticles: newArticles,
          failedFeeds: List<String>.unmodifiable(failed),
        );
        _notify();
        try {
          final fetched = await _rss.fetchFeedArticles(
            feed.url,
            feed.id,
            categoryId: feed.categoryId,
          );
          final inserted = await _database.insertArticlesBatch(fetched);
          newArticles += inserted;
          await _database.updateFeedStatus(
            feed.id,
            lastFetchedAt: DateTime.now(),
            clearError: true,
          );
        } catch (e) {
          AppLog.w('Refresh failed for ${feed.title}', e);
          failed.add(feed.title);
          try {
            await _database.updateFeedStatus(feed.id, lastError: _short(e));
          } catch (_) {
            // Status is best effort.
          }
        }
      },
      onProgress: (done, total) {
        _refreshProgress = RefreshProgress(
          done: done,
          total: total,
          currentFeedTitle: _refreshProgress?.currentFeedTitle,
          newArticles: newArticles,
          failedFeeds: List<String>.unmodifiable(failed),
        );
        _notify();
      },
    );

    _refreshProgress = null;
    await loadArticles();

    return RefreshSummary(
      totalFeeds: active.length,
      newArticles: newArticles,
      failedFeedTitles: List<String>.unmodifiable(failed),
    );
  }

  /// Compatibility alias used by existing screens.
  Future<RefreshSummary> refreshArticles() => refreshAllArticles();

  /// Refreshes a single feed.
  Future<RefreshSummary> refreshFeed(String feedId) async {
    try {
      final feed = await _database.getFeedById(feedId);
      if (feed == null) {
        return const RefreshSummary(totalFeeds: 0, newArticles: 0);
      }
      final fetched = await _rss.fetchFeedArticles(
        feed.url,
        feed.id,
        categoryId: feed.categoryId,
      );
      final inserted = await _database.insertArticlesBatch(fetched);
      await _database.updateFeedStatus(
        feed.id,
        lastFetchedAt: DateTime.now(),
        clearError: true,
      );
      await loadArticles();
      return RefreshSummary(totalFeeds: 1, newArticles: inserted);
    } catch (e) {
      AppLog.w('Refresh failed for feed $feedId', e);
      try {
        await _database.updateFeedStatus(feedId, lastError: _short(e));
      } catch (_) {
        // Best effort.
      }
      _error = 'Could not refresh this feed. ${_short(e)}';
      _notify();
      return RefreshSummary(
        totalFeeds: 1,
        newArticles: 0,
        failedFeedTitles: <String>[feedId],
      );
    }
  }

  /// Refreshes when the configured interval has elapsed since the last run.
  Future<RefreshSummary> refreshIfStale(SettingsProvider settings) async {
    if (!settings.refreshOnLaunch) {
      return const RefreshSummary(totalFeeds: 0, newArticles: 0, skipped: true);
    }
    final interval = settings.refreshIntervalMinutes;
    final last = settings.lastRefreshAt;
    if (interval > 0 && last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < Duration(minutes: interval)) {
        return const RefreshSummary(
          totalFeeds: 0,
          newArticles: 0,
          skipped: true,
        );
      }
    }
    final summary = await refreshAllArticles();
    await settings.setLastRefreshAt(DateTime.now());
    return summary;
  }

  // ---------------------------------------------------------------------------
  // Read / saved / starred state
  // ---------------------------------------------------------------------------

  Future<void> markAsRead(String articleId) async {
    final article = getArticleById(articleId);
    if (article != null && article.isRead) return;
    try {
      await _database.markArticleAsRead(articleId);
    } catch (e) {
      AppLog.w('Could not mark $articleId as read', e);
    }
    if (article == null) return;
    _replaceInLists(article.copyWith(isRead: true, readAt: DateTime.now()));
    _notify();
  }

  Future<void> markAsUnread(String articleId) async {
    final article = getArticleById(articleId);
    try {
      await _database.markArticleAsUnread(articleId);
    } catch (e) {
      AppLog.w('Could not mark $articleId as unread', e);
    }
    if (article == null) return;
    _replaceInLists(article.copyWith(isRead: false, clearReadAt: true));
    _notify();
  }

  /// Marks every article read, optionally limited to a feed or a category.
  /// Returns the number of rows changed.
  Future<int> markAllAsRead({String? feedId, String? categoryId}) async {
    try {
      final changed = await _database.markAllAsRead(
        feedId: feedId,
        categoryId: categoryId,
      );
      final now = DateTime.now();
      bool matches(Article a) {
        if (feedId != null && a.feedId != feedId) return false;
        if (categoryId != null && a.categoryId != categoryId) return false;
        return true;
      }

      for (final article in List<Article>.from(_articles)) {
        if (article.isRead || !matches(article)) continue;
        _replaceInLists(article.copyWith(isRead: true, readAt: now));
      }
      _notify();
      return changed;
    } catch (e) {
      AppLog.e('Failed to mark all as read', e);
      _error = 'Could not mark articles as read.';
      _notify();
      return 0;
    }
  }

  Future<void> toggleSaved(String articleId) async {
    final article = getArticleById(articleId);
    if (article == null) return;
    final next = !article.isSaved;
    try {
      await _database.markArticleAsSaved(articleId, next);
    } catch (e) {
      AppLog.w('Could not toggle saved for $articleId', e);
      return;
    }
    _replaceInLists(article.copyWith(isSaved: next));
    _notify();
  }

  Future<void> toggleStarred(String articleId) async {
    final article = getArticleById(articleId);
    if (article == null) return;
    final next = !article.isStarred;
    try {
      await _database.markArticleAsStarred(articleId, next);
    } catch (e) {
      AppLog.w('Could not toggle starred for $articleId', e);
      return;
    }
    _replaceInLists(article.copyWith(isStarred: next));
    _notify();
  }

  /// Compatibility alias.
  Future<void> toggleStar(String articleId) => toggleStarred(articleId);

  /// Stores the reading position, debounced by 500 ms per article.
  void saveScrollProgress(String articleId, double progress) {
    final clamped = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final article = getArticleById(articleId);
    if (article != null) {
      _replaceInLists(article.copyWith(scrollProgress: clamped), notify: false);
    }
    final debouncer = _scrollDebouncers.putIfAbsent(
      articleId,
      () => Debouncer(const Duration(milliseconds: 500)),
    );
    debouncer.run(() async {
      try {
        await _database.updateScrollProgress(articleId, clamped);
      } catch (e) {
        AppLog.d('Could not persist scroll progress: $e');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Full article extraction
  // ---------------------------------------------------------------------------

  bool isLoadingFullArticle(String id) => _loadingFullArticles.contains(id);

  /// Message describing why the last extraction of [id] failed.
  String? lastExtractionError(String id) => _extractionErrors[id];

  /// Fetches, extracts and persists the full body of [articleId].
  ///
  /// Returns true when a body was stored.
  Future<bool> loadFullArticle(
    String articleId, {
    ExtractionEngine engine = ExtractionEngine.auto,
    bool force = false,
  }) async {
    var article = getArticleById(articleId);
    article ??= await _database.getArticleById(articleId);
    if (article == null) return false;

    if (!force && article.hasFullContent) return true;
    if (_loadingFullArticles.contains(articleId)) return false;

    _loadingFullArticles.add(articleId);
    _extractionErrors.remove(articleId);
    _notify();

    try {
      final result = await _extractor.extract(
        article.url,
        engine: engine,
        rssHtml: article.content,
        force: force,
      );
      if (result == null || result.html.trim().isEmpty) {
        _extractionErrors[articleId] =
            'No readable content was found on this page.';
        return false;
      }

      final updated = article.copyWith(
        fullContent: result.html,
        extractedTitle: result.title,
        siteName: result.siteName,
        fullContentSource: result.source,
        fullContentFetchedAt: DateTime.now(),
        imageUrl: article.imageUrl ?? result.leadImageUrl,
      );
      try {
        await _database.updateArticle(updated);
      } catch (e) {
        AppLog.w('Could not persist full content for $articleId', e);
      }
      _replaceInLists(updated, notify: false);
      _error = null;
      return true;
    } on ExtractionException catch (e) {
      _extractionErrors[articleId] = e.userMessage;
      AppLog.w('Extraction failed for ${article.url}: ${e.userMessage}');
      return false;
    } catch (e) {
      _extractionErrors[articleId] = 'Could not load the article.';
      AppLog.e('Extraction failed for ${article.url}', e);
      return false;
    } finally {
      _loadingFullArticles.remove(articleId);
      _notify();
    }
  }

  /// Drops the cached body of [articleId] (or every article when null).
  Future<int> clearFullContent([String? articleId]) async {
    try {
      final changed = await _database.clearFullContent(articleId: articleId);
      if (articleId != null) {
        final article = getArticleById(articleId);
        if (article != null) {
          _replaceInLists(article.copyWith(clearFullContent: true));
        }
      } else {
        _articles = _articles
            .map((a) => a.copyWith(clearFullContent: true))
            .toList();
        _savedArticles = _savedArticles
            .map((a) => a.copyWith(clearFullContent: true))
            .toList();
        _starredArticles = _starredArticles
            .map((a) => a.copyWith(clearFullContent: true))
            .toList();
      }
      _extractor.clearCache();
      _notify();
      return changed;
    } catch (e) {
      AppLog.e('Failed to clear cached articles', e);
      return 0;
    }
  }

  /// Downloads full bodies for the newest unread articles, for offline reading.
  Future<int> prefetchFullArticles({int limit = 20}) async {
    final candidates =
        _articles
            .where((a) => !a.isRead && !a.hasFullContent)
            .take(limit)
            .toList();
    if (candidates.isEmpty) return 0;

    var stored = 0;
    await mapWithConcurrency<void, Article>(candidates, 2, (article) async {
      final ok = await loadFullArticle(
        article.id,
        engine: ExtractionEngine.fast,
      );
      if (ok) stored++;
    });
    _notify();
    return stored;
  }

  /// Persists user-edited article text.
  Future<bool> updateArticleContent(
    String articleId,
    String newContent, {
    bool editFullContent = false,
  }) async {
    try {
      var article = getArticleById(articleId);
      article ??= await _database.getArticleById(articleId);
      if (article == null) return false;

      final updated = editFullContent
          ? article.copyWith(
              fullContent: newContent,
              fullContentSource: article.fullContentSource ?? 'http',
            )
          : article.copyWith(content: newContent);
      await _database.updateArticle(updated);
      _replaceInLists(updated);
      _notify();
      return true;
    } catch (e) {
      AppLog.e('Error updating article content', e);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  /// Deletes articles older than [days], keeping saved and starred ones.
  Future<int> cleanupOldArticles(int days) async {
    if (days <= 0) return 0;
    try {
      final deleted = await _database.deleteOldArticles(days);
      if (deleted > 0) await loadArticles();
      return deleted;
    } catch (e) {
      AppLog.e('Cleanup failed', e);
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Single place where the three lists are kept consistent.
  void _replaceInLists(Article article, {bool notify = false}) {
    void apply(List<Article> list, bool shouldContain) {
      final index = list.indexWhere((a) => a.id == article.id);
      if (shouldContain) {
        if (index == -1) {
          list.add(article);
          list.sort((a, b) => b.publishedDate.compareTo(a.publishedDate));
        } else {
          list[index] = article;
        }
      } else if (index != -1) {
        list.removeAt(index);
      }
    }

    final mainIndex = _articles.indexWhere((a) => a.id == article.id);
    if (mainIndex != -1) _articles[mainIndex] = article;
    apply(_savedArticles, article.isSaved);
    apply(_starredArticles, article.isStarred);

    if (notify) _notify();
  }

  static String _short(Object error) {
    final text = error.toString().replaceAll('Exception: ', '');
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 160
        ? '${firstLine.substring(0, 157)}...'
        : firstLine;
  }
}