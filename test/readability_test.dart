import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:freead/services/extraction/extraction_result.dart';
import 'package:freead/services/extraction/readability.dart';

/// Loads a fixture from `test/fixtures/html/`.
String fixture(String name) =>
    File('test/fixtures/html/$name').readAsStringSync();

/// A paragraph long enough (and comma-rich enough) to score as real prose.
String longParagraph(int i) =>
    'This is paragraph number $i of the article body, and it contains '
    'enough meaningful text, with several commas, clauses, and words, to '
    'be scored as real article content by the readability algorithm.';

String paragraphs(int count, {int start = 0}) => List.generate(
  count,
  (i) => '<p>${longParagraph(start + i)}</p>',
).join();

/// Minimal JSON string encoder for embedding text in inline fixtures.
String jsonString(String value) =>
    '"${value.replaceAll('\\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

void main() {
  const readability = Readability();

  group('JSON-LD extraction', () {
    test('prefers articleBody from JSON-LD when present', () {
      final body = List.generate(6, longParagraph).join('\n\n');
      final html =
          '''
<html><head>
<script type="application/ld+json">
{"@type":"NewsArticle","headline":"JSON-LD Headline","articleBody":${jsonString(body)},
 "author":{"@type":"Person","name":"Jane Reporter"},"datePublished":"2026-07-01"}
</script>
</head><body><div id="junk">unrelated page chrome</div></body></html>''';

      final result = readability.parse(html, 'https://example.com/story');
      expect(result, isNotNull);
      expect(result!.title, 'JSON-LD Headline');
      expect(result.author, 'Jane Reporter');
      expect(result.publishedAt, '2026-07-01');
      expect(result.html, contains('paragraph number 0'));
      expect(result.html, contains('paragraph number 5'));
    });

    test('handles @graph wrapper and author lists', () {
      final result = readability.parse(
        fixture('jsonld.html'),
        'https://structured.example/x',
      );
      expect(result, isNotNull);
      expect(result!.title, 'Structured data wins');
      expect(result.author, 'A. One, B. Two');
      expect(result.leadImageUrl, 'https://structured.example/lead.jpg');
      expect(result.publishedAt, '2026-06-30T11:00:00Z');
      expect(result.html, contains('paragraph number 0'));
      expect(result.html, contains('paragraph number 5'));
      expect(result.isGood, isTrue);
    });
  });

  group('Readability scoring', () {
    test('extracts main content and drops sidebar/nav boilerplate', () {
      final html =
          '''
<html><head><title>Page</title></head><body>
  <nav><a href="/a">Home</a><a href="/b">World</a></nav>
  <div class="sidebar"><p>Subscribe to our newsletter now, please, today, thanks.</p></div>
  <div class="article-body">${paragraphs(8)}</div>
  <footer><p>Copyright, some site, all rights reserved, contact, legal.</p></footer>
</body></html>''';

      final result = readability.parse(html, 'https://example.com/story');
      expect(result, isNotNull);
      expect(result!.html, contains('paragraph number 0'));
      expect(result.html, contains('paragraph number 7'));
      expect(result.html, isNot(contains('Subscribe to our newsletter')));
      expect(result.html, isNot(contains('Copyright')));
    });

    test('keeps elements whose class merely contains "ad" as a substring', () {
      final html =
          '''
<html><body>
  <div class="article-readable download-friendly">${paragraphs(6)}
    <p class="read-more-text">${longParagraph(99)}</p>
  </div>
</body></html>''';

      final result = readability.parse(html, 'https://example.com/story');
      expect(result, isNotNull);
      // "readable", "download" and "read-more" contain boilerplate-looking
      // substrings but are NOT boilerplate - they must survive.
      expect(result!.html, contains('paragraph number 99'));
      expect(result.html, contains('paragraph number 0'));
    });

    test('joins sibling containers holding the rest of the article', () {
      final result = readability.parse(
        fixture('div_soup.html'),
        'https://soup.example/story',
      );
      expect(result, isNotNull);
      expect(result!.html, contains('paragraph number 0'));
      expect(result.html, contains('paragraph number 7'));
      expect(result.html, isNot(contains('Advertisement')));
      expect(result.isGood, isTrue);
    });

    test('handles a semantic <article> page', () {
      final result = readability.parse(
        fixture('article_tag.html'),
        'https://example.com/news/semantic',
      );
      expect(result, isNotNull);
      expect(result!.title, 'The semantic article');
      expect(result.siteName, 'Example News');
      expect(result.author, 'Alex Byline');
      expect(result.html, contains('paragraph number 7'));
      expect(result.html, contains('<blockquote>'));
      expect(result.html, contains('figcaption'));
      expect(result.html, isNot(contains('Related')));
      expect(result.html, isNot(contains('Copyright')));
      expect(result.wordCount, greaterThan(150));
      expect(result.isGood, isTrue);
      // Images are resolved against the page URL.
      expect(result.html, contains('https://example.com/images/inline.jpg'));
    });
  });

  group('Post-processing', () {
    test('promotes lazy-loaded image sources', () {
      final html =
          '''
<html><body><div class="content">
  <img src="data:image/gif;base64,R0lGOD" data-src="/images/photo.jpg" alt="pic">
  ${paragraphs(6)}
</div></body></html>''';

      final result = readability.parse(
        html,
        'https://example.com/news/story.html',
      );
      expect(result, isNotNull);
      expect(
        result!.html,
        contains('src="https://example.com/images/photo.jpg"'),
      );
    });

    test('resolves relative URLs against the article path', () {
      final html =
          '''
<html><body><div class="content">
  ${paragraphs(6)}
  <p>See <a href="part2.html">part two, the sequel, continued</a> for more details, analysis, and context.</p>
</div></body></html>''';

      final result = readability.parse(
        html,
        'https://example.com/news/2026/story.html',
      );
      expect(result, isNotNull);
      expect(
        result!.html,
        contains('href="https://example.com/news/2026/part2.html"'),
      );
    });

    test('uses og:title over the first h1', () {
      final html =
          '''
<html><head>
  <meta property="og:title" content="The Real Article Title">
</head><body>
  <h1>SITE MEGA BANNER</h1>
  <div class="content">${paragraphs(6)}</div>
</body></html>''';

      final result = readability.parse(html, 'https://example.com/story');
      expect(result, isNotNull);
      expect(result!.title, 'The Real Article Title');
    });

    test('recovers lazy images, srcsets and pictures; drops tracking pixels', () {
      final result = readability.parse(
        fixture('lazy_images.html'),
        'https://lazy.example/news/story.html',
      );
      expect(result, isNotNull);
      expect(
        result!.html,
        contains('https://lazy.example/images/photo.jpg'),
      );
      // The largest srcset candidate wins.
      expect(result.html, contains('https://lazy.example/images/wide-1600.jpg'));
      expect(result.html, isNot(contains('wide-400')));
      expect(result.html, isNot(contains('tracker.example')));
      expect(result.html, isNot(contains('data:image')));
      expect(
        result.html,
        contains('href="https://lazy.example/news/part2.html"'),
      );
    });

    test('sanitises the output: no scripts, no classes', () {
      final html =
          '''
<html><body><div class="entry-content">
  ${paragraphs(6)}
  <script>tracker();</script>
</div></body></html>''';
      final result = readability.parse(html, 'https://example.com/x');
      expect(result, isNotNull);
      expect(result!.html, isNot(contains('<script')));
      expect(result.html, isNot(contains('tracker()')));
      expect(result.html, isNot(contains('class=')));
    });
  });

  group('Quality and partial detection', () {
    test('flags JavaScript-only pages as partial with zero quality', () {
      final result = readability.parse(
        fixture('js_required.html'),
        'https://spa.example/app',
      );
      // Either nothing at all, or a partial Open Graph teaser.
      if (result != null) {
        expect(result.partial, isTrue);
        expect(result.quality, 0);
        expect(result.isGood, isFalse);
      }
    });

    test('a nav-heavy page scores low', () {
      final links = List.generate(
        30,
        (i) => '<a href="/section/$i">Section number $i of the site</a>',
      ).join(' ');
      final html = '<html><body><div id="main"><p>$links</p></div></body></html>';
      final result = readability.parse(html, 'https://links.example/');
      if (result != null) {
        expect(result.isGood, isFalse);
      }
    });

    test('empty input returns null', () {
      expect(readability.parse('', 'https://example.com'), isNull);
      expect(readability.parse('   ', 'https://example.com'), isNull);
    });

    test('result survives a JSON round trip', () {
      final result = readability.parse(
        fixture('article_tag.html'),
        'https://example.com/news/semantic',
      );
      expect(result, isNotNull);
      final json = result!.toJson();
      final restored = ExtractionResult.fromJson(json);
      expect(restored.html, result.html);
      expect(restored.wordCount, result.wordCount);
      expect(restored.quality, result.quality);
      expect(restored.title, result.title);
      expect(restored.partial, result.partial);
    });
  });

  group('CSS selector safety', () {
    // The `html` package only implements a subset of CSS. `:scope`, `:has()`
    // and other functional pseudo classes throw at evaluation time and were
    // the root cause of the v2 extractor silently returning null.
    test('every selector used by Readability is supported', () {
      final selectors = <String>{
        'script[type="application/ld+json"]',
        '[itemprop="articleBody"]',
        '[property="articleBody"]',
        'meta[property="og:site_name"]',
        'meta[property="og:title"]',
        'meta[name="twitter:title"]',
        'meta[property="og:image"]',
        'meta[name="twitter:image"]',
        'meta[name="twitter:image:src"]',
        'meta[name="author"]',
        'meta[property="article:author"]',
        'meta[name="parsely-author"]',
        'meta[property="article:published_time"]',
        'meta[name="date"]',
        'meta[name="parsely-pub-date"]',
        'meta[itemprop="datePublished"]',
        'meta[property="og:description"]',
        'meta[name="description"]',
        'meta[name="twitter:description"]',
        'time[datetime]',
        '[rel="author"]',
        '[itemprop="author"]',
        '.author',
        '.byline',
        '.by-author',
        '.article-author',
        'h1',
        'title',
        'article',
        'main',
        'p, td, pre, blockquote',
        'h1, h2',
        'p, div',
        'p, div, section',
        'img',
        'img[src]',
        'a[href]',
        'a',
        'blockquote',
        'figure',
        'table',
        'tr',
        'noscript',
        'picture',
        'source',
        'div',
        '*',
        'img, video, audio, picture, figure',
        'img, video, audio, iframe',
        '#__next',
        '#root',
        '#app',
        '#__nuxt',
        'app-root',
        'link[rel="amphtml"]',
        'link[rel="canonical"]',
        'link',
        // Every site specific selector.
        ...Readability.siteSpecificSelectors.values.expand((v) => v),
      };

      final document = _sampleDocument();
      for (final selector in selectors) {
        expect(
          () => document.querySelectorAll(selector),
          returnsNormally,
          reason: 'selector "$selector" is not supported by package:html',
        );
      }
    });

    test('the v2 bug selector really does throw', () {
      final document = _sampleDocument();
      expect(() => document.querySelectorAll(':scope > div'), throwsA(anything));
    });
  });
}

/// A document exercising the shapes the selectors above look for.
dom.Document _sampleDocument() => html_parser.parse('''
<html><head>
  <title>Sample</title>
  <meta property="og:title" content="T">
  <link rel="canonical" href="https://e.com/x">
  <link rel="amphtml" href="https://e.com/amp">
  <script type="application/ld+json">{}</script>
</head>
<body>
  <app-root></app-root>
  <div id="__next"><div id="root"><div id="app"><div id="__nuxt"></div></div></div></div>
  <article class="post-content prose entry-content article-body">
    <section name="articleBody" itemprop="articleBody">
      <h1>H</h1><h2>H2</h2>
      <p class="Normal">Text</p>
      <div data-component="text-block" data-testid="ArticleBody">Block</div>
      <blockquote>Q</blockquote>
      <figure><img src="/a.png"><figcaption>C</figcaption></figure>
      <table><tr><td>c</td></tr></table>
      <picture><source srcset="/a.png"><img src="/a.png"></picture>
      <noscript><img src="https://e.com/n.png"></noscript>
      <a href="/l" rel="author">L</a>
      <time datetime="2026-01-01"></time>
      <pre>code</pre>
      <video></video><audio></audio><iframe></iframe>
    </section>
  </article>
</body></html>
''');
