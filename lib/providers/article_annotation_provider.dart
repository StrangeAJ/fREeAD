import 'package:flutter/foundation.dart';
import '../models/article_highlight.dart';
import '../models/article_note.dart';
import '../services/article_annotation_service.dart';

class ArticleAnnotationProvider extends ChangeNotifier {
  final ArticleAnnotationService _annotationService = ArticleAnnotationService();

  List<ArticleHighlight> _highlights = [];
  List<ArticleNote> _notes = [];
  bool _isEditMode = false;
  String? _selectedText;
  int? _selectionStart;
  int? _selectionEnd;

  List<ArticleHighlight> get highlights => _highlights;
  List<ArticleNote> get notes => _notes;
  bool get isEditMode => _isEditMode;
  String? get selectedText => _selectedText;

  // Predefined highlight colors
  static const List<String> highlightColors = [
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
    }
    notifyListeners();
  }

  void setSelection(String text, int start, int end) {
    _selectedText = text;
    _selectionStart = start;
    _selectionEnd = end;
    notifyListeners();
  }

  void clearSelection() {
    _selectedText = null;
    _selectionStart = null;
    _selectionEnd = null;
    notifyListeners();
  }

  Future<void> loadAnnotations(String articleId) async {
    try {
      _highlights = await _annotationService.getHighlightsByArticle(articleId);
      _notes = await _annotationService.getNotesByArticle(articleId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading annotations: $e');
    }
  }

  Future<void> addHighlight(String articleId, String color, {String? note}) async {
    if (_selectedText == null || _selectionStart == null || _selectionEnd == null) return;

    final highlight = ArticleHighlight(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      articleId: articleId,
      selectedText: _selectedText!,
      startIndex: _selectionStart!,
      endIndex: _selectionEnd!,
      color: color,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await _annotationService.addHighlight(highlight);
      _highlights.add(highlight);
      _highlights.sort((a, b) => a.startIndex.compareTo(b.startIndex));
      clearSelection();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding highlight: $e');
    }
  }

  Future<void> updateHighlight(ArticleHighlight highlight) async {
    try {
      final updatedHighlight = highlight.copyWith(updatedAt: DateTime.now());
      await _annotationService.updateHighlight(updatedHighlight);

      final index = _highlights.indexWhere((h) => h.id == highlight.id);
      if (index != -1) {
        _highlights[index] = updatedHighlight;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating highlight: $e');
    }
  }

  Future<void> deleteHighlight(String highlightId) async {
    try {
      await _annotationService.deleteHighlight(highlightId);
      _highlights.removeWhere((h) => h.id == highlightId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting highlight: $e');
    }
  }

  Future<void> addNote(String articleId, String content, {int? position, String? highlightId}) async {
    final note = ArticleNote(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      articleId: articleId,
      content: content,
      position: position,
      highlightId: highlightId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await _annotationService.addNote(note);
      _notes.add(note);
      _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding note: $e');
    }
  }

  Future<void> updateNote(ArticleNote note) async {
    try {
      final updatedNote = note.copyWith(updatedAt: DateTime.now());
      await _annotationService.updateNote(updatedNote);

      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index != -1) {
        _notes[index] = updatedNote;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating note: $e');
    }
  }

  Future<void> deleteNote(String noteId) async {
    try {
      await _annotationService.deleteNote(noteId);
      _notes.removeWhere((n) => n.id == noteId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting note: $e');
    }
  }

  List<ArticleNote> getNotesForHighlight(String highlightId) {
    return _notes.where((note) => note.highlightId == highlightId).toList();
  }

  Future<void> clearAllAnnotations(String articleId) async {
    try {
      await _annotationService.deleteAllAnnotationsForArticle(articleId);
      _highlights.clear();
      _notes.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing annotations: $e');
    }
  }
}
