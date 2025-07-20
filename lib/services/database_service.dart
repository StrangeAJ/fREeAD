import 'package:flutter/foundation.dart' hide Category;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/article.dart';
import '../models/rss_feed.dart';
import '../models/category.dart';
import '../models/feed_summary.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    if (kIsWeb) {
      // For web, use in-memory database or mock implementation
      throw UnsupportedError('Database operations not supported on web platform');
    }
    
    _database = await _initDatabase();

    // Ensure all required tables exist
    await _ensureTablesExist();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('Database operations not supported on web platform');
    }
    
    String path = join(await getDatabasesPath(), 'freead.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add fullContent column to articles table
      try {
        await db.execute('ALTER TABLE articles ADD COLUMN fullContent TEXT');
        print('Added fullContent column to articles table');
      } catch (e) {
        print('Error adding fullContent column: $e');
        // Column might already exist, continue
      }
    }
    
    if (oldVersion < 3) {
      // Fix any feeds with invalid category IDs
      try {
        await db.execute('''
          UPDATE feeds 
          SET categoryId = 'general' 
          WHERE categoryId NOT IN (
            SELECT id FROM categories
          ) OR categoryId = 'news'
        ''');
        print('Fixed feeds with invalid category IDs');
      } catch (e) {
        print('Error fixing category IDs: $e');
      }
    }

    if (oldVersion < 4) {
      // Add summary column to articles table
      try {
        await db.execute('ALTER TABLE articles ADD COLUMN summary TEXT');
        print('Added summary column to articles table');
      } catch (e) {
        print('Error adding summary column: $e');
        // Column might already exist, continue
      }
    }

    if (oldVersion < 5) {
      // Create feed_summaries table
      try {
        await db.execute('''
          CREATE TABLE feed_summaries (
            id TEXT PRIMARY KEY,
            feedId TEXT NOT NULL,
            summary TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            FOREIGN KEY (feedId) REFERENCES feeds (id)
          )
        ''');
        print('Created feed_summaries table');
      } catch (e) {
        print('Error creating feed_summaries table: $e');
        // Table might already exist, continue
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create categories table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        iconName TEXT,
        color TEXT,
        dateCreated TEXT NOT NULL,
        sortOrder INTEGER DEFAULT 0,
        isDefault INTEGER DEFAULT 0
      )
    ''');

    // Create feeds table
    await db.execute('''
      CREATE TABLE feeds (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL,
        imageUrl TEXT,
        categoryId TEXT,
        dateAdded TEXT NOT NULL,
        lastUpdated TEXT,
        isActive INTEGER DEFAULT 1,
        FOREIGN KEY (categoryId) REFERENCES categories (id)
      )
    ''');

    // Create articles table
    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        content TEXT,
        fullContent TEXT,
        imageUrl TEXT,
        url TEXT NOT NULL,
        author TEXT,
        publishedDate TEXT NOT NULL,
        feedId TEXT NOT NULL,
        categoryId TEXT,
        isRead INTEGER DEFAULT 0,
        isSaved INTEGER DEFAULT 0,
        isStarred INTEGER DEFAULT 0,
        dateAdded TEXT NOT NULL,
        summary TEXT,
        FOREIGN KEY (feedId) REFERENCES feeds (id),
        FOREIGN KEY (categoryId) REFERENCES categories (id)
      )
    ''');

    // Create feed_summaries table
    await db.execute('''
      CREATE TABLE feed_summaries (
        id TEXT PRIMARY KEY,
        feedId TEXT NOT NULL,
        summary TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (feedId) REFERENCES feeds (id)
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_articles_feedId ON articles(feedId)');
    await db.execute('CREATE INDEX idx_articles_categoryId ON articles(categoryId)');
    await db.execute('CREATE INDEX idx_articles_publishedDate ON articles(publishedDate)');
    await db.execute('CREATE INDEX idx_articles_isRead ON articles(isRead)');
    await db.execute('CREATE INDEX idx_articles_isSaved ON articles(isSaved)');
    await db.execute('CREATE INDEX idx_articles_isStarred ON articles(isStarred)');

    // Insert default categories
    for (final category in Category.defaultCategories) {
      await db.insert('categories', category.toJson());
    }
  }

  // Ensure all required tables exist (for backward compatibility)
  Future<void> _ensureTablesExist() async {
    final db = _database!;

    // Check if feed_summaries table exists
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='feed_summaries'"
    );

    if (result.isEmpty) {
      // Create feed_summaries table if it doesn't exist
      try {
        await db.execute('''
          CREATE TABLE feed_summaries (
            id TEXT PRIMARY KEY,
            feedId TEXT NOT NULL,
            summary TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            FOREIGN KEY (feedId) REFERENCES feeds (id)
          )
        ''');
        print('Created missing feed_summaries table');
      } catch (e) {
        print('Error creating feed_summaries table: $e');
      }
    }
  }

  // Category operations
  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      orderBy: 'sortOrder ASC, name ASC',
    );
    return List.generate(maps.length, (i) => Category.fromJson(maps[i]));
  }

  Future<Category?> getCategoryById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty ? Category.fromJson(maps.first) : null;
  }

  Future<int> insertCategory(Category category) async {
    final db = await database;
    return await db.insert('categories', category.toJson());
  }

  Future<int> updateCategory(Category category) async {
    final db = await database;
    return await db.update(
      'categories',
      category.toJson(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(String id) async {
    final db = await database;
    return await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Feed operations
  Future<List<RSSFeed>> getAllFeeds() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feeds',
      orderBy: 'title ASC',
    );
    return List.generate(maps.length, (i) => RSSFeed.fromJson(maps[i]));
  }

  // Alias for getAllFeeds for backward compatibility
  Future<List<RSSFeed>> getFeeds() async {
    return getAllFeeds();
  }

  // Insert multiple articles in a batch for performance, ignoring duplicates
  Future<void> insertArticlesBatch(List<Article> articles) async {
    final db = await database;
    final batch = db.batch();
    for (final article in articles) {
      batch.insert(
        'articles',
        article.toJson(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<RSSFeed>> getFeedsByCategory(String categoryId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feeds',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: 'title ASC',
    );
    return List.generate(maps.length, (i) => RSSFeed.fromJson(maps[i]));
  }

  Future<RSSFeed?> getFeedById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feeds',
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty ? RSSFeed.fromJson(maps.first) : null;
  }

  Future<RSSFeed?> getFeedByUrl(String url) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feeds',
      where: 'url = ?',
      whereArgs: [url],
    );
    return maps.isNotEmpty ? RSSFeed.fromJson(maps.first) : null;
  }

  Future<int> insertFeed(RSSFeed feed) async {
    final db = await database;
    return await db.insert('feeds', feed.toJson());
  }

  Future<int> updateFeed(RSSFeed feed) async {
    final db = await database;
    return await db.update(
      'feeds',
      feed.toJson(),
      where: 'id = ?',
      whereArgs: [feed.id],
    );
  }

  Future<int> deleteFeed(String id) async {
    final db = await database;
    // Delete associated articles first
    await db.delete('articles', where: 'feedId = ?', whereArgs: [id]);
    return await db.delete('feeds', where: 'id = ?', whereArgs: [id]);
  }

  // Article operations
  Future<List<Article>> getAllArticles({
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      orderBy: orderBy ?? 'publishedDate DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Search operations
  Future<List<Article>> searchArticles(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'title LIKE ? OR description LIKE ? OR content LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Get starred articles
  Future<List<Article>> getStarredArticles() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'isStarred = ?',
      whereArgs: [1],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Get saved articles
  Future<List<Article>> getSavedArticles() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'isSaved = ?',
      whereArgs: [1],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Get unread articles
  Future<List<Article>> getUnreadArticles() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'isRead = ?',
      whereArgs: [0],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Get recent articles (within specified days)
  Future<List<Article>> getRecentArticles(int days) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'publishedDate >= ?',
      whereArgs: [cutoffDate.toIso8601String()],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Get articles by feed
  Future<List<Article>> getArticlesByFeed(String feedId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'feedId = ?',
      whereArgs: [feedId],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  // Get articles by category
  Future<List<Article>> getArticlesByCategory(String categoryId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

  Future<Article?> getArticleById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty ? Article.fromJson(maps.first) : null;
  }

  Future<int> insertArticle(Article article) async {
    final db = await database;
    return await db.insert('articles', article.toJson());
  }

  // Alias for insertArticle for backward compatibility
  Future<int> saveArticle(Article article) async {
    return await insertArticle(article);
  }

  Future<int> updateArticle(Article article) async {
    final db = await database;
    return await db.update(
      'articles',
      article.toJson(),
      where: 'id = ?',
      whereArgs: [article.id],
    );
  }

  Future<int> markArticleAsRead(String articleId) async {
    final db = await database;
    return await db.update(
      'articles',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<int> markArticleAsSaved(String articleId, bool isSaved) async {
    final db = await database;
    return await db.update(
      'articles',
      {'isSaved': isSaved ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<int> markArticleAsStarred(String articleId, bool isStarred) async {
    final db = await database;
    return await db.update(
      'articles',
      {'isStarred': isStarred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<int> updateArticleSummary(String articleId, String summary) async {
    final db = await database;
    return await db.update(
      'articles',
      {'summary': summary},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // Feed Summary operations
  Future<FeedSummary?> getFeedSummary(String feedId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feed_summaries',
      where: 'feedId = ?',
      whereArgs: [feedId],
      orderBy: 'updatedAt DESC',
      limit: 1,
    );
    return maps.isNotEmpty ? FeedSummary.fromJson(maps.first) : null;
  }

  Future<int> saveFeedSummary(String feedId, String summary) async {
    final db = await database;
    final now = DateTime.now();
    final existingSummary = await getFeedSummary(feedId);

    if (existingSummary != null) {
      // Update existing summary
      return await db.update(
        'feed_summaries',
        {
          'summary': summary,
          'updatedAt': now.toIso8601String(),
        },
        where: 'feedId = ?',
        whereArgs: [feedId],
      );
    } else {
      // Insert new summary
      final feedSummary = FeedSummary(
        id: '${feedId}_${now.millisecondsSinceEpoch}',
        feedId: feedId,
        summary: summary,
        createdAt: now,
        updatedAt: now,
      );
      return await db.insert('feed_summaries', feedSummary.toJson());
    }
  }

  Future<int> deleteFeedSummary(String feedId) async {
    final db = await database;
    return await db.delete(
      'feed_summaries',
      where: 'feedId = ?',
      whereArgs: [feedId],
    );
  }

  // Delete a single article
  Future<int> deleteArticle(String articleId) async {
    final db = await database;
    return await db.delete(
      'articles',
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // Delete old articles older than specified days
  Future<int> deleteOldArticles(int daysOld) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    return await db.delete(
      'articles',
      where: 'publishedDate < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }

  // Get article statistics
  Future<Map<String, int>> getArticleStats() async {
    final db = await database;

    // Get total count
    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles');
    final totalCount = totalResult.first['count'] as int;

    // Get unread count
    final unreadResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE isRead = 0');
    final unreadCount = unreadResult.first['count'] as int;

    // Get saved count
    final savedResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE isSaved = 1');
    final savedCount = savedResult.first['count'] as int;

    // Get starred count
    final starredResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE isStarred = 1');
    final starredCount = starredResult.first['count'] as int;

    return {
      'total': totalCount,
      'unread': unreadCount,
      'saved': savedCount,
      'starred': starredCount,
    };
  }
}
