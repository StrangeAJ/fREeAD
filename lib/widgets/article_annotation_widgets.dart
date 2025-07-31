import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/article_highlight.dart';
import '../models/article_note.dart';
import '../providers/article_annotation_provider.dart';

class HighlightColorPicker extends StatelessWidget {
  final String articleId;
  final VoidCallback? onHighlightAdded;

  const HighlightColorPicker({
    super.key,
    required this.articleId,
    this.onHighlightAdded,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ArticleAnnotationProvider>(
      builder: (context, provider, child) {
        if (provider.selectedText == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Highlight Selection',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"${provider.selectedText!.length > 50 ? '${provider.selectedText!.substring(0, 50)}...' : provider.selectedText!}"',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose highlight color:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ArticleAnnotationProvider.highlightColors.map((color) {
                  return GestureDetector(
                    onTap: () => _addHighlight(context, provider, color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(int.parse('0xFF${color.substring(1)}')),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.brush,
                        color: Colors.black54,
                        size: 20,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => provider.clearSelection(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showNoteDialog(context, provider),
                    icon: const Icon(Icons.note_add, size: 16),
                    label: const Text('Add Note'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _addHighlight(BuildContext context, ArticleAnnotationProvider provider, String color) async {
    await provider.addHighlight(articleId, color);
    onHighlightAdded?.call();
  }

  void _showNoteDialog(BuildContext context, ArticleAnnotationProvider provider) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note to Highlight'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'Enter your note...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (noteController.text.trim().isNotEmpty) {
                // First add highlight with note, then add separate note
                await provider.addHighlight(
                  articleId,
                  ArticleAnnotationProvider.highlightColors.first,
                  note: noteController.text.trim(),
                );
                onHighlightAdded?.call();
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class ArticleNotesPanel extends StatelessWidget {
  final String articleId;

  const ArticleNotesPanel({
    super.key,
    required this.articleId,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ArticleAnnotationProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Notes & Highlights',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showAddNoteDialog(context, provider),
                    icon: const Icon(Icons.add_comment),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    ...provider.highlights.map((highlight) => _buildHighlightCard(context, provider, highlight)),
                    ...provider.notes.where((note) => note.highlightId == null).map((note) => _buildNoteCard(context, provider, note)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHighlightCard(BuildContext context, ArticleAnnotationProvider provider, ArticleHighlight highlight) {
    final highlightColor = Color(int.parse('0xFF${highlight.color.substring(1)}'));
    final notes = provider.getNotesForHighlight(highlight.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: highlightColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    highlight.selectedText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      backgroundColor: highlightColor.withOpacity(0.3),
                    ),
                  ),
                ),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Note'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditHighlightDialog(context, provider, highlight);
                    } else if (value == 'delete') {
                      provider.deleteHighlight(highlight.id);
                    }
                  },
                ),
              ],
            ),
            if (highlight.note != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  highlight.note!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            ...notes.map((note) => _buildNoteCard(context, provider, note, isSubNote: true)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, ArticleAnnotationProvider provider, ArticleNote note, {bool isSubNote = false}) {
    return Card(
      margin: EdgeInsets.only(
        bottom: 8,
        left: isSubNote ? 16 : 0,
      ),
      color: isSubNote ? Colors.blue.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.note,
                  size: 16,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  'Note',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade600,
                  ),
                ),
                const Spacer(),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditNoteDialog(context, provider, note);
                    } else if (value == 'delete') {
                      provider.deleteNote(note.id);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note.content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Created: ${note.createdAt.toString().split('.')[0]}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddNoteDialog(BuildContext context, ArticleAnnotationProvider provider) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'Enter your note...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (noteController.text.trim().isNotEmpty) {
                await provider.addNote(articleId, noteController.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditHighlightDialog(BuildContext context, ArticleAnnotationProvider provider, ArticleHighlight highlight) {
    final noteController = TextEditingController(text: highlight.note ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Highlight Note'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'Enter note for this highlight...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updatedHighlight = highlight.copyWith(
                note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
              );
              await provider.updateHighlight(updatedHighlight);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditNoteDialog(BuildContext context, ArticleAnnotationProvider provider, ArticleNote note) {
    final noteController = TextEditingController(text: note.content);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Note'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'Enter your note...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (noteController.text.trim().isNotEmpty) {
                final updatedNote = note.copyWith(content: noteController.text.trim());
                await provider.updateNote(updatedNote);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
