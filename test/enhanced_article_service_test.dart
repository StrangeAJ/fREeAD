import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/enhanced_article_service.dart';

void main() {
  late EnhancedArticleService service;

  setUp(() {
    service = EnhancedArticleService();
  });

  String longParagraph(int i) =>
      'This is paragraph number $i of the article body, and it contains '
      'enough meaningful text, with several commas, clauses, and words, to '
      'be scored as real article content by the readability algorithm.';

  group('JSON-LD extraction', () {
    test('prefers articleBody from JSON-LD when present', () {
      final body = List.generate(6, longParagraph).join('\n\n');
      final html = '''
<html><head>
<script type="application/ld+json">
{"@type":"NewsArticle","headline":"JSON-LD Headline","articleBody":${_json(body)},
 "author":{"@type":"Person","name":"Jane Reporter"},"datePublished":"2026-07-01"}
</script>
</head><body><div id="junk">unrelated page chrome</div></body></html>''';

      final result = service.processHtml(html, 'https://example.com/story');
      expect(result, isNotNull);
      expect(result!['title'], 'JSON-LD Headline');
      expect(result['author'], 'Jane Reporter');
      expect(result['publishedTime'], '2026-07-01');
      expect(result['content'], contains('paragraph number 0'));
      expect(result['content'], contains('paragraph number 5'));
    });

    test('handles @graph wrapper and author lists', () {
      final body = List.generate(6, longParagraph).join('\n\n');
      final html = '''
<html><head>
<script type="application/ld+json">
{"@graph":[{"@type":"WebSite","name":"Site"},
 {"@type":"BlogPosting","headline":"Graph Headline","articleBody":${_json(body)},
  "author":[{"name":"A. One"},{"name":"B. Two"}]}]}
</script>
</head><body></body></html>''';

      final result = service.processHtml(html, 'https://example.com/x');
      expect(result, isNotNull);
      expect(result!['title'], 'Graph Headline');
      expect(result['author'], 'A. One, B. Two');
    });
  });

  group('Readability scoring', () {
    test('extracts main content and drops sidebar/nav boilerplate', () {
      final paragraphs =
          List.generate(8, (i) => '<p>${longParagraph(i)}</p>').join();
      final html = '''
<html><head><title>Page</title></head><body>
  <nav><a href="/a">Home</a><a href="/b">World</a></nav>
  <div class="sidebar"><p>Subscribe to our newsletter now, please, today, thanks.</p></div>
  <div class="article-body">$paragraphs</div>
  <footer><p>Copyright, some site, all rights reserved, contact, legal.</p></footer>
</body></html>''';

      final result = service.processHtml(html, 'https://example.com/story');
      expect(result, isNotNull);
      final content = result!['content'] as String;
      expect(content, contains('paragraph number 0'));
      expect(content, contains('paragraph number 7'));
      expect(content, isNot(contains('Subscribe to our newsletter')));
      expect(content, isNot(contains('Copyright')));
    });

    test('keeps elements whose class merely contains "ad" as a substring', () {
      final paragraphs =
          List.generate(6, (i) => '<p>${longParagraph(i)}</p>').join();
      final html = '''
<html><body>
  <div class="article-readable download-friendly">$paragraphs
    <p class="read-more-text">${longParagraph(99)}</p>
  </div>
</body></html>''';

      final result = service.processHtml(html, 'https://example.com/story');
      expect(result, isNotNull);
      final content = result!['content'] as String;
      // "readable", "download", "read-more" contain "ad"/"nav"-like
      // substrings but are NOT boilerplate — they must survive.
      expect(content, contains('paragraph number 99'));
      expect(content, contains('paragraph number 0'));
    });

    test('joins sibling containers holding the rest of the article', () {
      final part1 =
          List.generate(4, (i) => '<p>${longParagraph(i)}</p>').join();
      final part2 =
          List.generate(4, (i) => '<p>${longParagraph(i + 4)}</p>').join();
      final html = '''
<html><body><div id="wrapper">
  <div class="story-part">$part1</div>
  <div class="story-part">$part2</div>
</div></body></html>''';

      final result = service.processHtml(html, 'https://example.com/story');
      expect(result, isNotNull);
      final content = result!['content'] as String;
      expect(content, contains('paragraph number 0'));
      expect(content, contains('paragraph number 7'));
    });
  });

  group('Post-processing', () {
    test('promotes lazy-loaded image sources', () {
      final paragraphs =
          List.generate(6, (i) => '<p>${longParagraph(i)}</p>').join();
      final html = '''
<html><body><div class="content">
  <img src="data:image/gif;base64,R0lGOD" data-src="/images/photo.jpg" alt="pic">
  $paragraphs
</div></body></html>''';

      final result =
          service.processHtml(html, 'https://example.com/news/story.html');
      expect(result, isNotNull);
      expect(result!['content'],
          contains('src="https://example.com/images/photo.jpg"'));
    });

    test('resolves relative URLs against the article path', () {
      final paragraphs =
          List.generate(6, (i) => '<p>${longParagraph(i)}</p>').join();
      final html = '''
<html><body><div class="content">
  $paragraphs
  <p>See <a href="part2.html">part two, the sequel, continued</a> for more details, analysis, and context.</p>
</div></body></html>''';

      final result =
          service.processHtml(html, 'https://example.com/news/2026/story.html');
      expect(result, isNotNull);
      expect(result!['content'],
          contains('href="https://example.com/news/2026/part2.html"'));
    });

    test('uses og:title over the first h1', () {
      final paragraphs =
          List.generate(6, (i) => '<p>${longParagraph(i)}</p>').join();
      final html = '''
<html><head>
  <meta property="og:title" content="The Real Article Title">
</head><body>
  <h1>SITE MEGA BANNER</h1>
  <div class="content">$paragraphs</div>
</body></html>''';

      final result = service.processHtml(html, 'https://example.com/story');
      expect(result, isNotNull);
      expect(result!['title'], 'The Real Article Title');
    });
  });
}

/// Minimal JSON string encoder for embedding text in test fixtures.
String _json(String value) =>
    '"${value.replaceAll('\\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
