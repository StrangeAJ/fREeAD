import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/article_highlight.dart';
import '../../models/article_note.dart';
import '../../providers/article_annotation_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ui/ui.dart';
import 'highlight_injector.dart';

/// Opens the "Notes & highlights" sheet for one article.
///
/// The provider is passed explicitly because modal routes are siblings of the
/// reader screen, not descendants of it.
Future<void> showAnnotationsSheet(
  BuildContext context, {
  required String articleId,
  required ArticleAnnotationProvider annotations,
}) {
  return showAppBottomSheet<void>(
    context,
    title: 'Notes & highlights',
    builder: (BuildContext context) =>
        ChangeNotifierProvider<ArticleAnnotationProvider>.value(
          value: annotations,
          child: AnnotationsSheet(articleId: articleId),
        ),
  );
}

/// Lets the reader pick a highlight colour for the current selection.
/// Returns the chosen hex colour, or null when dismissed.
Future<String?> showHighlightColorSheet(BuildContext context) {
  return showAppBottomSheet<String>(
    context,
    title: 'Highlight',
    builder: (BuildContext context) => const HighlightColorPicker(),
  );
}

/// Opens the options for one existing highlight: recolour, note, delete.
Future<void> showHighlightOptionsSheet(
  BuildContext context, {
  required ArticleHighlight highlight,
  required ArticleAnnotationProvider annotations,
}) {
  return showAppBottomSheet<void>(
    context,
    title: 'Highlight',
    builder: (BuildContext sheetContext) =>
        ChangeNotifierProvider<ArticleAnnotationProvider>.value(
          value: annotations,
          child: _HighlightOptions(highlightId: highlight.id),
        ),
  );
}

/// A single-line note composer. Returns the text, or null when cancelled.
Future<String?> showNoteEditor(
  BuildContext context, {
  String? initialText,
  String title = 'Note',
}) {
  return showAppBottomSheet<String>(
    context,
    title: title,
    builder: (BuildContext context) => _NoteEditor(initialText: initialText),
  );
}

/// The row of highlight colours.
class HighlightColorPicker extends StatelessWidget {
  const HighlightColorPicker({super.key, this.selected, this.onSelected});

  /// Currently applied colour, drawn with a check mark.
  final String? selected;

  /// When null the picker pops the sheet with the chosen colour instead.
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Wrap(
      spacing: t.spaceM,
      runSpacing: t.spaceM,
      children: <Widget>[
        for (final String hex in ArticleAnnotationProvider.highlightColors)
          _Swatch(
            hex: hex,
            selected:
                selected != null &&
                HighlightInjector.normalizeColor(selected) ==
                    HighlightInjector.normalizeColor(hex),
            onTap: () {
              if (onSelected != null) {
                onSelected!(hex);
              } else {
                Navigator.of(context).pop(hex);
              }
            },
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = colorFromHex(hex, fallback: t.warning);

    return Semantics(
      button: true,
      selected: selected,
      label: 'Highlight colour',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? t.textPrimary : t.hairlineStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: t.textPrimary)
              : null,
        ),
      ),
    );
  }
}

/// `#RRGGBB` -> [Color], falling back when the string is unusable.
Color colorFromHex(String? hex, {required Color fallback}) {
  final String normalized = HighlightInjector.normalizeColor(hex);
  final int? value = int.tryParse(normalized.substring(1), radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | (value & 0xFFFFFF));
}

/// The body of [showAnnotationsSheet].
class AnnotationsSheet extends StatelessWidget {
  const AnnotationsSheet({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ArticleAnnotationProvider annotations = context
        .watch<ArticleAnnotationProvider>();
    final List<ArticleHighlight> highlights = annotations.highlights;
    final List<ArticleNote> notes = annotations.standaloneNotes;

    if (highlights.isEmpty && notes.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.spaceXl),
        child: EmptyState(
          compact: true,
          icon: Icons.edit_note_rounded,
          title: 'Nothing marked yet',
          message:
              'Select text in the article to highlight it, or add a free note.',
          primaryActionLabel: 'Add note',
          primaryActionIcon: Icons.note_add_outlined,
          onPrimaryAction: () => _addNote(context, annotations),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (highlights.isNotEmpty) ...<Widget>[
          SectionHeader(
            label: 'Highlights',
            padding: EdgeInsets.only(bottom: t.spaceS),
          ),
          for (final ArticleHighlight highlight in highlights)
            _HighlightRow(highlight: highlight, annotations: annotations),
        ],
        SectionHeader(
          label: 'Notes',
          padding: EdgeInsets.only(top: t.spaceL, bottom: t.spaceS),
          actionLabel: 'Add',
          onAction: () => _addNote(context, annotations),
        ),
        if (notes.isEmpty)
          Text(
            'No free notes.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: t.textTertiary),
          )
        else
          for (final ArticleNote note in notes)
            _NoteRow(note: note, annotations: annotations),
        SizedBox(height: t.spaceM),
      ],
    );
  }

