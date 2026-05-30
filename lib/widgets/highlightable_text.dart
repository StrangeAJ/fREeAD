import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../models/article_highlight.dart';
import '../providers/article_annotation_provider.dart';

class HighlightableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final List<ArticleHighlight> highlights;
  final bool isEditMode;

  const HighlightableText({
    super.key,
    required this.text,
    this.style,
    required this.highlights,
    required this.isEditMode,
  });

  @override
  State<HighlightableText> createState() => _HighlightableTextState();
}

class _HighlightableTextState extends State<HighlightableText> {
  OverlayEntry? _selectionOverlay;

  @override
  void dispose() {
    _removeSelectionOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.highlights.isEmpty && !widget.isEditMode) {
      return SelectableText(
        widget.text,
        style: widget.style,
        onSelectionChanged: widget.isEditMode ? _handleTextSelection : null,
      );
    }

    return Consumer<ArticleAnnotationProvider>(
      builder: (context, provider, child) {
        return widget.isEditMode
            ? SelectableText(
                widget.text,
                style: widget.style,
                onSelectionChanged: (selection, cause) =>
                    _handleTextSelection(selection, cause, provider),
              )
            : RichText(text: _buildTextSpan(context, provider));
      },
    );
  }

  void _handleTextSelection(
    TextSelection selection,
    SelectionChangedCause? cause, [
    ArticleAnnotationProvider? provider,
  ]) {
    if (!widget.isEditMode || provider == null) return;

    final selectedText = widget.text.substring(selection.start, selection.end);

    if (selectedText.trim().isNotEmpty && selection.start != selection.end) {
      // Set the selection in the provider
      provider.setSelection(
        selectedText.trim(),
        selection.start,
        selection.end,
      );
    } else {
      // Clear selection if nothing is selected
      provider.clearSelection();
      _removeSelectionOverlay();
    }
  }

  void _removeSelectionOverlay() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
  }

  TextSpan _buildTextSpan(
    BuildContext context,
    ArticleAnnotationProvider provider,
  ) {
    List<TextSpan> spans = [];
    int currentIndex = 0;

    // Filter out invalid highlights and sort by start index
    final validHighlights = widget.highlights.where((highlight) {
      return highlight.startIndex >= 0 &&
          highlight.startIndex < widget.text.length &&
          highlight.endIndex > highlight.startIndex &&
          highlight.endIndex <= widget.text.length;
    }).toList()..sort((a, b) => a.startIndex.compareTo(b.startIndex));

    for (final highlight in validHighlights) {
      // Skip overlapping highlights
      if (highlight.startIndex < currentIndex) continue;

      // Add text before highlight
      if (currentIndex < highlight.startIndex) {
        final safeStartIndex = currentIndex.clamp(0, widget.text.length);
        final safeEndIndex = highlight.startIndex.clamp(0, widget.text.length);
        if (safeStartIndex < safeEndIndex) {
          spans.add(
            TextSpan(
              text: widget.text.substring(safeStartIndex, safeEndIndex),
              style: widget.style,
              recognizer: widget.isEditMode
                  ? (TapGestureRecognizer()
                      ..onTapDown = (details) =>
                          _handleTapDown(context, provider, details))
                  : null,
            ),
          );
        }
      }

      // Add highlighted text with bounds checking
      final safeStartIndex = highlight.startIndex.clamp(0, widget.text.length);
      final safeEndIndex = highlight.endIndex.clamp(
        highlight.startIndex,
        widget.text.length,
      );

      if (safeStartIndex < safeEndIndex) {
        final highlightColor = Color(
          int.parse('0xFF${highlight.color.substring(1)}'),
        );
        final highlightText = widget.text.substring(
          safeStartIndex,
          safeEndIndex,
        );

        spans.add(
          TextSpan(
            text: highlightText,
            style: widget.style?.copyWith(
              backgroundColor: highlightColor.withOpacity(0.4),
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  _showHighlightOptions(context, provider, highlight),
          ),
        );

        currentIndex = safeEndIndex;
      }
    }

    // Add remaining text
    if (currentIndex < widget.text.length) {
      spans.add(
        TextSpan(
          text: widget.text.substring(currentIndex),
          style: widget.style,
          recognizer: widget.isEditMode
              ? (TapGestureRecognizer()
                  ..onTapDown = (details) =>
                      _handleTapDown(context, provider, details))
              : null,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  void _handleTapDown(
    BuildContext context,
    ArticleAnnotationProvider provider,
    TapDownDetails details,
  ) {
    if (!widget.isEditMode) return;
    // In edit mode with RichText, we'll rely on the SelectableText for selection
  }

  void _showHighlightOptions(
    BuildContext context,
    ArticleAnnotationProvider provider,
    ArticleHighlight highlight,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Highlight Options',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Highlighted text preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(
                  int.parse('0xFF${highlight.color.substring(1)}'),
                ).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Color(
                    int.parse('0xFF${highlight.color.substring(1)}'),
                  ).withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Text(
                highlight.selectedText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  backgroundColor: Color(
                    int.parse('0xFF${highlight.color.substring(1)}'),
                  ).withOpacity(0.3),
                ),
              ),
            ),

            if (highlight.note != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.note, size: 16, color: Colors.blue.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Note:',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade600,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      highlight.note!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editHighlightNote(context, provider, highlight);
                    },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Edit Note'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      provider.deleteHighlight(highlight.id);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _editHighlightNote(
    BuildContext context,
    ArticleAnnotationProvider provider,
    ArticleHighlight highlight,
  ) {
    final noteController = TextEditingController(text: highlight.note ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Note'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'Add your note here...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final updatedHighlight = highlight.copyWith(
                note: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
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
}
