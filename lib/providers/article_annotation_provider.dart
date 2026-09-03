import 'package:flutter/foundation.dart';

import '../models/article_highlight.dart';
import '../models/article_note.dart';
import '../services/article_annotation_service.dart';
import '../utils/app_logger.dart';

/// Highlights and notes for one article.
///
/// Created per reader screen. Offsets are indices into the article's *plain
/// text projection* (see `HighlightInjector.plainText`), which the reader hands
/// over with [setArticleText] before any selection happens.
class ArticleAnnotationProvider extends ChangeNotifier {
  ArticleAnnotationProvider({ArticleAnnotationService? service})
    : _annotationService = service ?? ArticleAnnotationService();

  final ArticleAnnotationService _annotationService;

  List<ArticleHighlight> _highlights = <ArticleHighlight>[];
  List<ArticleNote> _notes = <ArticleNote>[];
  bool _isEditMode = false;
  String _articleText = '';
  String? _selectedText;
  int? _selectionStart;
  int? _selectionEnd;
  bool _disposed = false;

  List<ArticleHighlight> get highlights => List.unmodifiable(_highlights);
  List<ArticleNote> get notes => List.unmodifiable(_notes);
  bool get isEditMode => _isEditMode;

  /// Text of the current selection, or null.
  String? get selectedText => _selectedText;

  /// Start of the current selection in the plain text projection.
  int? get selectionStart => _selectionStart;

  /// End (exclusive) of the current selection in the plain text projection.
  int? get selectionEnd => _selectionEnd;

  /// True when something is selected and can be highlighted.
  bool get hasSelection =>
      _selectedText != null && _selectedText!.trim().isNotEmpty;

  /// The plain text projection the offsets are measured against.
  String get articleText => _articleText;

  /// Colours offered by the highlight picker.
  static const List<String> highlightColors = <String>[
    '#FFEB3B', // Yellow
    '#4CAF50', // Green
    '#2196F3', // Blue
    '#FF9800', // Orange
    '#E91E63', // Pink
    '#9C27B0', // Purple
  ];

  void toggleEditMode() {
    _isEditMode = !_isEditMode;
    if (!_isEditMode) {
      clearSelection();
      return;
    }
    _notify();
  }

  /// Stores the plain text projection new selections are resolved against.
  void setArticleText(String text) {
    if (_articleText == text) return;
    _articleText = text;
  }

