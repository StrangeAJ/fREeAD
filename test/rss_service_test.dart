import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/rss/rss_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  late RssService rss;

  setUp(() => rss = RssService());
  tearDown(() => rss.dispose());

  group('RSS 2.0', () {
    const feedUrl = 'https://example.com/feed.xml';

    test('parses items, skipping ones without a link', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(articles.length, 3);
      expect(articles.first.title, 'The quiet instrument');
      expect(articles.every((a) => a.feedId == 'feed-1'), isTrue);
    });

    test('parses an RFC 822 pubDate with a numeric offset', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(
        articles.first.publishedDate.toUtc(),
        DateTime.utc(2026, 7, 1, 3, 0, 0),
      );
    });

    test('parses a pubDate without seconds and a two digit year', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(
        articles[1].publishedDate.toUtc(),
        DateTime.utc(2026, 6, 30, 22, 15),
      );
      expect(
        articles[2].publishedDate.toUtc(),
        DateTime.utc(1999, 11, 15, 17, 45, 26),
      );
    });

    test('keeps content:encoded as sanitised HTML', () {
      final article = rss
          .parseFeedXml(fixture('rss2.xml'), 'feed-1', feedUrl: feedUrl)
          .first;
      final content = article.content!;
      expect(content, contains('<h2>'));
      expect(content, contains('Why quiet matters'));
      expect(content, isNot(contains('<script')));
      expect(content, isNot(contains('window.tracker')));
      expect(content, isNot(contains('class=')));
      // Relative URLs resolve against the article link.
      expect(content, contains('https://example.com/related/story'));
      expect(content, contains('https://example.com/images/hero.jpg'));
    });

    test('description is plain text capped at 300 characters', () {
      final article = rss
          .parseFeedXml(fixture('rss2.xml'), 'feed-1', feedUrl: feedUrl)
          .first;
      expect(article.description, isNot(contains('<')));
      expect(article.description, contains('quiet instrument'));
      expect(article.description.length, lessThanOrEqualTo(303));
    });

    test('picks the widest media:content image', () {
      final article = rss
          .parseFeedXml(fixture('rss2.xml'), 'feed-1', feedUrl: feedUrl)
          .first;
      expect(article.imageUrl, 'https://cdn.example.com/large.jpg');
    });

    test('falls back to an image enclosure', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(articles[1].imageUrl, 'https://cdn.example.com/enclosure.jpg');
    });

    test('resolves relative item links against the feed URL', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(articles[1].url, 'https://example.com/2026/06/second-story');
    });

    test('uses a permalink guid when link is missing', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(articles[2].url, 'https://example.com/1999/legacy');
    });

    test('cleans authors, never returning "Unknown"', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
      );
      expect(articles[0].author, 'Jane Reporter');
      expect(articles[1].author, 'Sam Editor');
      expect(articles[2].author, isNull);
    });

    test('assigns the category id to every article', () {
      final articles = rss.parseFeedXml(
        fixture('rss2.xml'),
        'feed-1',
        feedUrl: feedUrl,
        categoryId: 'technology',
      );
      expect(articles.every((a) => a.categoryId == 'technology'), isTrue);
    });

    test('parses channel metadata', () {
      final feed = rss.parseFeedInfo(fixture('rss2.xml'), feedUrl);
      expect(feed.title, 'Quiet Instrument Daily');
      expect(feed.description, 'Long form reporting about & around technology.');
      expect(feed.siteUrl, 'https://example.com/');
      expect(feed.imageUrl, 'https://example.com/assets/logo.png');
      expect(feed.language, 'en-GB');
      expect(feed.url, feedUrl);
    });
  });

  group('Atom', () {
    const feedUrl = 'https://atom.example.org/feed.atom';

    test('parses entries with rel=alternate links', () {
      final articles = rss.parseFeedXml(
        fixture('atom.xml'),
        'atom-1',
        feedUrl: feedUrl,
      );
      expect(articles.length, 2);
      expect(articles.first.url, 'https://atom.example.org/posts/one');
      expect(articles.first.title, 'Fractional seconds and a Z suffix');
      expect(articles.first.author, 'Ada Writer');
    });

    test('parses fractional-second timestamps', () {
      final articles = rss.parseFeedXml(
        fixture('atom.xml'),
        'atom-1',
        feedUrl: feedUrl,
      );
      expect(
        articles.first.publishedDate.toUtc(),
        DateTime.utc(2026, 7, 2, 9, 15, 30, 250),
      );
    });

    test('resolves relative entry links', () {
      final articles = rss.parseFeedXml(
        fixture('atom.xml'),
        'atom-1',
        feedUrl: feedUrl,
      );
      expect(articles[1].url, 'https://atom.example.org/posts/two');
    });

    test('keeps escaped HTML content', () {
      final articles = rss.parseFeedXml(
        fixture('atom.xml'),
        'atom-1',
        feedUrl: feedUrl,
      );
      expect(articles.first.content, contains('<em>strong point</em>'));
    });

    test('parses feed metadata including the site link and logo', () {
      final feed = rss.parseFeedInfo(fixture('atom.xml'), feedUrl);
      expect(feed.title, 'Atom Notes');
      expect(feed.description, 'Short notes published as an Atom feed.');
      expect(feed.siteUrl, 'https://atom.example.org/');
      expect(feed.imageUrl, 'https://atom.example.org/logo.png');
      expect(feed.language, 'en-US');
    });
  });

  group('RSS 1.0 (RDF)', () {
    const feedUrl = 'https://rdf.example.net/index.rdf';

    test('parses items and dc:date', () {
      final articles = rss.parseFeedXml(
        fixture('rdf.xml'),
        'rdf-1',
        feedUrl: feedUrl,
      );
      expect(articles.length, 2);
      expect(articles.first.title, 'Story A');
      expect(articles.first.author, 'Ola Nordmann');
      expect(
        articles.first.publishedDate.toUtc(),
        DateTime.utc(2026, 6, 29, 12, 5),
      );
      expect(articles.first.content, contains('Body of story A.'));
    });

    test('parses channel metadata', () {
      final feed = rss.parseFeedInfo(fixture('rdf.xml'), feedUrl);
      expect(feed.title, 'RDF Wire');
      expect(feed.siteUrl, 'https://rdf.example.net/');
      expect(feed.language, 'de-DE');
    });
  });

  group('JSON Feed', () {
    const feedUrl = 'https://json.example.io/feed.json';

    test('parses items with html and text content', () {
      final articles = rss.parseFeedXml(
        fixture('jsonfeed.json'),
        'json-1',
        feedUrl: feedUrl,
      );
      expect(articles.length, 2);
      expect(articles.first.title, 'Hello from JSON Feed');
      expect(articles.first.author, 'Jo Author');
      expect(articles.first.content, contains('The body of the JSON post.'));
      expect(articles.first.imageUrl, 'https://json.example.io/img/big.png');
      expect(
        articles.first.publishedDate.toUtc(),
        DateTime.utc(2026, 7, 3, 12),
      );
      expect(articles[1].url, 'https://json.example.io/posts/relative');
      expect(articles[1].content, contains('Plain text content only.'));
    });

    test('parses feed metadata', () {
      final feed = rss.parseFeedInfo(fixture('jsonfeed.json'), feedUrl);
      expect(feed.title, 'JSON Feed Journal');
      expect(feed.siteUrl, 'https://json.example.io/');
      expect(feed.imageUrl, 'https://json.example.io/icon.png');
      expect(feed.language, 'en');
    });
  });

  group('Ids and detection', () {
    test('article ids are unpadded base64 of the link (v2 compatible)', () {
      expect(
        RssService.articleIdFor('https://example.com/a'),
        'aHR0cHM6Ly9leGFtcGxlLmNvbS9h',
      );
      expect(RssService.articleIdFor('https://e.com/x'), isNot(contains('=')));
    });

    test('feed ids are unpadded base64 of the URL', () {
      expect(
        RssService.feedIdFor('https://example.com/feed.xml'),
        isNot(contains('=')),
      );
    });

    test('looksLikeFeed recognises every supported flavour', () {
      expect(RssService.looksLikeFeed(fixture('rss2.xml')), isTrue);
      expect(RssService.looksLikeFeed(fixture('atom.xml')), isTrue);
      expect(RssService.looksLikeFeed(fixture('rdf.xml')), isTrue);
      expect(RssService.looksLikeFeed(fixture('jsonfeed.json')), isTrue);
      expect(RssService.looksLikeFeed(fixture('discovery_page.html')), isFalse);
      expect(RssService.looksLikeFeed('{"not":"a feed"}'), isFalse);
      expect(RssService.looksLikeFeed('plain text'), isFalse);
      expect(RssService.looksLikeFeed(''), isFalse);
    });

    test('an unsupported XML document throws FeedFormatException', () {
      expect(
        () => rss.parseFeedXml(
          '<?xml version="1.0"?><html><body>hi</body></html>',
          'x',
          feedUrl: 'https://e.com/f',
        ),
        throwsA(isA<FeedFormatException>()),
      );
    });

    test('malformed XML throws FeedFormatException', () {
      expect(
        () => rss.parseFeedXml('<rss><channel>', 'x', feedUrl: 'https://e.com'),
        throwsA(isA<FeedFormatException>()),
      );
    });
  });

  group('Charset decoding', () {
    test('honours the XML prologue encoding', () {
      // 0xE9 is 'é' in latin-1 but invalid UTF-8.
      final bytes = <int>[
        ...'<?xml version="1.0" encoding="ISO-8859-1"?><rss><channel><title>caf'
            .codeUnits,
        0xE9,
        ...'</title></channel></rss>'.codeUnits,
      ];
      final decoded = RssService.decodeBody(bytes);
      expect(decoded, contains('café'));
    });

    test('honours the transport charset', () {
      final bytes = <int>[...'caf'.codeUnits, 0xE9];
      expect(
        RssService.decodeBody(bytes, contentType: 'text/xml; charset=utf-8'),
        isNot(contains('café')),
      );
      expect(
        RssService.decodeBody(
          bytes,
          contentType: 'text/xml; charset=windows-1252',
        ),
        'café',
      );
    });

    test('strips a UTF-8 BOM', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...'<rss/>'.codeUnits];
      expect(RssService.decodeBody(bytes), '<rss/>');
    });
  });

  test('RSSService alias still exists', () {
    final alias = RSSService();
    expect(alias, isA<RssService>());
    alias.dispose();
  });
}
