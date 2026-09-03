import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/article_highlight.dart';
import 'package:freead/providers/article_annotation_provider.dart';
import 'package:freead/screens/reader/highlight_injector.dart';

ArticleHighlight highlight(
  String text, {
  String id = 'h1',
  int start = 0,
  String color = '#FFEB3B',
  String? note,
}) {
  final DateTime now = DateTime(2026, 1, 1);
  return ArticleHighlight(
    id: id,
    articleId: 'a1',
    selectedText: text,
    startIndex: start,
    endIndex: start + text.length,
    color: color,
    note: note,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('plainText projection', () {
    test('concatenates every text node in document order', () {
      const String html = '<p>Hello <em>brave</em> world</p><p>Again.</p>';
      expect(
        HighlightInjector.plainText(html),
        equals('Hello brave worldAgain.'),
      );
    });

    test('ignores script and style content', () {
      const String html = '<p>Body</p><script>var x = 1;</script>';
      expect(HighlightInjector.plainText(html), equals('Body'));
    });

    test('is empty for empty input', () {
      expect(HighlightInjector.plainText(''), isEmpty);
      expect(HighlightInjector.plainText('   '), isEmpty);
    });
  });

  group('apply', () {
    test('returns the html untouched when there are no highlights', () {
      const String html = '<p>Nothing to mark.</p>';
      expect(
        HighlightInjector.apply(html, const <ArticleHighlight>[]),
        equals(html),
      );
    });

    test('wraps a range inside a single text node', () {
      const String html = '<p>The quick brown fox jumps.</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('quick brown', start: 4),
      ]);

      expect(
        result,
        equals(
          '<p>The <mark data-hl="h1" data-hl-color="#FFEB3B">quick brown'
          '</mark> fox jumps.</p>',
        ),
      );
      // The plain text projection must be unchanged by the injection.
      expect(
        HighlightInjector.plainText(result),
        equals(HighlightInjector.plainText(html)),
      );
    });

    test('splits a range that spans several text nodes', () {
      const String html = '<p>Hello <em>brave</em> world</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('brave world', start: 6),
      ]);

      expect(result, contains('<em><mark data-hl="h1"'));
      expect(result, contains('>brave</mark></em>'));
      expect(
        result,
        contains('<mark data-hl="h1" data-hl-color="#FFEB3B"> world</mark>'),
      );
      expect(HighlightInjector.plainText(result), equals('Hello brave world'));
    });

    test('skips highlights whose text is gone', () {
      const String html = '<p>The article was re-extracted.</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('a sentence that no longer exists'),
      ]);
      expect(result, equals(html));
      expect(result, isNot(contains('<mark')));
    });

    test('keeps unrelated highlights when one cannot be resolved', () {
      const String html = '<p>alpha beta gamma</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('missing', id: 'gone', start: 0),
        highlight('beta', id: 'keep', start: 6),
      ]);
      expect(result, contains('data-hl="keep"'));
      expect(result, isNot(contains('data-hl="gone"')));
    });

    test('applies several highlights in one pass', () {
      const String html = '<p>one two three four</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('one', id: 'a', start: 0, color: '#4CAF50'),
        highlight('three', id: 'b', start: 8, color: '#2196F3'),
      ]);

      expect(result, contains('data-hl="a" data-hl-color="#4CAF50"'));
      expect(result, contains('data-hl="b" data-hl-color="#2196F3"'));
      expect(HighlightInjector.plainText(result), equals('one two three four'));
    });

    test('picks the occurrence nearest to the stored startIndex', () {
      const String html = '<p>cat dog cat dog cat</p>';
      // Projection indices of "cat": 0, 8, 16. The stored index is 15.
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('cat', start: 15),
      ]);

      final int markIndex = HighlightInjector.plainText(
        result.substring(0, result.indexOf('<mark')),
      ).length;
      expect(markIndex, equals(16));
    });

    test('overlapping highlights: the earlier one wins', () {
      const String html = '<p>alpha beta</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('alpha beta', id: 'first', start: 0),
        highlight('beta', id: 'second', start: 6),
      ]);
      expect(result, contains('data-hl="first"'));
      expect(result, isNot(contains('data-hl="second"')));
    });

    test('normalizes malformed colours', () {
      const String html = '<p>colour test</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('colour', color: 'not-a-colour'),
      ]);
      expect(result, contains('data-hl-color="#FFEB3B"'));
    });

    test('preserves images and other markup around a highlight', () {
      const String html =
          '<p>Look <img src="https://e.com/a.png" alt="a"> here</p>';
      final String result = HighlightInjector.apply(html, <ArticleHighlight>[
        highlight('here'),
      ]);
      expect(result, contains('<img src="https://e.com/a.png" alt="a">'));
      expect(result, contains('<mark data-hl="h1"'));
    });
  });

  group('normalizeColor', () {
    test('accepts hashed and bare hex', () {
      expect(HighlightInjector.normalizeColor('#ff9800'), equals('#FF9800'));
      expect(HighlightInjector.normalizeColor('ff9800'), equals('#FF9800'));
    });

    test('falls back for null and garbage', () {
      expect(HighlightInjector.normalizeColor(null), equals('#FFEB3B'));
      expect(HighlightInjector.normalizeColor('red'), equals('#FFEB3B'));
    });
  });

  group('ArticleAnnotationProvider selection offsets', () {
    test('computes start/end from the plain text projection', () {
      final ArticleAnnotationProvider provider = ArticleAnnotationProvider();
      addTearDown(provider.dispose);

      provider.setArticleText(
        HighlightInjector.plainText('<p>Hello <em>brave</em> world</p>'),
      );
      provider.setSelection('brave world');

      expect(provider.selectedText, equals('brave world'));
      expect(provider.selectionStart, equals(6));
      expect(provider.selectionEnd, equals(17));
      expect(provider.hasSelection, isTrue);
    });

    test('falls back to 0 when the selection is not in the projection', () {
      final ArticleAnnotationProvider provider = ArticleAnnotationProvider();
      addTearDown(provider.dispose);

      provider.setArticleText('some body text');
      provider.setSelection('elsewhere');

      expect(provider.selectionStart, equals(0));
    });

    test('an empty selection clears the state', () {
      final ArticleAnnotationProvider provider = ArticleAnnotationProvider();
      addTearDown(provider.dispose);

      provider.setArticleText('body');
      provider.setSelection('body');
      provider.setSelection('   ');

      expect(provider.selectedText, isNull);
      expect(provider.hasSelection, isFalse);
    });
  });
}
