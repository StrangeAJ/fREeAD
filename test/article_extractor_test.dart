import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/app_settings.dart';
import 'package:freead/services/extraction/article_extractor.dart';
import 'package:freead/services/extraction/extraction_result.dart';
import 'package:freead/services/extraction/html_fetcher.dart';
import 'package:freead/services/extraction/readability.dart';
import 'package:freead/services/extraction/webview_extractor.dart';

/// A paragraph long enough (and comma-rich enough) to score as real prose.
String _longParagraph(int i) =>
    'This is paragraph number $i of the article body, and it contains '
    'enough meaningful text, with several commas, clauses, and words, to '
    'be scored as real article content by the readability algorithm.';

String _paragraphs(int count) =>
    List.generate(count, (i) => '<p>${_longParagraph(i)}</p>').join();

/// A page whose article body is unambiguous, so readability rates it good.
String _goodPage({String title = 'A good article', int paragraphs = 10}) =>
    '<!doctype html><html><head><title>$title</title>'
    '<meta property="og:site_name" content="Fixture Times">'
    '</head><body><header><nav><a href="/">Home</a></nav></header>'
    '<article>${_paragraphs(paragraphs)}</article>'
    '<footer><p>Copyright</p></footer></body></html>';

/// A page with almost no text: something comes back, but never enough.
const String _thinPage =
    '<!doctype html><html><head><title>Thin</title></head>'
    '<body><div id="root"><p>Short teaser.</p></div></body></html>';

/// Serves canned pages per URL and records what was asked for.
class _FakeFetcher extends HtmlFetcher {
  _FakeFetcher(this.pages, {this.ampUrls = const <String, String>{}});

  final Map<String, String> pages;
  final Map<String, String> ampUrls;
  final List<String> requested = <String>[];

  /// Thrown instead of answering, when set.
  FetchException? failure;

  @override
  Future<FetchedPage> fetch(String url, {bool mobileUa = false}) async {
    requested.add(url);
    final failWith = failure;
    if (failWith != null) throw failWith;
    final html = pages[url];
    if (html == null) {
      throw FetchException('Nothing at $url', statusCode: 404);
    }
    return FetchedPage(
      finalUrl: url,
      statusCode: 200,
      html: html,
      ampUrl: ampUrls[url],
    );
  }
}

/// Stands in for the headless browser tier.
class _FakeWebview extends WebviewExtractor {
  _FakeWebview({this.result});

  ExtractionResult? result;
  int calls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<ExtractionResult?> extract(String url) async {
    calls++;
    return result;
  }
}

ExtractionResult _webviewResult({int words = 900, double quality = 0.9}) =>
    ExtractionResult(
      html: '<p>Rendered by the browser tier.</p>',
      text: 'Rendered by the browser tier.',
      title: 'Browser title',
      wordCount: words,
      quality: quality,
      source: ExtractionSource.webview,
    );