  Future<void> _addNote(
    BuildContext context,
    ArticleAnnotationProvider annotations,
  ) async {
    final String? text = await showNoteEditor(context, title: 'New note');
    if (text == null || text.trim().isEmpty) return;
    await annotations.addNote(articleId, text);
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({required this.highlight, required this.annotations});

  final ArticleHighlight highlight;
  final ArticleAnnotationProvider annotations;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = colorFromHex(highlight.color, fallback: t.warning);

    return SurfaceCard(
      level: 2,
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.all(t.spaceM),
      onTap: () => showHighlightOptionsSheet(
        context,
        highlight: highlight,
        annotations: annotations,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 4,
            height: 36,
            margin: EdgeInsets.only(right: t.spaceM),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  highlight.selectedText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: t.textPrimary),
                ),
                if (highlight.note != null && highlight.note!.isNotEmpty) ...[
                  SizedBox(height: t.spaceXs),
                  Text(
                    highlight.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: t.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: t.textTertiary),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.annotations});

  final ArticleNote note;
  final ArticleAnnotationProvider annotations;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return SurfaceCard(
      level: 2,
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.fromLTRB(t.spaceM, t.spaceM, t.spaceS, t.spaceM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              note.content,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.textPrimary),
            ),
          ),
          IconButton(
            onPressed: () async {
              final String? edited = await showNoteEditor(
                context,
                initialText: note.content,
                title: 'Edit note',
              );
              if (edited == null || edited.trim().isEmpty) return;
              await annotations.updateNote(note.copyWith(content: edited));
            },
            icon: const Icon(Icons.edit_outlined),
            iconSize: 18,
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => annotations.deleteNote(note.id),
            icon: const Icon(Icons.delete_outline_rounded),
            iconSize: 18,
            color: t.danger,
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _HighlightOptions extends StatelessWidget {
  const _HighlightOptions({required this.highlightId});

  final String highlightId;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ArticleAnnotationProvider annotations = context
        .watch<ArticleAnnotationProvider>();
    final ArticleHighlight? highlight = annotations.highlightById(highlightId);

    if (highlight == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.spaceXl),
        child: Text(
          'This highlight is gone.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: t.textTertiary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SurfaceCard(
          level: 2,
          padding: EdgeInsets.all(t.spaceM),
          child: Text(
            highlight.selectedText,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: t.textPrimary),
          ),
        ),
        SizedBox(height: t.spaceL),
        HighlightColorPicker(
          selected: highlight.color,
          onSelected: (String hex) =>
              annotations.updateHighlight(highlight.copyWith(color: hex)),
        ),
        SizedBox(height: t.spaceL),
        if (highlight.note != null && highlight.note!.isNotEmpty) ...<Widget>[
          Text(
            highlight.note!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: t.textSecondary),
          ),
          SizedBox(height: t.spaceM),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final String? note = await showNoteEditor(
                    context,
                    initialText: highlight.note,
                    title: 'Note on highlight',
                  );
                  if (note == null) return;
                  await annotations.updateHighlight(
                    highlight.copyWith(note: note),
                  );
                },
                icon: const Icon(Icons.note_alt_outlined, size: 18),
                label: Text(highlight.note == null ? 'Add note' : 'Edit note'),
              ),
            ),
            SizedBox(width: t.spaceM),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final NavigatorState navigator = Navigator.of(context);
                  await annotations.deleteHighlight(highlight.id);
                  navigator.pop();
                },
                style: OutlinedButton.styleFrom(foregroundColor: t.danger),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({this.initialText});

  final String? initialText;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Write a note...'),
        ),
        SizedBox(height: t.spaceL),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            SizedBox(width: t.spaceS),
            GlowButton(
              label: 'Save',
              onPressed: () => Navigator.of(context).pop(_controller.text),
            ),
          ],
        ),
      ],
    );
  }
}
