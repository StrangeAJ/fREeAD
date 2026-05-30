import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../services/database_service.dart';
import '../services/rss_service.dart';
import '../utils/concurrency_utils.dart';

class ArticleProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final RssService _rssService = RssService();

  List<Article> _articles = [];
  List<Article> _savedArticles = [];
  List<Article> _starredArticles = [];
  final Set<String> _loadingFullArticles = {};
  bool _isLoading = false;
  String? _error;

  List<Article> get articles => _articles;
  List<Article> get savedArticles => _savedArticles;
  List<Article> get starredArticles => _starredArticles;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadArticles() async {
    _setLoading(true);
    try {
      _articles = await _databaseService.getAllArticles();
      _savedArticles = await _databaseService.getSavedArticles();
      _starredArticles = await _databaseService.getStarredArticles();
      _error = null;
    } catch (e) {
      _error = 'Failed to load articles: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshAllArticles() async {
    _setLoading(true);
    try {
      final feeds = await _databaseService.getAllFeeds();
      for (final feed in feeds) {
        try {
          final newArticles = await _rssService.fetchFeedArticles(feed.url, feed.id);
          await _databaseService.insertArticlesBatch(newArticles);
        } catch (e) {
          print('Error refreshing feed ${feed.title}: $e');
        }
      }
      await loadArticles();
    } catch (e) {
      _error = 'Failed to refresh articles: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshArticles() async {
    await refreshAllArticles();
  }

  Future<void> markAsRead(String articleId) async {
    try {
      await _databaseService.markArticleAsRead(articleId);
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index != -1) {
        _articles[index] = _articles[index].copyWith(isRead: true);
        notifyListeners();
      }
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> toggleSaved(String articleId) async {
    try {
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index == -1) return;
      
      final article = _articles[index];
      final newStatus = !article.isSaved;
      await _databaseService.markArticleAsSaved(articleId, newStatus);

      _articles[index] = article.copyWith(isSaved: newStatus);
      if (newStatus) {
        _savedArticles.add(_articles[index]);
      } else {
        _savedArticles.removeWhere((a) => a.id == articleId);
      }
      notifyListeners();
    } catch (e) {
      print('Error toggling saved: $e');
    }
  }

  Future<void> toggleStarred(String articleId) async {
    try {
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index == -1) return;

      final article = _articles[index];
      final newStatus = !article.isStarred;
      await _databaseService.markArticleAsStarred(articleId, newStatus);
      
      _articles[index] = article.copyWith(isStarred: newStatus);
      if (newStatus) {
        _starredArticles.add(_articles[index]);
      } else {
        _starredArticles.removeWhere((a) => a.id == articleId);
      }
      notifyListeners();
    } catch (e) {
      print('Error toggling starred: $e');
    }
  }

  Future<void> toggleStar(String articleId) async {
    await toggleStarred(articleId);
  }

  Future<List<Article>> searchArticles(String query) async {
    return await _databaseService.searchArticles(query);
  }

  Future<List<Article>> getArticlesByCategory(String categoryId) async {
    return await _databaseService.getArticlesByCategory(categoryId);
  }

  Future<List<Article>> getArticlesByFeed(String feedId) async {
    return await _databaseService.getArticlesByFeed(feedId);
  }

  bool isLoadingFullArticle(String id) => _loadingFullArticles.contains(id);

  Future<bool> loadFullArticle(String articleId) async {
    final index = _articles.indexWhere((a) => a.id == articleId);
    if (index == -1) return false;

    final article = _articles[index];
    if (article.fullContent != null) return true;

    _loadingFullArticles.add(articleId);
    notifyListeners();

    try {
      final extracted = await compute(extractEnhancedArticleContentIsolate, article.url);
      String? fullContent = extracted?['content'];
      
      if (fullContent == null || fullContent.isEmpty) {
        fullContent = await compute(fetchFullArticleContentIsolate, article.url);
      }

      if (fullContent != null && fullContent.isNotEmpty) {
        final updated = article.copyWith(fullContent: fullContent);
        await _databaseService.updateArticle(updated);
        _articles[index] = updated;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      _loadingFullArticles.remove(articleId);
      notifyListeners();
    }
  }

  Future<void> refreshArticle(String id) async {
    final updated = await _databaseService.getArticleById(id);
    if (updated != null) {
      final index = _articles.indexWhere((a) => a.id == id);
      if (index != -1) {
        _articles[index] = updated;
        notifyListeners();
      }
    }
  }

  Article? getArticleById(String id) {
    try {
      return _articles.firstWhere((a) => a.id == id);
    } catch (e) {
      return null;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}