void main() {
  const url = 'https://example.com/story';
  const ampUrl = 'https://example.com/story/amp';

  group('ArticleExtractor - auto engine', () {
    test(
      'returns the HTTP result when it is good and skips later tiers',
      () async {
        final fetcher = _FakeFetcher({url: _goodPage()});
        final webview = _FakeWebview(result: _webviewResult());
        final extractor = ArticleExtractor(
          fetcher: fetcher,
          readability: const Readability(),
          webview: webview,
        );

        final result = await extractor.extract(url);

        expect(result, isNotNull);
        expect(result!.source, ExtractionSource.http);
        expect(result.isGood, isTrue);
        expect(result.wordCount, greaterThanOrEqualTo(150));
        expect(webview.calls, 0, reason: 'a good HTTP result ends the run');
        expect(fetcher.requested, [url]);
      },
    );

    test('falls back to the AMP page advertised by the article', () async {
      final fetcher = _FakeFetcher(
        {url: _thinPage, ampUrl: _goodPage(title: 'AMP body')},
        ampUrls: {url: ampUrl},
      );
      final webview = _FakeWebview(result: _webviewResult());
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
        webview: webview,
      );

      final result = await extractor.extract(url);

      expect(result!.source, ExtractionSource.amp);
      expect(result.isGood, isTrue);
      expect(fetcher.requested, [url, ampUrl]);
      expect(webview.calls, 0);
    });

    test('falls through to the WebView when HTTP and AMP are thin', () async {
      final fetcher = _FakeFetcher({url: _thinPage});
      final webview = _FakeWebview(result: _webviewResult());
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
        webview: webview,
      );

      final result = await extractor.extract(url);

      expect(webview.calls, 1);
      expect(result!.source, ExtractionSource.webview);
      expect(result.isGood, isTrue);
    });

    test('returns the longest partial when no tier is good', () async {
      final fetcher = _FakeFetcher({url: _goodPage(paragraphs: 2)});
      final webview = _FakeWebview(
        result: _webviewResult(words: 20, quality: 0.2),
      );
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
        webview: webview,
      );

      final result = await extractor.extract(url);

      expect(webview.calls, 1);
      expect(result, isNotNull);
      expect(result!.isGood, isFalse);
      expect(
        result.source,
        ExtractionSource.http,
        reason: 'the HTTP partial has more words than the WebView one',
      );
    });
  });

  group('ArticleExtractor - engine selection', () {
    test('fast never starts the WebView', () async {
      final fetcher = _FakeFetcher({url: _thinPage});
      final webview = _FakeWebview(result: _webviewResult());
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
        webview: webview,
      );

      final result = await extractor.extract(
        url,
        engine: ExtractionEngine.fast,
      );

      expect(webview.calls, 0);
      expect(result, isNotNull);
      expect(result!.source, ExtractionSource.http);
    });

    test(
      'browser tries the WebView first and skips HTTP when it is good',
      () async {
        final fetcher = _FakeFetcher({url: _goodPage()});
        final webview = _FakeWebview(result: _webviewResult());
        final extractor = ArticleExtractor(
          fetcher: fetcher,
          readability: const Readability(),
          webview: webview,
        );

        final result = await extractor.extract(
          url,
          engine: ExtractionEngine.browser,
        );

        expect(webview.calls, 1);
        expect(fetcher.requested, isEmpty);
        expect(result!.source, ExtractionSource.webview);
      },
    );

    test(
      'browser falls back to HTTP when the WebView returns nothing',
      () async {
        final fetcher = _FakeFetcher({url: _goodPage()});
        final webview = _FakeWebview();
        final extractor = ArticleExtractor(
          fetcher: fetcher,
          readability: const Readability(),
          webview: webview,
        );

        final result = await extractor.extract(
          url,
          engine: ExtractionEngine.browser,
        );

        expect(webview.calls, 1);
        expect(fetcher.requested, [url]);
        expect(result!.source, ExtractionSource.http);
      },
    );
  });

  group('ArticleExtractor - RSS fallback and failures', () {
    const rssHtml =
        '<script>tracker();</script>'
        '<p class="lead">The feed shipped the whole post, so the reader can '
        'show something useful even when the site refuses to answer.</p>'
        '<p>It continues for several sentences, with commas and clauses, so '
        'that the plain text projection is comfortably longer than the two '
        'hundred character floor the fallback applies before it accepts the '
        'feed body as an article.</p>';

    test('uses the sanitised RSS body when every tier fails', () async {
      final fetcher = _FakeFetcher(const <String, String>{})
        ..failure = FetchException(
          'The site blocked automated access (HTTP 403)',
          statusCode: 403,
        );
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
      );

      final result = await extractor.extract(url, rssHtml: rssHtml);

      expect(result, isNotNull);
      expect(result!.source, ExtractionSource.rss);
      expect(result.html, isNot(contains('<script')));
      expect(result.html, isNot(contains('class=')));
      expect(result.text, contains('the whole post'));
    });

    test(
      'throws ExtractionException carrying the fetch message and status',
      () async {
        final fetcher = _FakeFetcher(const <String, String>{})
          ..failure = FetchException(
            'The site blocked automated access (HTTP 403)',
            statusCode: 403,
          );
        final extractor = ArticleExtractor(
          fetcher: fetcher,
          readability: const Readability(),
        );

        await expectLater(
          extractor.extract(url),
          throwsA(
            isA<ExtractionException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.userMessage, 'userMessage', contains('403')),
          ),
        );
        expect(extractor.lastError(url), contains('403'));
      },
    );

    test('rejects an empty url without touching the network', () async {
      final fetcher = _FakeFetcher(const <String, String>{});
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
      );

      await expectLater(
        extractor.extract('   '),
        throwsA(isA<ExtractionException>()),
      );
      expect(fetcher.requested, isEmpty);
    });
  });

  group('ArticleExtractor - memoisation', () {
    test('caches per URL and refetches only when forced', () async {
      final fetcher = _FakeFetcher({url: _goodPage()});
      final extractor = ArticleExtractor(
        fetcher: fetcher,
        readability: const Readability(),
      );

      final first = await extractor.extract(url);
      final second = await extractor.extract(url);

      expect(fetcher.requested, [url]);
      expect(identical(first, second), isTrue);
      expect(extractor.cached(url), same(first));

      await extractor.extract(url, force: true);
      expect(fetcher.requested, [url, url]);

      extractor.clearCache();
      expect(extractor.cached(url), isNull);
    });
  });
}
