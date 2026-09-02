import 'package:flutter/foundation.dart' hide Category;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/article.dart';
import '../models/rss_feed.dart';
import '../models/category.dart';
import '../models/chat_message.dart';
import '../models/feed_summary.dart';
import '../utils/app_logger.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  /// Current schema version.
  static const int schemaVersion = 7;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (kIsWeb) {
      // For web, use in-memory database or mock implementation
      throw UnsupportedError(
        'Database operations not supported on web platform',
      );
    }

    _database = await _initDatabase();

    // Make sure everything the app expects exists, even on databases that were
    // upgraded through older, partially failing migrations.
    await _ensureSchema();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Database operations not supported on web platform',
      );
    }

    String path = join(await getDatabasesPath(), 'freead.db');
    return await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _tryExecute(db, 'ALTER TABLE articles ADD COLUMN fullContent TEXT');
    }

    if (oldVersion < 3) {
      // Fix any feeds with invalid category IDs
      await _tryExecute(db, '''
          UPDATE feeds
          SET categoryId = 'general'
          WHERE categoryId NOT IN (SELECT id FROM categories)
        ''');
    }

    if (oldVersion < 4) {
      await _tryExecute(db, 'ALTER TABLE articles ADD COLUMN summary TEXT');
    }

    if (oldVersion < 5) {
      await _tryExecute(db, _createFeedSummariesSql);
    }

    if (oldVersion < 6) {
      await _tryExecute(db, _createHighlightsSql);
      await _tryExecute(db, _createNotesSql);
    }

    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
  }

  Future<void> _migrateToV7(Database db) async {
    AppLog.i('Migrating database to v7');

    await _ensureColumns(db, 'articles', _articleColumnsV7);
    await _ensureColumns(db, 'feeds', _feedColumnsV7);

    await _tryExecute(db, _createChatsSql);

    for (final sql in _indexStatements) {
      await _tryExecute(db, sql);
    }

    // Categories added in v3 of the product need to exist on old databases.
    await _insertMissingCategories(db);

    // Articles never had a category; inherit it from their feed.
    await _tryExecute(db, '''
        UPDATE articles
        SET categoryId = (
          SELECT categoryId FROM feeds WHERE feeds.id = articles.feedId
        )
        WHERE categoryId IS NULL
      ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_createCategoriesSql);
    await db.execute(_createFeedsSql);
    await db.execute(_createArticlesSql);
    await db.execute(_createFeedSummariesSql);
    await db.execute(_createHighlightsSql);
    await db.execute(_createNotesSql);
    await db.execute(_createChatsSql);

    for (final sql in _indexStatements) {
      await _tryExecute(db, sql);
    }

    for (final category in Category.defaultCategories) {
      await db.insert(
        'categories',
        category.toJson(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Idempotent guard that runs on every open: creates anything missing and
  /// back-fills default categories.
  Future<void> _ensureSchema() async {
    final db = _database!;

    await _tryExecute(
      db,
      _createCategoriesSql.replaceFirst(
        'CREATE TABLE',
        'CREATE TABLE IF NOT EXISTS',
      ),
    );
    await _tryExecute(
      db,
      _createFeedsSql.replaceFirst(
        'CREATE TABLE',
        'CREATE TABLE IF NOT EXISTS',
      ),
    );
    await _tryExecute(
      db,
      _createArticlesSql.replaceFirst(
        'CREATE TABLE',
        'CREATE TABLE IF NOT EXISTS',
      ),
    );
    await _tryExecute(db, _createFeedSummariesSql);
    await _tryExecute(db, _createHighlightsSql);
    await _tryExecute(db, _createNotesSql);
    await _tryExecute(db, _createChatsSql);

    // Repair databases where an earlier migration only partly applied.
    await _ensureColumns(db, 'articles', _articleColumnsV7);
    await _ensureColumns(db, 'feeds', _feedColumnsV7);

    for (final sql in _indexStatements) {
      await _tryExecute(db, sql);
    }

    await _insertMissingCategories(db);
  }

  /// Adds any of [columns] that [table] is missing.
  Future<void> _ensureColumns(
    DatabaseExecutor db,
    String table,
    Map<String, String> columns,
  ) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (info.isEmpty) return;
      final existing = info.map((row) => row['name'] as String).toSet();
      for (final entry in columns.entries) {
        if (existing.contains(entry.key)) continue;
        AppLog.i('Adding missing column $table.${entry.key}');
        await _tryExecute(
          db,
          'ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    } catch (e) {
      AppLog.w('Could not inspect $table', e);
    }
  }

  static const Map<String, String> _articleColumnsV7 = <String, String>{
    'fullContent': 'TEXT',
    'summary': 'TEXT',
    'extractedTitle': 'TEXT',
    'siteName': 'TEXT',
    'fullContentSource': 'TEXT',
    'fullContentFetchedAt': 'TEXT',
    'scrollProgress': 'REAL DEFAULT 0',
    'readAt': 'TEXT',
  };

  static const Map<String, String> _feedColumnsV7 = <String, String>{
    'siteUrl': 'TEXT',
    'lastFetchedAt': 'TEXT',
    'lastError': 'TEXT',
    'language': 'TEXT',
  };

  Future<void> _insertMissingCategories(DatabaseExecutor db) async {
    for (final category in Category.defaultCategories) {
      try {
        await db.insert(
          'categories',
          category.toJson(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (e) {
        AppLog.w('Could not insert default category ${category.id}', e);
      }
    }
  }

  Future<void> _tryExecute(DatabaseExecutor db, String sql) async {
    try {
      await db.execute(sql);
    } catch (e) {
      // Column/table/index already exists, or the table is missing on a very
      // old database - both are safe to ignore.
      AppLog.d('Schema statement skipped: ${e.toString().split('\n').first}');
    }
  }

  /// Public entry point so providers can guarantee the default set exists.
  Future<void> ensureDefaultCategories() async {
    final db = await database;
    await _insertMissingCategories(db);
  }

  static const String _createCategoriesSql = '''
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
    ''';

  static const String _createFeedsSql = '''
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
        siteUrl TEXT,
        lastFetchedAt TEXT,
        lastError TEXT,
        language TEXT
      )
    ''';

  static const String _createArticlesSql = '''
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
        extractedTitle TEXT,
        siteName TEXT,
        fullContentSource TEXT,
        fullContentFetchedAt TEXT,
        scrollProgress REAL DEFAULT 0,
        readAt TEXT
      )
    ''';

  static const String _createFeedSummariesSql = '''
      CREATE TABLE IF NOT EXISTS feed_summaries (
        id TEXT PRIMARY KEY,
        feedId TEXT NOT NULL,
        summary TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''';

  static const String _createHighlightsSql = '''
      CREATE TABLE IF NOT EXISTS article_highlights (
        id TEXT PRIMARY KEY,
        articleId TEXT NOT NULL,
        selectedText TEXT NOT NULL,
        startIndex INTEGER NOT NULL,
        endIndex INTEGER NOT NULL,
        color TEXT NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''';

  static const String _createNotesSql = '''
      CREATE TABLE IF NOT EXISTS article_notes (
        id TEXT PRIMARY KEY,
        articleId TEXT NOT NULL,
        content TEXT NOT NULL,
        position INTEGER,
        highlightId TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''';

  static const String _createChatsSql = '''
      CREATE TABLE IF NOT EXISTS article_chats (
        id TEXT PRIMARY KEY,
        articleId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''';

  static const List<String> _indexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_articles_feedId ON articles(feedId)',
    'CREATE INDEX IF NOT EXISTS idx_articles_categoryId ON articles(categoryId)',
    'CREATE INDEX IF NOT EXISTS idx_articles_publishedDate ON articles(publishedDate)',
    'CREATE INDEX IF NOT EXISTS idx_articles_isRead ON articles(isRead)',
    'CREATE INDEX IF NOT EXISTS idx_articles_isSaved ON articles(isSaved)',
    'CREATE INDEX IF NOT EXISTS idx_articles_isStarred ON articles(isStarred)',
    'CREATE INDEX IF NOT EXISTS idx_articles_read_date ON articles(isRead, publishedDate)',
    'CREATE INDEX IF NOT EXISTS idx_feeds_category ON feeds(categoryId)',
    'CREATE INDEX IF NOT EXISTS idx_chats_article ON article_chats(articleId)',
  ];

  // ---------------------------------------------------------------------------
  // Category operations
  // ---------------------------------------------------------------------------

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
    return await db.insert(
      'categories',
      category.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Feed operations
  // ---------------------------------------------------------------------------

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

  /// Records the outcome of a refresh for a feed.
  Future<int> updateFeedStatus(
    String feedId, {
    DateTime? lastFetchedAt,
    String? lastError,
    bool clearError = false,
  }) async {
    final db = await database;
    final values = <String, Object?>{};
    if (lastFetchedAt != null) {
      values['lastFetchedAt'] = lastFetchedAt.toIso8601String();
      values['lastUpdated'] = lastFetchedAt.toIso8601String();
    }
    if (clearError) {
      values['lastError'] = null;
    } else if (lastError != null) {
      values['lastError'] = lastError;
    }
    if (values.isEmpty) return 0;
    return await db.update(
      'feeds',
      values,
      where: 'id = ?',
      whereArgs: [feedId],
    );
  }

  Future<int> deleteFeed(String id) async {
    final db = await database;
    return await db.transaction((txn) async {
      // Get all article IDs for this feed so we can clean up annotations
      final articleRows = await txn.query(
        'articles',
        columns: ['id'],
        where: 'feedId = ?',
        whereArgs: [id],
      );
      final articleIds = articleRows.map((r) => r['id'] as String).toList();

      // Delete highlights, notes and chats for each article
      if (articleIds.isNotEmpty) {
        final placeholders = List.filled(articleIds.length, '?').join(', ');
        await txn.delete(
          'article_notes',
          where: 'articleId IN ($placeholders)',
          whereArgs: articleIds,
        );
        await txn.delete(
          'article_highlights',
          where: 'articleId IN ($placeholders)',
          whereArgs: articleIds,
        );
        await txn.delete(
          'article_chats',
          where: 'articleId IN ($placeholders)',
          whereArgs: articleIds,
        );
      }

      // Delete feed summaries
      await txn.delete('feed_summaries', where: 'feedId = ?', whereArgs: [id]);

      // Delete articles
      await txn.delete('articles', where: 'feedId = ?', whereArgs: [id]);

      // Delete the feed itself
      return await txn.delete('feeds', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // Article operations
  // ---------------------------------------------------------------------------

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

  /// Full-text-ish search across title, description, content and fullContent.
  Future<List<Article>> searchArticles(String query) async {
    final db = await database;
    final like = '%$query%';
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where:
          'title LIKE ? OR description LIKE ? OR content LIKE ? OR fullContent LIKE ?',
      whereArgs: [like, like, like, like],
      orderBy: 'publishedDate DESC',
    );
    return List.generate(maps.length, (i) => Article.fromJson(maps[i]));
  }

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

  /// Inserts articles, ignoring duplicates.
  ///
  /// Returns the number of rows that were actually new, so callers can report
  /// "12 new articles".
  Future<int> insertArticlesBatch(List<Article> articles) async {
    if (articles.isEmpty) return 0;
    final db = await database;
    return await db.transaction<int>((txn) async {
      final before =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM articles'),
          ) ??
          0;

      final batch = txn.batch();
      for (final article in articles) {
        batch.insert(
          'articles',
          article.toJson(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);

      final after =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM articles'),
          ) ??
          0;
      final added = after - before;
      return added < 0 ? 0 : added;
    });
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
      {'isRead': 1, 'readAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<int> markArticleAsUnread(String articleId) async {
    final db = await database;
    return await db.update(
      'articles',
      {'isRead': 0, 'readAt': null},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Marks every article read, optionally limited to a feed or a category.
  /// Returns the number of rows changed.
  Future<int> markAllAsRead({String? feedId, String? categoryId}) async {
    final db = await database;
    final where = <String>['isRead = 0'];
    final args = <Object?>[];
    if (feedId != null) {
      where.add('feedId = ?');
      args.add(feedId);
    }
    if (categoryId != null) {
      where.add('categoryId = ?');
      args.add(categoryId);
    }
    return await db.update(
      'articles',
      {'isRead': 1, 'readAt': DateTime.now().toIso8601String()},
      where: where.join(' AND '),
      whereArgs: args,
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

  /// Keeps `articles.categoryId` in sync when a feed moves category.
  Future<int> updateArticleCategoryForFeed(
    String feedId,
    String? categoryId,
  ) async {
    final db = await database;
    return await db.update(
      'articles',
      {'categoryId': categoryId},
      where: 'feedId = ?',
      whereArgs: [feedId],
    );
  }

  Future<int> updateScrollProgress(String articleId, double progress) async {
    final db = await database;
    final clamped = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return await db.update(
      'articles',
      {'scrollProgress': clamped},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Drops cached full article bodies - for one article or all of them.
  Future<int> clearFullContent({String? articleId}) async {
    final db = await database;
    return await db.update(
      'articles',
      {
        'fullContent': null,
        'fullContentSource': null,
        'fullContentFetchedAt': null,
      },
      where: articleId != null ? 'id = ?' : 'fullContent IS NOT NULL',
      whereArgs: articleId != null ? [articleId] : null,
    );
  }

  Future<Map<String, int>> getUnreadCountsByFeed() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT feedId, COUNT(*) AS c FROM articles WHERE isRead = 0 GROUP BY feedId',
    );
    return {
      for (final row in rows)
        if (row['feedId'] != null)
          row['feedId'] as String: (row['c'] as num).toInt(),
    };
  }

  Future<Map<String, int>> getUnreadCountsByCategory() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT categoryId, COUNT(*) AS c FROM articles WHERE isRead = 0 '
      'AND categoryId IS NOT NULL GROUP BY categoryId',
    );
    return {
      for (final row in rows)
        row['categoryId'] as String: (row['c'] as num).toInt(),
    };
  }

  Future<int> deleteArticle(String articleId) async {
    final db = await database;
    return await db.delete('articles', where: 'id = ?', whereArgs: [articleId]);
  }

  /// Deletes articles older than [daysOld]. Saved and starred articles are
  /// kept by default.
  Future<int> deleteOldArticles(
    int daysOld, {
    bool keepSavedAndStarred = true,
  }) async {
    if (daysOld <= 0) return 0;
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    final where = StringBuffer('publishedDate < ?');
    if (keepSavedAndStarred) {
      where.write(' AND isSaved = 0 AND isStarred = 0');
    }
    return await db.delete(
      'articles',
      where: where.toString(),
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }

  // ---------------------------------------------------------------------------
  // Feed summary operations
  // ---------------------------------------------------------------------------

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
      return await db.update(
        'feed_summaries',
        {'summary': summary, 'updatedAt': now.toIso8601String()},
        where: 'feedId = ?',
        whereArgs: [feedId],
      );
    } else {
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

  // ---------------------------------------------------------------------------
  // Article chat ("Ask AI") operations
  // ---------------------------------------------------------------------------

  Future<List<ChatMessage>> getArticleChat(String articleId) async {
    final db = await database;
    final maps = await db.query(
      'article_chats',
      where: 'articleId = ?',
      whereArgs: [articleId],
      orderBy: 'createdAt ASC',
    );
    return List.generate(maps.length, (i) => ChatMessage.fromJson(maps[i]));
  }

  Future<int> insertChatMessage(ChatMessage message) async {
    final db = await database;
    return await db.insert(
      'article_chats',
      message.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteArticleChat(String articleId) async {
    final db = await database;
    return await db.delete(
      'article_chats',
      where: 'articleId = ?',
      whereArgs: [articleId],
    );
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  Future<Map<String, int>> getArticleStats() async {
    final db = await database;

    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM articles',
    );
    final totalCount = totalResult.first['count'] as int;

    final unreadResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM articles WHERE isRead = 0',
    );
    final unreadCount = unreadResult.first['count'] as int;

    final savedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM articles WHERE isSaved = 1',
    );
    final savedCount = savedResult.first['count'] as int;

    final starredResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM articles WHERE isStarred = 1',
    );
    final starredCount = starredResult.first['count'] as int;

    return {
      'total': totalCount,
      'unread': unreadCount,
      'saved': savedCount,
      'starred': starredCount,
    };
  }
}
