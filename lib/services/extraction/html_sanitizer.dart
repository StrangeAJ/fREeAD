import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Allow-list based HTML sanitiser for article bodies.
///
/// Pure Dart (no Flutter imports) so it can run inside a `compute` isolate.
/// The output is safe to hand to `flutter_widget_from_html_core`: no scripts,
/// no inline styles, no classes, absolute URLs only.
class HtmlSanitizer {
  const HtmlSanitizer();

  /// Tags that survive sanitising.
  static const Set<String> allowedTags = <String>{
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'li',
    'blockquote',
    'pre',
    'code',
    'em',
    'strong',
    'b',
    'i',
    'u',
    's',
    'a',
    'img',
    'figure',
    'figcaption',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'br',
    'hr',
    'sup',
    'sub',
    'mark',
    'span',
    'div',
    'picture',
    'source',
    'video',
    'audio',
  };

  /// Attributes that survive sanitising, on any allowed tag.
  static const Set<String> allowedAttributes = <String>{
    'href',
    'src',
    'alt',
    'title',
    'width',
    'height',
    'colspan',
    'rowspan',
    'srcset',
    'data-hl',
    'data-hl-color',
  };

  /// Tags removed together with their subtree.
  static const Set<String> _droppedTags = <String>{
    'script',
    'style',
    'iframe',
    'form',
    'input',
    'button',
    'select',
    'option',
    'textarea',
    'noscript',
    'svg',
    'canvas',
    'link',
    'meta',
    'object',
    'embed',
    'applet',
    'template',
    'head',
    'nav',
    'aside',
    'dialog',
  };

  /// Block level tags that must not be left empty.
  static const Set<String> _blockTags = <String>{
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'li',
    'figure',
    'figcaption',
    'td',
    'th',
    'section',
    'article',
  };

  static const Set<String> _voidLikeTags = <String>{
    'img',
    'br',
    'hr',
    'video',
    'audio',
    'source',
    'picture',
    'table',
    'iframe',
  };

  /// Fragments in an image URL that mark it as an analytics beacon.
  static final RegExp _trackingPixel = RegExp(
    r'(pixel|/track|tracker|beacon|/imp\b|doubleclick|googletagmanager|'
    r'google-analytics|scorecardresearch|quantserve|stats\.wordpress|'
    r'feedburner\.com/~ff|feeds\.feedburner\.com/~r|1x1\.|spacer\.gif|'
    r'blank\.gif)',
    caseSensitive: false,
  );

  /// Sanitises [html], resolving relative URLs against [baseUrl].
  static String sanitize(String html, {String? baseUrl}) {
    if (html.trim().isEmpty) return '';
    final dom.DocumentFragment fragment;
    try {
      fragment = html_parser.parseFragment(html);
    } catch (_) {
      return _escape(html);
    }

    final base = _parseBase(baseUrl);
    _removeComments(fragment);
    _flattenPictures(fragment);

    for (final node in fragment.nodes.toList()) {
      _clean(node, base);
    }

    _unwrapRedundantWrappers(fragment);
    _removeEmptyBlocks(fragment);
    _collapseLeadingBreaks(fragment);

    return fragment.nodes.map(_serialize).join().trim();
  }

