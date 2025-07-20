import 'package:flutter/foundation.dart' hide Category;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/article.dart';
import '../models/rss_feed.dart';
import '../models/category.dart';

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
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('Database operations not supported on web platform');
    }
    
    String path = join(await getDatabasesPath(), 'freead.db');
    return await openDatabase(
      path,
      version: 3,
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
        FOREIGN KEY (feedId) REFERENCES feeds (id),
        FOREIGN KEY (categoryId) REFERENCES categories (id)
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

  Future<int> deleteArticle(String id) async {
    final db = await database;
    return await db.delete('articles', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteOldArticles(int daysOld) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    return await db.delete(
      'articles',
      where: 'publishedDate < ? AND isSaved = 0 AND isStarred = 0',
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }

  // Statistics
  Future<Map<String, int>> getArticleStats() async {
    final db = await database;
    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles');
    final unreadResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE isRead = 0');
    final savedResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE isSaved = 1');
    final starredResult = await db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE isStarred = 1');

    return {
      'total': totalResult.first['count'] as int,
      'unread': unreadResult.first['count'] as int,
      'saved': savedResult.first['count'] as int,
      'starred': starredResult.first['count'] as int,
    };
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
