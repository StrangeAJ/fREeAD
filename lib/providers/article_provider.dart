import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../models/rss_feed.dart';
import '../services/database_service.dart';
import '../services/rss_service.dart';
import '../services/full_article_service.dart';
import '../services/enhanced_article_service.dart';

class ArticleProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final RSSService _rssService = RSSService();
  final FullArticleService _fullArticleService = FullArticleService();
  final EnhancedArticleService _enhancedArticleService = EnhancedArticleService();

  List<Article> _articles = [];
  List<Article> _savedArticles = [];
  List<Article> _starredArticles = [];
  bool _isLoading = false;
  String? _error;
  String _currentFilter = 'all';
  
  // Track loading state for full articles
  final Set<String> _loadingFullArticles = {};
  
  // For web platform, store feeds in memory
  static List<String> _webFeeds = [];

  // Getters
  List<Article> get articles => _articles;
  List<Article> get savedArticles => _savedArticles;
  List<Article> get starredArticles => _starredArticles;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentFilter => _currentFilter;
  
  // Check if a full article is being loaded
  bool isLoadingFullArticle(String articleId) {
    return _loadingFullArticles.contains(articleId);
  }
  
  // Add feed for web platform
  void addWebFeed(String url) {
    if (!_webFeeds.contains(url)) {
      _webFeeds.add(url);
    }
  }
  
  // Static method to add web feed
  static void addWebFeedStatic(String url) {
    if (!_webFeeds.contains(url)) {
      _webFeeds.add(url);
    }
  }

  // Load all articles
  Future<void> loadArticles() async {
    _setLoading(true);
    try {
      if (kIsWeb) {
        // For web, use sample data
        _articles = [
          Article(
            id: 'sample-1',
            title: 'Sample Article',
            description: 'This is a sample article for web demo.',
            content: 'This is a sample article for web demo.',
            url: 'https://example.com/article',
            feedId: 'sample-1',
            publishedDate: DateTime.now().subtract(Duration(hours: 2)),
            author: 'Sample Author',
            isRead: false,
            isStarred: false,
            isSaved: false,
            imageUrl: null,
            dateAdded: DateTime.now(),
          ),
          Article(
            id: 'sample-2',
            title: 'Another Sample Article',
            description: 'This is another sample article for web demo.',
            content: 'This is another sample article for web demo.',
            url: 'https://example.com/article2',
            feedId: 'sample-1',
            publishedDate: DateTime.now().subtract(Duration(hours: 5)),
            author: 'Another Author',
            isRead: false,
            isStarred: true,
            isSaved: false,
            imageUrl: null,
            dateAdded: DateTime.now(),
          ),
        ];
        _savedArticles = _articles.where((a) => a.isSaved).toList();
        _starredArticles = _articles.where((a) => a.isStarred).toList();
      } else {
        _articles = await _databaseService.getAllArticles();
        _savedArticles = await _databaseService.getSavedArticles();
        _starredArticles = await _databaseService.getStarredArticles();
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load articles: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Get articles by feed
  Future<List<Article>> getArticlesByFeed(String feedId) async {
    try {
      return await _databaseService.getArticlesByFeed(feedId);
    } catch (e) {
      _error = 'Failed to load articles for feed: $e';
      return [];
    }
  }

  // Get articles by category
  Future<List<Article>> getArticlesByCategory(String categoryId) async {
    try {
      return await _databaseService.getArticlesByCategory(categoryId);
    } catch (e) {
      _error = 'Failed to load articles for category: $e';
      return [];
    }
  }

  // Get unread articles
  Future<List<Article>> getUnreadArticles() async {
    try {
      return await _databaseService.getUnreadArticles();
    } catch (e) {
      _error = 'Failed to load unread articles: $e';
      return [];
    }
  }

  // Filter articles
  List<Article> getFilteredArticles() {
    switch (_currentFilter) {
      case 'unread':
        return _articles.where((article) => !article.isRead).toList();
      case 'saved':
        return _savedArticles;
      case 'starred':
        return _starredArticles;
      default:
        return _articles;
    }
  }

  // Set filter
  void setFilter(String filter) {
    _currentFilter = filter;
    notifyListeners();
  }

  // Refresh articles for a feed
  Future<void> refreshFeedArticles(String feedId, String feedUrl) async {
    _setLoading(true);
    try {
      final newArticles = await _rssService.parseRSSFeed(feedUrl, feedId);
      
      // Insert new articles
      for (final article in newArticles) {
        final existingArticle = await _databaseService.getArticleById(article.id);
        if (existingArticle == null) {
          await _databaseService.insertArticle(article);
        }
      }
      
      // Reload articles
      await loadArticles();
      _error = null;
    } catch (e) {
      _error = 'Failed to refresh articles: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Refresh all articles
  Future<void> refreshAllArticles() async {
    _setLoading(true);
    try {
      if (kIsWeb) {
        print('Refreshing articles for web platform');
        
        // For web, use sample feeds plus user-added feeds
        final sampleFeeds = [
          'https://feeds.bbci.co.uk/news/rss.xml',
          'http://rss.cnn.com/rss/edition.rss',
          'https://www.nasa.gov/rss/dyn/mission_pages/kepler/news/news.rss',
        ];
        
        final allFeeds = [...sampleFeeds, ..._webFeeds];
        print('Processing ${allFeeds.length} feeds: $allFeeds');
        
        List<Article> newArticles = [];
        
        for (final feedUrl in allFeeds) {
          try {
            print('Fetching articles from: $feedUrl');
            final articles = await _rssService.parseRSSFeed(feedUrl, 'feed_${allFeeds.indexOf(feedUrl)}');
            print('Got ${articles.length} articles from $feedUrl');
            newArticles.addAll(articles);
          } catch (e) {
            print('Error parsing feed $feedUrl: $e');
          }
        }
        
        // Sort articles by published date (newest first)
        newArticles.sort((a, b) => b.publishedDate.compareTo(a.publishedDate));
        
        print('Total articles loaded: ${newArticles.length}');
        
        // Update the articles list
        _articles = newArticles;
        _savedArticles = _articles.where((a) => a.isSaved).toList();
        _starredArticles = _articles.where((a) => a.isStarred).toList();
        notifyListeners();
        _error = null;
        return;
      }

      // Get all feeds from database
      final feeds = await _databaseService.getAllFeeds();
      
      print('Found ${feeds.length} feeds in database');
      
      // If no feeds in database, add some default ones
      if (feeds.isEmpty) {
        print('No feeds found, adding default feeds...');
        await _addDefaultFeeds();
      }
      
      // Get updated feeds list
      final updatedFeeds = await _databaseService.getAllFeeds();
      
      List<Article> newArticles = [];
      
      for (final feed in updatedFeeds) {
        if (feed.isActive) {
          print('Refreshing feed: ${feed.title} (${feed.url})');
          try {
            final articles = await _rssService.parseRSSFeed(feed.url, feed.id);
            print('Got ${articles.length} articles from ${feed.title}');
            
            // Save articles to database
            for (final article in articles) {
              try {
                await _databaseService.insertArticle(article);
              } catch (e) {
                // Article might already exist, that's ok
                print('Article already exists: ${article.title}');
              }
            }
            
            newArticles.addAll(articles);
          } catch (e) {
            print('Error refreshing feed ${feed.title}: $e');
          }
        }
      }
      
      // Load all articles from database
      _articles = await _databaseService.getAllArticles();
      _savedArticles = await _databaseService.getSavedArticles();
      _starredArticles = await _databaseService.getStarredArticles();
      
      print('Total articles loaded: ${_articles.length}');
      
      _error = null;
    } catch (e) {
      print('Error in refreshAllArticles: $e');
      _error = 'Failed to refresh all articles: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Add default feeds for initial setup
  Future<void> _addDefaultFeeds() async {
    final defaultFeeds = [
      {
        'url': 'https://feeds.bbci.co.uk/news/rss.xml',
        'title': 'BBC News',
        'description': 'Latest news from BBC',
        'categoryId': 'news',
      },
      {
        'url': 'https://rss.cnn.com/rss/edition.rss',
        'title': 'CNN',
        'description': 'Latest news from CNN',
        'categoryId': 'news',
      },
      {
        'url': 'https://feeds.npr.org/1001/rss.xml',
        'title': 'NPR News',
        'description': 'Latest news from NPR',
        'categoryId': 'news',
      },
    ];

    for (final feedData in defaultFeeds) {
      try {
        // Check if feed already exists
        final existingFeed = await _databaseService.getFeedByUrl(feedData['url']!);
        if (existingFeed == null) {
          final feed = RSSFeed(
            id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + feedData['url'].hashCode.toString(),
            title: feedData['title']!,
            url: feedData['url']!,
            description: feedData['description']!,
            categoryId: feedData['categoryId']!,
            isActive: true,
            dateAdded: DateTime.now(),
            lastUpdated: DateTime.now(),
          );
          
          await _databaseService.insertFeed(feed);
          print('Added default feed: ${feed.title}');
        }
      } catch (e) {
        print('Error adding default feed ${feedData['title']}: $e');
      }
    }
  }

  // Mark article as read
  Future<bool> markAsRead(String articleId) async {
    try {
      await _databaseService.markArticleAsRead(articleId);
      
      // Update local state
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index != -1) {
        _articles[index] = _articles[index].copyWith(isRead: true);
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to mark article as read: $e';
      return false;
    }
  }

  // Toggle saved status
  Future<bool> toggleSaved(String articleId) async {
    try {
      final article = _articles.firstWhere((a) => a.id == articleId);
      final newSavedStatus = !article.isSaved;
      
      await _databaseService.markArticleAsSaved(articleId, newSavedStatus);
      
      // Update local state
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index != -1) {
        _articles[index] = _articles[index].copyWith(isSaved: newSavedStatus);
      }
      
      // Update saved articles list
      if (newSavedStatus) {
        _savedArticles.add(_articles[index]);
      } else {
        _savedArticles.removeWhere((a) => a.id == articleId);
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to toggle saved status: $e';
      return false;
    }
  }

  // Toggle starred status
  Future<bool> toggleStarred(String articleId) async {
    try {
      final article = _articles.firstWhere((a) => a.id == articleId);
      final newStarredStatus = !article.isStarred;
      
      await _databaseService.markArticleAsStarred(articleId, newStarredStatus);
      
      // Update local state
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index != -1) {
        _articles[index] = _articles[index].copyWith(isStarred: newStarredStatus);
      }
      
      // Update starred articles list
      if (newStarredStatus) {
        _starredArticles.add(_articles[index]);
      } else {
        _starredArticles.removeWhere((a) => a.id == articleId);
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to toggle starred status: $e';
      return false;
    }
  }

  // Search articles
  Future<List<Article>> searchArticles(String query) async {
    try {
      return await _databaseService.searchArticles(query);
    } catch (e) {
      _error = 'Failed to search articles: $e';
      return [];
    }
  }

  // Delete article
  Future<bool> deleteArticle(String articleId) async {
    try {
      await _databaseService.deleteArticle(articleId);
      
      // Remove from local state
      _articles.removeWhere((a) => a.id == articleId);
      _savedArticles.removeWhere((a) => a.id == articleId);
      _starredArticles.removeWhere((a) => a.id == articleId);
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete article: $e';
      return false;
    }
  }

  // Clean up old articles
  Future<void> cleanupOldArticles({int daysOld = 30}) async {
    try {
      await _databaseService.deleteOldArticles(daysOld);
      await loadArticles();
    } catch (e) {
      _error = 'Failed to cleanup old articles: $e';
    }
  }

  // Get article statistics
  Future<Map<String, int>> getArticleStats() async {
    try {
      return await _databaseService.getArticleStats();
    } catch (e) {
      _error = 'Failed to get article statistics: $e';
      return {};
    }
  }

  // Get article by ID
  Article? getArticleById(String articleId) {
    try {
      return _articles.firstWhere((a) => a.id == articleId);
    } catch (e) {
      return null;
    }
  }

  // Load full article content
  Future<bool> loadFullArticle(String articleId) async {
    try {
      final article = getArticleById(articleId);
      if (article == null) {
        _error = 'Article not found';
        return false;
      }

      // If already has full content, return success
      if (article.fullContent != null && article.fullContent!.isNotEmpty) {
        return true;
      }

      // Mark as loading
      _loadingFullArticles.add(articleId);
      notifyListeners();

      // Fetch full article content using enhanced service first
      Map<String, dynamic>? extractedContent;
      String? fullContent;
      
      try {
        print('Trying enhanced article extraction for: ${article.url}');
        extractedContent = await _enhancedArticleService.extractArticleContent(article.url);
        
        if (extractedContent != null && extractedContent['content'] != null) {
          fullContent = extractedContent['content'];
          print('Enhanced extraction successful. Content length: ${fullContent?.length}');
        } else {
          print('Enhanced extraction failed, falling back to original service');
          fullContent = await _fullArticleService.fetchFullArticleContent(article.url);
        }
      } catch (e) {
        print('Enhanced extraction error: $e, falling back to original service');
        fullContent = await _fullArticleService.fetchFullArticleContent(article.url);
      }
      
      // Remove from loading set
      _loadingFullArticles.remove(articleId);
      
      if (fullContent != null && fullContent.isNotEmpty) {
        // Update article with full content
        final updatedArticle = article.copyWith(fullContent: fullContent);
        
        // Update in lists
        final index = _articles.indexWhere((a) => a.id == articleId);
        if (index != -1) {
          _articles[index] = updatedArticle;
        }
        
        // Update in saved articles if applicable
        final savedIndex = _savedArticles.indexWhere((a) => a.id == articleId);
        if (savedIndex != -1) {
          _savedArticles[savedIndex] = updatedArticle;
        }
        
        // Update in starred articles if applicable
        final starredIndex = _starredArticles.indexWhere((a) => a.id == articleId);
        if (starredIndex != -1) {
          _starredArticles[starredIndex] = updatedArticle;
        }
        
        notifyListeners();
        return true;
      } else {
        _error = 'Failed to load full article content';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _loadingFullArticles.remove(articleId);
      _error = 'Failed to load full article: $e';
      notifyListeners();
      return false;
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
