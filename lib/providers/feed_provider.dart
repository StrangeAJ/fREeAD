import 'package:flutter/material.dart';
import '../models/rss_feed.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../services/rss_service.dart';

class FeedProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final RssService _rssService = RssService();

  List<RSSFeed> _feeds = [];
  List<Category> _categories = [];
  bool _isLoading = false;
  String? _error;

  List<RSSFeed> get feeds => _feeds;
  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadFeeds() async {
    _setLoading(true);
    try {
      _feeds = await _databaseService.getAllFeeds();
      _error = null;
    } catch (e) {
      _error = 'Failed to load feeds: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addFeed(String url) async {
    _setLoading(true);
    try {
      final feed = RSSFeed(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Loading...',
        url: url,
        description: '',
        categoryId: 'general',
        isActive: true,
        dateAdded: DateTime.now(),
        lastUpdated: DateTime.now(),
      );
      
      await _databaseService.insertFeed(feed);
      await loadFeeds();
      _error = null;
      return true;
    } catch (e) {
      _error = 'Failed to add feed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshAllFeeds() async {
    await loadFeeds();
  }

  /// Imports feeds (e.g. parsed from an OPML file), skipping URLs that
  /// already exist. Returns counts of imported and skipped feeds.
  Future<Map<String, int>> importFeeds(List<RSSFeed> feedsToImport) async {
    _setLoading(true);
    int imported = 0;
    int skipped = 0;
    try {
      final existing = await _databaseService.getAllFeeds();
      final existingUrls = existing.map((f) => f.url.trim()).toSet();

      for (final feed in feedsToImport) {
        if (existingUrls.contains(feed.url.trim())) {
          skipped++;
          continue;
        }
        await _databaseService.insertFeed(feed);
        existingUrls.add(feed.url.trim());
        imported++;
      }
      await loadFeeds();
      _error = null;
    } catch (e) {
      _error = 'Failed to import feeds: $e';
    } finally {
      _setLoading(false);
    }
    return {'imported': imported, 'skipped': skipped};
  }

  RSSFeed? getFeedById(String id) {
    try {
      return _feeds.firstWhere((f) => f.id == id);
    } catch (e) {
      return null;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Deletes a single feed by [id]. Returns true on success.
  Future<bool> deleteFeed(String id) async {
    try {
      await _databaseService.deleteFeed(id);
      _feeds.removeWhere((f) => f.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete feed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Deletes multiple feeds. Returns counts of successful and failed deletions.
  Future<Map<String, int>> deleteFeeds(List<String> ids) async {
    int success = 0;
    int failed = 0;
    for (final id in ids) {
      try {
        await _databaseService.deleteFeed(id);
        success++;
      } catch (e) {
        print('Error deleting feed $id: $e');
        failed++;
      }
    }
    await loadFeeds();
    return {'success': success, 'failed': failed};
  }

  /// Updates the category for multiple feeds.
  Future<Map<String, int>> updateFeedsCategory(List<String> ids, String category) async {
    int success = 0;
    int failed = 0;
    for (final id in ids) {
      try {
        final feed = getFeedById(id);
        if (feed != null) {
          await _databaseService.updateFeed(feed.copyWith(categoryId: category));
          success++;
        } else {
          failed++;
        }
      } catch (e) {
        print('Error updating feed category for $id: $e');
        failed++;
      }
    }
    await loadFeeds();
    return {'success': success, 'failed': failed};
  }
}