  /// Records the current selection.
  ///
  /// [start]/[end] are computed from the plain text projection (first
  /// occurrence of [text]) when the caller does not know them - which is the
  /// normal case, because `SelectionArea` only reports the selected string.
  void setSelection(String text, {int? start, int? end}) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      clearSelection();
      return;
    }

    var resolvedStart = start ?? _articleText.indexOf(trimmed);
    if (resolvedStart < 0) resolvedStart = 0;
    final int resolvedEnd = end ?? (resolvedStart + trimmed.length);

    _selectedText = trimmed;
    _selectionStart = resolvedStart;
    _selectionEnd = resolvedEnd;
    _notify();
  }

  void clearSelection() {
    _selectedText = null;
    _selectionStart = null;
    _selectionEnd = null;
    _notify();
  }

  Future<void> loadAnnotations(String articleId) async {
    try {
      await _annotationService.initializeTables();
      _highlights = await _annotationService.getHighlightsByArticle(articleId);
      _notes = await _annotationService.getNotesByArticle(articleId);
      _notify();
    } catch (e, st) {
      AppLog.w('Could not load annotations for $articleId', e, st);
    }
  }

  /// Creates a highlight from the current selection.
  Future<ArticleHighlight?> addHighlight(
    String articleId,
    String color, {
    String? note,
  }) async {
    final String? text = _selectedText;
    if (text == null || text.trim().isEmpty) return null;

    final DateTime now = DateTime.now();
    final ArticleHighlight highlight = ArticleHighlight(
      id: '${now.microsecondsSinceEpoch}',
      articleId: articleId,
      selectedText: text,
      startIndex: _selectionStart ?? 0,
      endIndex: _selectionEnd ?? text.length,
      color: color,
      note: note,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _annotationService.addHighlight(highlight);
    } catch (e, st) {
      AppLog.w('Could not save highlight', e, st);
      return null;
    }

    _highlights = <ArticleHighlight>[..._highlights, highlight]
      ..sort(
        (ArticleHighlight a, ArticleHighlight b) =>
            a.startIndex.compareTo(b.startIndex),
      );
    clearSelection();
    return highlight;
  }

  Future<void> updateHighlight(ArticleHighlight highlight) async {
    final ArticleHighlight updated = highlight.copyWith(
      updatedAt: DateTime.now(),
    );
    try {
      await _annotationService.updateHighlight(updated);
    } catch (e, st) {
      AppLog.w('Could not update highlight ${highlight.id}', e, st);
      return;
    }
    _highlights = <ArticleHighlight>[
      for (final ArticleHighlight h in _highlights)
        if (h.id == updated.id) updated else h,
    ];
    _notify();
  }

  Future<void> deleteHighlight(String highlightId) async {
    try {
      await _annotationService.deleteHighlight(highlightId);
    } catch (e, st) {
      AppLog.w('Could not delete highlight $highlightId', e, st);
      return;
    }
    _highlights = _highlights
        .where((ArticleHighlight h) => h.id != highlightId)
        .toList();
    _notes = _notes
        .where((ArticleNote n) => n.highlightId != highlightId)
        .toList();
    _notify();
  }

  /// Highlight carrying [highlightId], or null.
  ArticleHighlight? highlightById(String highlightId) {
    for (final ArticleHighlight highlight in _highlights) {
      if (highlight.id == highlightId) return highlight;
    }
    return null;
  }

  Future<ArticleNote?> addNote(
    String articleId,
    String content, {
    int? position,
    String? highlightId,
  }) async {
    if (content.trim().isEmpty) return null;

    final DateTime now = DateTime.now();
    final ArticleNote note = ArticleNote(
      id: '${now.microsecondsSinceEpoch}',
      articleId: articleId,
      content: content.trim(),
      position: position ?? _selectionStart,
      highlightId: highlightId,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _annotationService.addNote(note);
    } catch (e, st) {
      AppLog.w('Could not save note', e, st);
      return null;
    }

    _notes = <ArticleNote>[note, ..._notes]
      ..sort(
        (ArticleNote a, ArticleNote b) => b.createdAt.compareTo(a.createdAt),
      );
    _notify();
    return note;
  }

  Future<void> updateNote(ArticleNote note) async {
    final ArticleNote updated = note.copyWith(updatedAt: DateTime.now());
    try {
      await _annotationService.updateNote(updated);
    } catch (e, st) {
      AppLog.w('Could not update note ${note.id}', e, st);
      return;
    }
    _notes = <ArticleNote>[
      for (final ArticleNote n in _notes)
        if (n.id == updated.id) updated else n,
    ];
    _notify();
  }

  Future<void> deleteNote(String noteId) async {
    try {
      await _annotationService.deleteNote(noteId);
    } catch (e, st) {
      AppLog.w('Could not delete note $noteId', e, st);
      return;
    }
    _notes = _notes.where((ArticleNote n) => n.id != noteId).toList();
    _notify();
  }

  List<ArticleNote> getNotesForHighlight(String highlightId) => _notes
      .where((ArticleNote note) => note.highlightId == highlightId)
      .toList();

  /// Free-standing notes - those not attached to a highlight.
  List<ArticleNote> get standaloneNotes =>
      _notes.where((ArticleNote note) => note.highlightId == null).toList();

  Future<void> clearAllAnnotations(String articleId) async {
    try {
      await _annotationService.deleteAllAnnotationsForArticle(articleId);
    } catch (e, st) {
      AppLog.w('Could not clear annotations for $articleId', e, st);
      return;
    }
    _highlights = <ArticleHighlight>[];
    _notes = <ArticleNote>[];
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
