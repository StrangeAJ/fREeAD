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

  Future<Map<String, int>> deleteFeeds(List<String> ids) async => {'success': 0, 'failed': 0};
  Future<Map<String, int>> updateFeedsCategory(List<String> ids, String category) async => {'success': 0, 'failed': 0};
}
