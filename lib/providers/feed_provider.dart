import 'package:flutter/foundation.dart';
import '../models/rss_feed.dart';
import '../models/category.dart' as model;
import '../services/database_service.dart';
import '../services/rss_service.dart';
import 'article_provider.dart';
import 'package:flutter/foundation.dart';
import '../utils/concurrency_utils.dart';

class FeedProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final RSSService _rssService = RSSService();

  List<RSSFeed> _feeds = [];
  List<model.Category> _categories = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<RSSFeed> get feeds => _feeds;
  List<model.Category> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load all feeds
  Future<void> loadFeeds() async {
    _setLoading(true);
    try {
      if (kIsWeb) {
        // For web, use sample data
        _feeds = [
          RSSFeed(
            id: 'sample-1',
            title: 'Sample RSS Feed',
            url: 'https://example.com/feed',
            description: 'Sample feed for web demo',
            categoryId: 'news',
            isActive: true,
            dateAdded: DateTime.now(),
            lastUpdated: DateTime.now(),
          ),
        ];
        _categories = model.Category.defaultCategories;
      } else {
        _feeds = await _databaseService.getAllFeeds();
        _categories = await _databaseService.getAllCategories();
        
        // Add default categories if none exist
        if (_categories.isEmpty) {
          _categories = model.Category.defaultCategories;
          for (final category in _categories) {
            await _databaseService.insertCategory(category);
          }
        }
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load feeds: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Get feeds by category
  List<RSSFeed> getFeedsByCategory(String categoryId) {
    return _feeds.where((feed) => feed.categoryId == categoryId).toList();
  }

  // Get feed by ID
  RSSFeed? getFeedById(String feedId) {
    try {
      return _feeds.firstWhere((feed) => feed.id == feedId);
    } catch (e) {
      return null;
    }
  }

  // Add new feed
  Future<bool> addFeed(String url, {String? categoryId}) async {
    _setLoading(true);
    try {
      if (kIsWeb) {
        // For web, just add to in-memory list
        final feed = RSSFeed(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'RSS Feed',
          url: url,
          description: 'RSS feed added from web',
          categoryId: categoryId ?? 'news',
          isActive: true,
          dateAdded: DateTime.now(),
          lastUpdated: DateTime.now(),
        );
        _feeds.add(feed);
        
        // Also add to ArticleProvider's web feeds list
        ArticleProvider.addWebFeedStatic(url);
        
        _error = null;
        notifyListeners();
        return true;
      }

      // For development, skip validation or use simpler validation
      bool isValid = true;
      if (!kIsWeb) {
        try {
          isValid = await _rssService.validateFeedUrl(url);
        } catch (e) {
          print('Validation error: $e');
          // For development, allow feed addition even if validation fails
          isValid = true;
        }
      }
      
      if (!isValid) {
        _error = 'Invalid RSS feed URL. Please check the URL and try again.';
        return false;
      }

      // Check if feed already exists
      final existingFeed = await _databaseService.getFeedByUrl(url);
      if (existingFeed != null) {
        _error = 'Feed already exists';
        return false;
      }

      // Fetch feed info using isolate
      final feedInfo = await compute(fetchFeedInfoIsolate, url);
      final feed = feedInfo.copyWith(categoryId: categoryId);

      // Save to database
      await _databaseService.insertFeed(feed);
      _feeds.add(feed);
      _error = null;
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add feed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Update feed
  Future<bool> updateFeed(RSSFeed feed) async {
    _setLoading(true);
    try {
      await _databaseService.updateFeed(feed);
      final index = _feeds.indexWhere((f) => f.id == feed.id);
      if (index != -1) {
        _feeds[index] = feed;
      }
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update feed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Delete feed
  Future<bool> deleteFeed(String feedId) async {
    _setLoading(true);
    try {
      await _databaseService.deleteFeed(feedId);
      _feeds.removeWhere((feed) => feed.id == feedId);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete feed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Delete multiple feeds
  Future<Map<String, int>> deleteFeeds(List<String> feedIds) async {
    _setLoading(true);
    int successCount = 0;
    int failedCount = 0;
    
    try {
      for (final feedId in feedIds) {
        try {
          await _databaseService.deleteFeed(feedId);
          _feeds.removeWhere((feed) => feed.id == feedId);
          successCount++;
        } catch (e) {
          failedCount++;
          print('Failed to delete feed $feedId: $e');
        }
      }
      
      _error = null;
      notifyListeners();
      return {'success': successCount, 'failed': failedCount};
    } catch (e) {
      _error = 'Failed to delete feeds: $e';
      return {'success': successCount, 'failed': failedCount};
    } finally {
      _setLoading(false);
    }
  }

  // Update category for multiple feeds
  Future<Map<String, int>> updateFeedsCategory(List<String> feedIds, String categoryId) async {
    _setLoading(true);
    int successCount = 0;
    int failedCount = 0;
    
    try {
      for (final feedId in feedIds) {
        try {
          final feedIndex = _feeds.indexWhere((f) => f.id == feedId);
          if (feedIndex != -1) {
            final updatedFeed = _feeds[feedIndex].copyWith(categoryId: categoryId);
            await _databaseService.updateFeed(updatedFeed);
            _feeds[feedIndex] = updatedFeed;
            successCount++;
          } else {
            failedCount++;
          }
        } catch (e) {
          failedCount++;
          print('Failed to update feed $feedId: $e');
        }
      }
      
      _error = null;
      notifyListeners();
      return {'success': successCount, 'failed': failedCount};
    } catch (e) {
      _error = 'Failed to update feeds: $e';
      return {'success': successCount, 'failed': failedCount};
    } finally {
      _setLoading(false);
    }
  }

  // Refresh feed
  Future<bool> refreshFeed(String feedId) async {
    _setLoading(true);
    try {
      // Get the feed details and refresh it
      final feed = _feeds.firstWhere((f) => f.id == feedId);

      // Fetch new articles for this feed using isolate
      final articles = await compute(parseRSSFeedIsolate, {'url': feed.url, 'feedId': feedId});

      // Save new articles to database
      if (articles.isNotEmpty) {
        final articlesToSave = articles.map((a) => a.copyWith(feedId: feedId)).toList();
        await _databaseService.insertArticlesBatch(articlesToSave);
      }

      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to refresh feed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Refresh all feeds
  Future<void> refreshAllFeeds() async {
    _setLoading(true);
    try {
      final List<Future<bool>> refreshTasks = [];
      for (final feed in _feeds) {
        refreshTasks.add(refreshFeed(feed.id));
      }
      await Future.wait(refreshTasks);
      _error = null;
    } catch (e) {
      _error = 'Failed to refresh feeds: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Category management
  Future<bool> addCategory(model.Category category) async {
    _setLoading(true);
    try {
      await _databaseService.insertCategory(category);
      _categories.add(category);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add category: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateCategory(model.Category category) async {
    _setLoading(true);
    try {
      await _databaseService.updateCategory(category);
      final index = _categories.indexWhere((c) => c.id == category.id);
      if (index != -1) {
        _categories[index] = category;
      }
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update category: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteCategory(String categoryId) async {
    _setLoading(true);
    try {
      // Check if category has feeds
      final categoryFeeds = getFeedsByCategory(categoryId);
      if (categoryFeeds.isNotEmpty) {
        _error = 'Cannot delete category with feeds';
        return false;
      }

      await _databaseService.deleteCategory(categoryId);
      _categories.removeWhere((category) => category.id == categoryId);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete category: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Get category by ID
  model.Category? getCategoryById(String categoryId) {
    try {
      return _categories.firstWhere((c) => c.id == categoryId);
    } catch (e) {
      return null;
    }
  }

  // Private methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _rssService.dispose();
    super.dispose();
  }
}
