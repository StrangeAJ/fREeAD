import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/article_highlight.dart';

/// Injects stored highlights into sanitized article HTML as `<mark>` elements.
///
/// The reader renders article bodies as HTML, so highlights cannot be painted
/// over a flat `String` any more. Instead the DOM is walked once to build a
/// *plain text projection* (every text node concatenated, in document order);
/// each [ArticleHighlight] is located inside that projection and the matching
/// character range is wrapped in
/// `<mark data-hl="<id>" data-hl-color="#RRGGBB">`, splitting text nodes when a
/// range spans several of them.
///
/// Pure Dart - no Flutter imports - so it is cheap to unit test.
///
/// ```dart
/// final html = HighlightInjector.apply(article.fullContent!, highlights);
/// ```
abstract final class HighlightInjector {
  /// Attribute carrying [ArticleHighlight.id] on an injected `<mark>`.
  static const String idAttribute = 'data-hl';

  /// Attribute carrying the highlight colour on an injected `<mark>`.
  static const String colorAttribute = 'data-hl-color';

  /// Used when a highlight has no (or a malformed) colour.
  static const String defaultColor = '#FFEB3B';

  /// The plain text projection of [html]: every text node concatenated in
  /// document order, with no whitespace collapsing.
  ///
  /// Highlight offsets (`startIndex`/`endIndex`) are indices into this string.
  static String plainText(String html) {
    if (html.trim().isEmpty) return '';
    final dom.DocumentFragment fragment = html_parser.parseFragment(html);
    final StringBuffer buffer = StringBuffer();
    for (final dom.Text node in _textNodes(fragment)) {
      buffer.write(node.data);
    }
    return buffer.toString();
  }

  /// Returns [html] with every resolvable highlight wrapped in a `<mark>`.
  ///
  /// Highlights whose [ArticleHighlight.selectedText] no longer appears in the
  /// body (the article was re-extracted, say) are skipped silently. Where two
  /// highlights overlap the one with the lower `startIndex` wins.
  static String apply(String html, List<ArticleHighlight> highlights) {
    if (html.trim().isEmpty || highlights.isEmpty) return html;

    final dom.DocumentFragment fragment = html_parser.parseFragment(html);
    final List<dom.Text> nodes = _textNodes(fragment);
    if (nodes.isEmpty) return html;

    final StringBuffer buffer = StringBuffer();
    for (final dom.Text node in nodes) {
      buffer.write(node.data);
    }
    final String projection = buffer.toString();
    if (projection.isEmpty) return html;

    // Per-character owner map. `??=` keeps the first (lowest startIndex)
    // highlight when two of them overlap.
    final List<ArticleHighlight?> owners = List<ArticleHighlight?>.filled(
      projection.length,
      null,
    );
    final List<ArticleHighlight> ordered = <ArticleHighlight>[...highlights]
      ..sort((ArticleHighlight a, ArticleHighlight b) {
        final int byStart = a.startIndex.compareTo(b.startIndex);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });

    var matched = 0;
    for (final ArticleHighlight highlight in ordered) {
      final int? start = _resolveStart(projection, highlight);
      if (start == null) continue;
      matched++;
      final int end = start + highlight.selectedText.length;
      for (var i = start; i < end && i < owners.length; i++) {
        owners[i] ??= highlight;
      }
    }
    if (matched == 0) return html;

    var cursor = 0;
    for (final dom.Text node in nodes) {
      final String data = node.data;
      final int nodeStart = cursor;
      cursor += data.length;
      if (data.isEmpty) continue;

      var covered = false;
      for (var i = nodeStart; i < nodeStart + data.length; i++) {
        if (owners[i] != null) {
          covered = true;
          break;
        }
      }
      if (!covered) continue;

      final dom.Node? parent = node.parentNode;
      if (parent == null) continue;
      final int index = parent.nodes.indexOf(node);
      if (index < 0) continue;

      final List<dom.Node> replacements = <dom.Node>[];
      var runStart = 0;
      for (var i = 1; i <= data.length; i++) {
        final ArticleHighlight? previous = owners[nodeStart + i - 1];
        final ArticleHighlight? current = i < data.length
            ? owners[nodeStart + i]
            : null;
        if (i == data.length || !identical(current, previous)) {
          replacements.add(_runNode(data.substring(runStart, i), previous));
          runStart = i;
        }
      }

      parent.nodes.removeAt(index);
      parent.nodes.insertAll(index, replacements);
    }

    return fragment.outerHtml;
  }

  /// A `<mark>` for a highlighted run, a bare text node otherwise.
  static dom.Node _runNode(String text, ArticleHighlight? owner) {
    if (owner == null) return dom.Text(text);
    final dom.Element mark = dom.Element.tag('mark');
    mark.attributes[idAttribute] = owner.id;
    mark.attributes[colorAttribute] = normalizeColor(owner.color);
    mark.append(dom.Text(text));
    return mark;
  }

  /// Index of the occurrence of [highlight]'s text nearest to its stored
  /// `startIndex`, or null when the text is gone.
  static int? _resolveStart(String projection, ArticleHighlight highlight) {
    final String needle = highlight.selectedText;
    if (needle.isEmpty) return null;

    var index = projection.indexOf(needle);
    if (index < 0) return null;

    var best = index;
    var bestDistance = (index - highlight.startIndex).abs();
    while (true) {
      index = projection.indexOf(needle, index + 1);
      if (index < 0) break;
      final int distance = (index - highlight.startIndex).abs();
      if (distance < bestDistance) {
        best = index;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// `#RRGGBB`, falling back to [defaultColor] for anything unparseable.
  static String normalizeColor(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) return defaultColor;
    final String hex = value.startsWith('#') ? value.substring(1) : value;
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
      return defaultColor;
    }
    return '#${hex.toUpperCase()}';
  }

  /// Every text node under [root], in document order, skipping the contents of
  /// `<script>` / `<style>` (which the sanitizer removes anyway).
  static List<dom.Text> _textNodes(dom.Node root) {
    final List<dom.Text> found = <dom.Text>[];
    void walk(dom.Node node) {
      for (final dom.Node child in node.nodes) {
        if (child is dom.Text) {
          found.add(child);
        } else if (child is dom.Element) {
          final String tag = (child.localName ?? '').toLowerCase();
          if (tag == 'script' || tag == 'style') continue;
          walk(child);
        }
      }
    }

    walk(root);
    return found;
  }
}
