import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/rss/feed_discovery_service.dart';

/// Loads a fixture from `test/fixtures/`.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Serves canned documents per URL; anything unknown answers 404.
///
/// The service never touches the network in these tests.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes, {this.contentTypes = const <String, String>{}});

  /// url -> body.
  final Map<String, String> routes;

  /// url -> content-type header (defaults to `application/xml`).
  final Map<String, String> contentTypes;

  final List<String> requested = <String>[];

  /// Paths of everything that was requested, in order.
  List<String> get requestedPaths => [
    for (final url in requested) Uri.parse(url).path,
  ];

  /// When set, every request throws instead of answering.
  DioException? failure;

  /// Route key for [uri].
  ///
  /// `FeedDiscoveryService` builds its probe URLs with `Uri.replace`, which
  /// leaves empty `?` / `#` markers behind (`https://host/feed?#`). Those are
  /// meaningless to a server, so they are meaningless to the routing table
  /// here too.
  static String routeKey(Uri uri) => uri
      .toString()
      .replaceAll(RegExp(r'\?(?=#|$)'), '')
      .replaceAll(RegExp(r'#$'), '');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    final failWith = failure;
    if (failWith != null) throw failWith;

    final body = routes[routeKey(options.uri)];
    if (body == null) {
      return ResponseBody.fromBytes(
        utf8.encode('not found'),
        404,
        headers: {
          Headers.contentTypeHeader: <String>['text/plain'],
        },
      );
    }
    return ResponseBody.fromBytes(
      utf8.encode(body),
      200,
      headers: {
        Headers.contentTypeHeader: <String>[
          contentTypes[url] ?? 'application/xml; charset=utf-8',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

FeedDiscoveryService _serviceFor(_FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return FeedDiscoveryService(dio: dio);
}

void main() {
  group('normalizeInput', () {
    test('adds a scheme to bare hosts', () {
      expect(
        FeedDiscoveryService.normalizeInput('example.com'),
        'https://example.com',
      );
      expect(
        FeedDiscoveryService.normalizeInput('  blog.example.com/feed  '),
        'https://blog.example.com/feed',
      );
    });

    test('keeps existing schemes and rewrites feed://', () {
      expect(
        FeedDiscoveryService.normalizeInput('http://example.com/rss.xml'),
        'http://example.com/rss.xml',
      );
      expect(
        FeedDiscoveryService.normalizeInput('FEED://example.com/rss.xml'),
        'http://example.com/rss.xml',
      );
    });

    test('leaves empty input alone', () {
      expect(FeedDiscoveryService.normalizeInput('   '), '');
    });
  });

  group('discover', () {
    test('returns the input itself when it already is a feed', () async {
      final adapter = _FakeAdapter({
        'https://example.com/rss.xml': fixture('rss2.xml'),
      });
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      final found = await service.discover('example.com/rss.xml');

      expect(found, hasLength(1));
      expect(found.single.url, 'https://example.com/rss.xml');
      expect(found.single.title, 'Quiet Instrument Daily');
      expect(found.single.type, 'rss');
      // One request: the feed parsed straight away, no HTML scan or probing.
      expect(adapter.requested, ['https://example.com/rss.xml']);
    });

    test('detects Atom and JSON Feed documents', () async {
      final atomService = _serviceFor(
        _FakeAdapter({'https://a.example/atom': fixture('atom.xml')}),
      );
      addTearDown(atomService.dispose);
      final atom = await atomService.discover('https://a.example/atom');
      expect(atom.single.type, 'atom');
      expect(atom.single.title, 'Atom Notes');

      final jsonService = _serviceFor(
        _FakeAdapter(
          {'https://j.example/feed.json': fixture('jsonfeed.json')},
          contentTypes: {
            'https://j.example/feed.json': 'application/json; charset=utf-8',
          },
        ),
      );
      addTearDown(jsonService.dispose);
      final json = await jsonService.discover('https://j.example/feed.json');
      expect(json.single.type, 'json');
      expect(json.single.title, 'JSON Feed Journal');
    });

    test(
      'reads <link rel="alternate"> tags and resolves relative hrefs',
      () async {
        final adapter = _FakeAdapter(
          {
            'https://blog.example.com/': fixture('discovery_page.html'),
            'https://blog.example.com/feed.xml': fixture('rss2.xml'),
            'https://blog.example.com/atom.xml': fixture('atom.xml'),
          },
          contentTypes: {
            'https://blog.example.com/': 'text/html; charset=utf-8',
          },
        );
        final service = _serviceFor(adapter);
        addTearDown(service.dispose);

        final found = await service.discover('https://blog.example.com/');

        expect(found, hasLength(2));
        expect(found.map((f) => f.url), [
          'https://blog.example.com/feed.xml',
          'https://blog.example.com/atom.xml',
        ]);
        expect(found.first.title, 'Example Blog RSS');
        expect(found.first.type, 'rss');
        expect(found.last.type, 'atom');
        // `type="text/html"` is not a feed link and must be ignored.
        expect(found.map((f) => f.url), isNot(contains('/print')));
        // Advertised feeds short-circuit path probing.
        expect(adapter.requested.where((u) => u.contains('/rss')), isEmpty);
      },
    );

    test('keeps advertised candidates that cannot be verified', () async {
      // The page advertises feeds but they 404 - the user still gets the
      // candidates rather than an empty result.
      final adapter = _FakeAdapter(
        {'https://blog.example.com/': fixture('discovery_page.html')},
        contentTypes: {'https://blog.example.com/': 'text/html; charset=utf-8'},
      );
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      final found = await service.discover('https://blog.example.com/');

      expect(found, hasLength(2));
      expect(found.first.title, 'Example Blog RSS');
    });

    test('probes the usual paths when nothing is advertised', () async {
      const plainPage =
          '<html><head><title>Bare</title></head>'
          '<body><p>No feed links here.</p></body></html>';
      final adapter = _FakeAdapter(
        {
          'https://bare.example/': plainPage,
          'https://bare.example/rss.xml': fixture('rss2.xml'),
        },
        contentTypes: {'https://bare.example/': 'text/html; charset=utf-8'},
      );
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      final found = await service.discover('bare.example');

      expect(found, hasLength(1));
      expect(Uri.parse(found.single.url).path, '/rss.xml');
      expect(found.single.title, 'Quiet Instrument Daily');
      expect(found.single.siteUrl, 'https://bare.example');
      // `/feed` and `/feed/` are probed before `/rss.xml`.
      expect(adapter.requestedPaths, contains('/feed'));
      expect(
        adapter.requestedPaths.indexOf('/feed'),
        lessThan(adapter.requestedPaths.indexOf('/rss.xml')),
      );
    });

    test('returns nothing when the host is unreachable', () async {
      final adapter = _FakeAdapter(const <String, String>{})
        ..failure = DioException.connectionError(
          requestOptions: RequestOptions(path: '/'),
          reason: 'No route to host',
        );
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      expect(await service.discover('https://offline.example'), isEmpty);
    });

    test('returns nothing for empty input without any request', () async {
      final adapter = _FakeAdapter(const <String, String>{});
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      expect(await service.discover('  '), isEmpty);
      expect(adapter.requested, isEmpty);
    });

    test(
      'a page that is not a feed and has no candidates yields nothing',
      () async {
        final adapter = _FakeAdapter(
          {'https://empty.example/': '<html><body>Hello</body></html>'},
          contentTypes: {'https://empty.example/': 'text/html; charset=utf-8'},
        );
        final service = _serviceFor(adapter);
        addTearDown(service.dispose);

        expect(await service.discover('https://empty.example/'), isEmpty);
        // Every common path was probed before giving up.
        for (final path in FeedDiscoveryService.commonPaths) {
          if (path.startsWith('/?')) continue;
          expect(
            adapter.requestedPaths,
            contains(path),
            reason: 'expected a probe for $path',
          );
        }
        // The `/?feed=rss2` probe keeps its query.
        expect(adapter.requested.any((u) => u.contains('feed=rss2')), isTrue);
      },
    );
  });

  group('inspect', () {
    test('reads metadata for a candidate the user picked', () async {
      final adapter = _FakeAdapter({
        'https://example.com/rss.xml': fixture('rss2.xml'),
      });
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      final feed = await service.inspect('example.com/rss.xml');

      expect(feed, isNotNull);
      expect(feed!.title, 'Quiet Instrument Daily');
    });

    test('returns null when the URL is not a feed', () async {
      final adapter = _FakeAdapter(
        {'https://example.com/page': '<html><body>Not a feed</body></html>'},
        contentTypes: {'https://example.com/page': 'text/html; charset=utf-8'},
      );
      final service = _serviceFor(adapter);
      addTearDown(service.dispose);

      expect(await service.inspect('https://example.com/page'), isNull);
    });
  });

  group('DiscoveredFeed', () {
    test('is identified by its URL', () {
      const a = DiscoveredFeed(url: 'https://x.example/f', title: 'A');
      const b = DiscoveredFeed(url: 'https://x.example/f', title: 'B');
      const c = DiscoveredFeed(url: 'https://y.example/f', title: 'A');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('faviconUrlFor', () {
    test('is re-exported for callers of the discovery service', () {
      expect(
        faviconUrlFor('https://news.example.com/feed.xml'),
        contains('news.example.com'),
      );
    });
  });
}
