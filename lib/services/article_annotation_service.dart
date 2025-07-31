import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/article_highlight.dart';
import '../models/article_note.dart';
import 'database_service.dart';

class ArticleAnnotationService {
  static final ArticleAnnotationService _instance = ArticleAnnotationService._internal();
  factory ArticleAnnotationService() => _instance;
  ArticleAnnotationService._internal();

  final DatabaseService _databaseService = DatabaseService();

  // Initialize tables for highlights and notes
  Future<void> initializeTables() async {
    if (kIsWeb) return;

    final db = await _databaseService.database;

    // Create highlights table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS article_highlights (
        id TEXT PRIMARY KEY,
        articleId TEXT NOT NULL,
        selectedText TEXT NOT NULL,
        startIndex INTEGER NOT NULL,
        endIndex INTEGER NOT NULL,
        color TEXT NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (articleId) REFERENCES articles (id) ON DELETE CASCADE
      )
    ''');

    // Create notes table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS article_notes (
        id TEXT PRIMARY KEY,
        articleId TEXT NOT NULL,
        content TEXT NOT NULL,
        position INTEGER,
        highlightId TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (articleId) REFERENCES articles (id) ON DELETE CASCADE,
        FOREIGN KEY (highlightId) REFERENCES article_highlights (id) ON DELETE CASCADE
      )
    ''');
  }

  // Highlight operations
  Future<void> addHighlight(ArticleHighlight highlight) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.insert('article_highlights', highlight.toJson());
  }

  Future<void> updateHighlight(ArticleHighlight highlight) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.update(
      'article_highlights',
      highlight.toJson(),
      where: 'id = ?',
      whereArgs: [highlight.id],
    );
  }

  Future<void> deleteHighlight(String highlightId) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.delete(
      'article_highlights',
      where: 'id = ?',
      whereArgs: [highlightId],
    );
  }

  Future<List<ArticleHighlight>> getHighlightsByArticle(String articleId) async {
    if (kIsWeb) return [];

    final db = await _databaseService.database;
    final maps = await db.query(
      'article_highlights',
      where: 'articleId = ?',
      whereArgs: [articleId],
      orderBy: 'startIndex ASC',
    );

    return maps.map((map) => ArticleHighlight.fromJson(map)).toList();
  }

  // Note operations
  Future<void> addNote(ArticleNote note) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.insert('article_notes', note.toJson());
  }

  Future<void> updateNote(ArticleNote note) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.update(
      'article_notes',
      note.toJson(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(String noteId) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.delete(
      'article_notes',
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  Future<List<ArticleNote>> getNotesByArticle(String articleId) async {
    if (kIsWeb) return [];

    final db = await _databaseService.database;
    final maps = await db.query(
      'article_notes',
      where: 'articleId = ?',
      whereArgs: [articleId],
      orderBy: 'createdAt DESC',
    );

    return maps.map((map) => ArticleNote.fromJson(map)).toList();
  }

  Future<List<ArticleNote>> getNotesByHighlight(String highlightId) async {
    if (kIsWeb) return [];

    final db = await _databaseService.database;
    final maps = await db.query(
      'article_notes',
      where: 'highlightId = ?',
      whereArgs: [highlightId],
      orderBy: 'createdAt DESC',
    );

    return maps.map((map) => ArticleNote.fromJson(map)).toList();
  }

  // Utility methods
  Future<int> getHighlightCountByArticle(String articleId) async {
    if (kIsWeb) return 0;

    final db = await _databaseService.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM article_highlights WHERE articleId = ?',
      [articleId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getNoteCountByArticle(String articleId) async {
    if (kIsWeb) return 0;

    final db = await _databaseService.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM article_notes WHERE articleId = ?',
      [articleId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Delete all annotations for an article
  Future<void> deleteAllAnnotationsForArticle(String articleId) async {
    if (kIsWeb) return;

    final db = await _databaseService.database;
    await db.delete(
      'article_highlights',
      where: 'articleId = ?',
      whereArgs: [articleId],
    );
    await db.delete(
      'article_notes',
      where: 'articleId = ?',
      whereArgs: [articleId],
    );
  }
}
