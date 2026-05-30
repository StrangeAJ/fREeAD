import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// HTML to Markdown converter inspired by Turndown.js
class HtmlToMarkdownConverter {
  /// Convert HTML string to Markdown
  String convert(String html) {
    if (html.isEmpty) return '';

    try {
      final document = html_parser.parse(html);
      final body = document.body;

      if (body == null) return '';

      // Clean up the HTML first
      _cleanupHtml(body);

      // Convert to markdown
      return _convertNode(body).trim();
    } catch (e) {
      print('Error converting HTML to Markdown: $e');
      return html; // Return original HTML as fallback
    }
  }

  /// Clean up HTML before conversion
  void _cleanupHtml(dom.Element element) {
    // Remove unwanted elements
    final unwantedTags = 'script, style, nav, header, footer, aside';
    final elements = element.querySelectorAll(unwantedTags);
    for (final el in elements) {
      el.remove();
    }

    // Remove empty paragraphs
    final paragraphs = element.querySelectorAll('p');
    for (final p in paragraphs) {
      if (p.text.trim().isEmpty && p.children.isEmpty) {
        p.remove();
      }
    }
  }

  /// Convert a DOM node to Markdown
  String _convertNode(dom.Node node) {
    final buffer = StringBuffer();

    if (node is dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        buffer.write(_escapeMarkdown(text));
      }
    } else if (node is dom.Element) {
      final tagName = node.localName?.toLowerCase() ?? '';

      switch (tagName) {
        case 'h1':
          buffer.write('\n# ${_getInnerText(node)}\n\n');
          break;
        case 'h2':
          buffer.write('\n## ${_getInnerText(node)}\n\n');
          break;
        case 'h3':
          buffer.write('\n### ${_getInnerText(node)}\n\n');
          break;
        case 'h4':
          buffer.write('\n#### ${_getInnerText(node)}\n\n');
          break;
        case 'h5':
          buffer.write('\n##### ${_getInnerText(node)}\n\n');
          break;
        case 'h6':
          buffer.write('\n###### ${_getInnerText(node)}\n\n');
          break;
        case 'p':
          final content = _convertChildren(node);
          if (content.trim().isNotEmpty) {
            buffer.write('\n\n$content\n\n');
          }
          break;
        case 'br':
          buffer.write('\n');
          break;
        case 'strong':
        case 'b':
          final content = _convertChildren(node);
          if (content.trim().isNotEmpty) {
            buffer.write('**$content**');
          }
          break;
        case 'em':
        case 'i':
          final content = _convertChildren(node);
          if (content.trim().isNotEmpty) {
            buffer.write('*$content*');
          }
          break;
        case 'code':
          final content = _getInnerText(node);
          if (content.trim().isNotEmpty) {
            buffer.write('`$content`');
          }
          break;
        case 'pre':
          final content = _getInnerText(node);
          if (content.trim().isNotEmpty) {
            buffer.write('\n```\n$content\n```\n\n');
          }
          break;
        case 'a':
          final href = node.attributes['href'];
          final content = _convertChildren(node);
          if (href != null && content.trim().isNotEmpty) {
            buffer.write('[$content]($href)');
          } else if (content.trim().isNotEmpty) {
            buffer.write(content);
          }
          break;
        case 'img':
          final src = node.attributes['src'];
          final alt = node.attributes['alt'] ?? '';
          if (src != null) {
            buffer.write('![$alt]($src)');
          }
          break;
        case 'ul':
          buffer.write('\n');
          for (final child in node.children) {
            if (child.localName == 'li') {
              final content = _convertChildren(child);
              if (content.trim().isNotEmpty) {
                buffer.write('- $content\n');
              }
            }
          }
          buffer.write('\n');
          break;
        case 'ol':
          buffer.write('\n');
          var counter = 1;
          for (final child in node.children) {
            if (child.localName == 'li') {
              final content = _convertChildren(child);
              if (content.trim().isNotEmpty) {
                buffer.write('$counter. $content\n');
                counter++;
              }
            }
          }
          buffer.write('\n');
          break;
        case 'blockquote':
          final content = _convertChildren(node);
          if (content.trim().isNotEmpty) {
            final lines = content.split('\n');
            for (final line in lines) {
              if (line.trim().isNotEmpty) {
                buffer.write('> $line\n');
              }
            }
            buffer.write('\n');
          }
          break;
        case 'hr':
          buffer.write('\n---\n\n');
          break;
        case 'table':
          buffer.write('\n');
          _convertTable(node, buffer);
          buffer.write('\n');
          break;
        case 'div':
        case 'span':
        case 'section':
        case 'article':
        case 'main':
          // For generic containers, just convert children
          buffer.write(_convertChildren(node));
          break;
        default:
          // For unknown tags, just convert children
          buffer.write(_convertChildren(node));
          break;
      }
    }

    return buffer.toString();
  }

  /// Convert child nodes of an element
  String _convertChildren(dom.Element element) {
    final buffer = StringBuffer();

    for (final child in element.nodes) {
      buffer.write(_convertNode(child));
    }

    return buffer.toString();
  }

  /// Get inner text of an element
  String _getInnerText(dom.Element element) {
    return element.text.trim();
  }

  /// Convert table to Markdown
  void _convertTable(dom.Element table, StringBuffer buffer) {
    final rows = table.querySelectorAll('tr');

    if (rows.isEmpty) return;

    var isFirstRow = true;
    for (final row in rows) {
      final cells = row.querySelectorAll('td, th');

      if (cells.isEmpty) continue;

      buffer.write('|');
      for (final cell in cells) {
        final content = _getInnerText(cell);
        buffer.write(' $content |');
      }
      buffer.write('\n');

      // Add separator row after first row (header)
      if (isFirstRow) {
        buffer.write('|');
        for (var i = 0; i < cells.length; i++) {
          buffer.write('---|');
        }
        buffer.write('\n');
        isFirstRow = false;
      }
    }
  }

  /// Escape special Markdown characters (only when necessary)
  String _escapeMarkdown(String text) {
    // Only escape the most critical characters that would break Markdown parsing
    // Don't escape parentheses, periods, or other characters that are commonly used in normal text
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('*', '\\*')
        .replaceAll('_', '\\_')
        .replaceAll('`', '\\`')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('#', '\\#');
  }
}