  /// Plain text of [html] with block boundaries preserved as newlines.
  static String toPlainText(String html) {
    if (html.trim().isEmpty) return '';
    final dom.DocumentFragment fragment;
    try {
      fragment = html_parser.parseFragment(html);
    } catch (_) {
      return html.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    }
    final buffer = StringBuffer();
    for (final node in fragment.nodes) {
      _writeText(node, buffer);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t ]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// First [max] characters of the plain text of [html], cut on a word break.
  static String excerpt(String html, {int max = 300}) {
    final text = toPlainText(html).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= max) return text;
    var cut = text.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > max ~/ 2) cut = cut.substring(0, lastSpace);
    return '${cut.trimRight()}...';
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  static Uri? _parseBase(String? baseUrl) {
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasScheme) return null;
    return uri;
  }

  static void _removeComments(dom.Node node) {
    for (final child in node.nodes.toList()) {
      if (child.nodeType == dom.Node.COMMENT_NODE) {
        child.remove();
      } else {
        _removeComments(child);
      }
    }
  }

  /// Replaces `<picture>` with the best `<img>` it contains.
  static void _flattenPictures(dom.Node root) {
    for (final picture in _descendants(root, 'picture')) {
      if (picture.parentNode == null) continue;
      final img = picture.querySelector('img');
      String? best = img?.attributes['src'];
      var bestWidth = -1;

      for (final source in picture.querySelectorAll('source')) {
        final candidate = _largestSrcsetUrl(source.attributes['srcset']);
        if (candidate == null) continue;
        final width = candidate.width;
        if (width > bestWidth || best == null) {
          best = candidate.url;
          bestWidth = width;
        }
      }
      best ??= _largestSrcsetUrl(img?.attributes['srcset'])?.url;
      if (best == null || best.trim().isEmpty) {
        picture.remove();
        continue;
      }

      final replacement = dom.Element.tag('img');
      replacement.attributes['src'] = best;
      final alt = img?.attributes['alt'];
      if (alt != null && alt.isNotEmpty) replacement.attributes['alt'] = alt;
      _replaceNode(picture, replacement);
    }
  }

  static List<dom.Element> _descendants(dom.Node root, String tag) {
    final results = <dom.Element>[];
    void walk(dom.Node node) {
      for (final child in node.nodes.toList()) {
        if (child is dom.Element) {
          if (child.localName == tag) results.add(child);
          walk(child);
        }
      }
    }

    walk(root);
    return results;
  }

  /// Recursively cleans [node] in place.
  static void _clean(dom.Node node, Uri? base) {
    if (node is dom.Text) return;
    if (node is! dom.Element) {
      if (node.nodeType != dom.Node.ELEMENT_NODE) {
        // Doctype / processing instructions are meaningless in a fragment.
        if (node.nodeType != dom.Node.TEXT_NODE) node.remove();
      }
      return;
    }

    final tag = node.localName ?? '';

    if (_droppedTags.contains(tag)) {
      node.remove();
      return;
    }

    // Clean children first so unwrapping below sees final content.
    for (final child in node.nodes.toList()) {
      _clean(child, base);
    }

    if (!allowedTags.contains(tag)) {
      _unwrap(node);
      return;
    }

    _cleanAttributes(node, base);

    if (tag == 'img' && _isDroppableImage(node)) {
      node.remove();
      return;
    }
    if (tag == 'a' && node.attributes['href'] == null && node.text.isEmpty) {
      node.remove();
    }
  }

  static void _cleanAttributes(dom.Element element, Uri? base) {
    for (final key in element.attributes.keys.toList()) {
      final name = key.toString().toLowerCase();
      if (!allowedAttributes.contains(name)) {
        element.attributes.remove(key);
      }
    }

    final href = element.attributes['href'];
    if (href != null) {
      final resolved = _resolveUrl(href, base);
      if (resolved == null) {
        element.attributes.remove('href');
      } else {
        element.attributes['href'] = resolved;
      }
    }

    final src = element.attributes['src'];
    if (src != null) {
      final resolved = _resolveUrl(src, base, allowData: true);
      if (resolved == null) {
        element.attributes.remove('src');
      } else {
        element.attributes['src'] = resolved;
      }
    }

    final srcset = element.attributes['srcset'];
    if (srcset != null) {
      // The reader renders a single image; keep only the largest candidate.
      final best = _largestSrcsetUrl(srcset);
      element.attributes.remove('srcset');
      if (best != null && element.localName == 'img') {
        final resolved = _resolveUrl(best.url, base);
        final current = element.attributes['src'];
        if (resolved != null && (current == null || _isPlaceholder(current))) {
          element.attributes['src'] = resolved;
        }
      }
    }

    // Numeric-only sizing attributes; drop junk like `width="100%"`.
    for (final key in const ['width', 'height', 'colspan', 'rowspan']) {
      final value = element.attributes[key];
      if (value != null && int.tryParse(value.trim()) == null) {
        element.attributes.remove(key);
      }
    }
  }

  static bool _isPlaceholder(String src) =>
      src.startsWith('data:') || src.contains('placeholder');

  static bool _isDroppableImage(dom.Element img) {
    final src = img.attributes['src'];
    if (src == null || src.trim().isEmpty) return true;
    if (_trackingPixel.hasMatch(src)) return true;
    final width = int.tryParse(img.attributes['width'] ?? '');
    final height = int.tryParse(img.attributes['height'] ?? '');
    if (width != null && width <= 2) return true;
    if (height != null && height <= 2) return true;
    return false;
  }

  static String? _resolveUrl(String raw, Uri? base, {bool allowData = false}) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('vbscript:') ||
        lower.startsWith('file:')) {
      return null;
    }
    if (lower.startsWith('data:')) {
      return allowData && lower.startsWith('data:image/') ? value : null;
    }
    if (lower.startsWith('#') || lower.startsWith('mailto:')) return value;
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return value;
    }
    if (base == null) return value;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  /// Picks the widest candidate from a `srcset` attribute.
  static _SrcsetCandidate? _largestSrcsetUrl(String? srcset) {
    if (srcset == null || srcset.trim().isEmpty) return null;
    _SrcsetCandidate? best;
    for (final part in srcset.split(',')) {
      final tokens = part.trim().split(RegExp(r'\s+'));
      if (tokens.isEmpty || tokens.first.isEmpty) continue;
      var width = 0;
      if (tokens.length > 1) {
        final descriptor = tokens[1];
        if (descriptor.endsWith('w')) {
          width =
              int.tryParse(descriptor.substring(0, descriptor.length - 1)) ?? 0;
        } else if (descriptor.endsWith('x')) {
          final scale =
              double.tryParse(descriptor.substring(0, descriptor.length - 1)) ??
              1;
          width = (scale * 1000).round();
        }
      }
      if (best == null || width > best.width) {
        best = _SrcsetCandidate(tokens.first, width);
      }
    }
    return best;
  }

  /// Replaces [element] with its children.
  ///
  /// Uses [dom.Node.parentNode] rather than `parent` because the top level of
  /// a parsed fragment is a `DocumentFragment`, for which `parent` is null.
  static void _unwrap(dom.Element element) {
    final parent = element.parentNode;
    if (parent == null) return;
    final index = parent.nodes.indexOf(element);
    final children = element.nodes.toList();
    for (final child in children) {
      child.remove();
    }
    element.remove();
    if (index < 0) return;
    parent.nodes.insertAll(index, children);
  }

  /// Unwraps `div`/`span` elements that only wrap inline content.
  static void _unwrapRedundantWrappers(dom.Node root) {
    for (final element in _allElements(root)) {
      if (element.parentNode == null) continue;
      final tag = element.localName;
      if (tag != 'div' && tag != 'span') continue;

      final hasBlockChild = element.children.any(
        (child) =>
            _blockTags.contains(child.localName) ||
            _voidLikeTags.contains(child.localName) ||
            child.localName == 'ul' ||
            child.localName == 'ol' ||
            child.localName == 'pre',
      );
      if (hasBlockChild) {
        if (tag == 'div' && element.attributes.isEmpty) {
          // A bare wrapper div adds nothing; splice its children up.
          _unwrap(element);
        }
        continue;
      }

      if (tag == 'div') {
        // Inline-only div: turn it into a paragraph so it reads correctly.
        final paragraph = dom.Element.tag('p');
        for (final node in element.nodes.toList()) {
          node.remove();
          paragraph.append(node);
        }
        _replaceNode(element, paragraph);
      } else {
        _unwrap(element);
      }
    }
  }

  static void _removeEmptyBlocks(dom.Node root) {
    for (final element in _allElements(root).reversed) {
      if (element.parentNode == null) continue;
      final tag = element.localName ?? '';
      if (!_blockTags.contains(tag)) continue;
      if (element.text.trim().isNotEmpty) continue;
      final hasMedia = element.querySelector('img, video, audio, iframe');
      if (hasMedia != null) continue;
      element.remove();
    }
  }

  static void _collapseLeadingBreaks(dom.Node root) {
    while (root.nodes.isNotEmpty) {
      final first = root.nodes.first;
      if (first is dom.Text && first.text.trim().isEmpty) {
        first.remove();
        continue;
      }
      if (first is dom.Element && first.localName == 'br') {
        first.remove();
        continue;
      }
      break;
    }
  }

  /// Replaces [node] with [replacement], fragment-safe.
  static void _replaceNode(dom.Node node, dom.Node replacement) {
    final parent = node.parentNode;
    if (parent == null) return;
    final index = parent.nodes.indexOf(node);
    node.remove();
    if (index < 0) {
      parent.nodes.add(replacement);
    } else {
      parent.nodes.insert(index, replacement);
    }
  }

  static List<dom.Element> _allElements(dom.Node root) {
    final results = <dom.Element>[];
    void walk(dom.Node node) {
      for (final child in node.nodes.toList()) {
        if (child is dom.Element) {
          results.add(child);
          walk(child);
        }
      }
    }

    walk(root);
    return results;
  }

  static String _serialize(dom.Node node) {
    if (node is dom.Element) return node.outerHtml;
    if (node is dom.Text) return _escape(node.text);
    return '';
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static const Set<String> _newlineAfter = <String>{
    'p',
    'div',
    'br',
    'li',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'pre',
    'tr',
    'figcaption',
    'section',
    'article',
    'hr',
  };

  static void _writeText(dom.Node node, StringBuffer buffer) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (_droppedTags.contains(tag)) return;
    for (final child in node.nodes) {
      _writeText(child, buffer);
    }
    if (_newlineAfter.contains(tag)) buffer.write('\n');
  }
}

class _SrcsetCandidate {
  const _SrcsetCandidate(this.url, this.width);

  final String url;
  final int width;
}
