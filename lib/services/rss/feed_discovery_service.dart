import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../utils/app_logger.dart';
import 'rss_service.dart';

export '../../utils/text_utils.dart' show faviconUrlFor;

/// A feed found on (or behind) a site URL.
class DiscoveredFeed {
  const DiscoveredFeed({
    required this.url,
    required this.title,
    this.type = 'rss',
    this.siteUrl,
  });

  final String url;
  final String title;

  /// `rss`, `atom` or `json`.
  final String type;

  /// Page the feed belongs to, when discovery started from a site URL.
  final String? siteUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DiscoveredFeed && other.url == url);

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiscoveredFeed($title, $url)';
}

/// Finds feeds for an arbitrary user input: a feed URL, a site URL or a
/// bare host name.
class FeedDiscoveryService {
  FeedDiscoveryService({Dio? dio, RssService? rssService})
    : _rss = rssService ?? RssService(dio: dio),
      _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      responseType: ResponseType.bytes,
      followRedirects: true,
      maxRedirects: 5,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
    );
  }

  final Dio _dio;
  final RssService _rss;

  /// Paths probed when a site does not advertise its feed.
  static const List<String> commonPaths = <String>[
    '/feed',
    '/feed/',
    '/rss',
    '/rss.xml',
    '/feed.xml',
    '/atom.xml',
    '/index.xml',
    '/blog/feed',
    '/?feed=rss2',
  ];

  static const Set<String> _feedMimeTypes = <String>{
    'application/rss+xml',
    'application/atom+xml',
    'application/feed+json',
    'application/json',
    'application/xml',
    'text/xml',
    'application/rdf+xml',
  };

  /// Normalises user input into an absolute URL.
  static String normalizeInput(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    value = value.replaceFirst(
      RegExp(r'^feed://', caseSensitive: false),
      'http://',
    );
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      value = 'https://$value';
    }
    return value;
  }

  /// Discovers feeds for [input].
  ///
  /// Returns an empty list when nothing was found. Never throws for network
  /// problems - those simply produce no candidates.
  Future<List<DiscoveredFeed>> discover(String input) async {
    final url = normalizeInput(input);
    if (url.isEmpty) return const <DiscoveredFeed>[];

    // 1. The input may already be a feed.
    final direct = await _tryFeed(url);
    if (direct != null) return <DiscoveredFeed>[direct];

    // 2. Look for <link rel="alternate"> in the page head.
    final html = await _fetchText(url);
    final results = <DiscoveredFeed>[];
    if (html != null) {
      results.addAll(_fromHtml(html, url));
    }
    if (results.isNotEmpty) {
      return _verify(results);
    }

    // 3. Probe the usual suspects.
    final base = Uri.tryParse(url);
    if (base == null) return const <DiscoveredFeed>[];
    // `Uri.replace(query: '', fragment: '')` sets *empty* (non-null) query/
    // fragment components, so `hasQuery`/`hasFragment` stay true and the
    // rendered URL keeps a stray `?#` suffix. Build a fresh origin instead.
    final origin = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );

    for (final path in commonPaths) {
      final candidate = _joinPath(origin, path);
      if (candidate == url) continue;
      final found = await _tryFeed(candidate);
      if (found != null) {
        results.add(
          DiscoveredFeed(
            url: found.url,
            title: found.title,
            type: found.type,
            siteUrl: origin.toString(),
          ),
        );
        if (results.length >= 3) break;
      }
    }

    return results;
  }

  /// Reads feed metadata for a candidate the user picked.
  Future<DiscoveredFeed?> inspect(String url) => _tryFeed(normalizeInput(url));

  void dispose() {
    try {
      _dio.close(force: true);
    } catch (_) {
      // Already closed.
    }
    _rss.dispose();
  }

  // ---------------------------------------------------------------------------

  Future<DiscoveredFeed?> _tryFeed(String url) async {
    final body = await _fetchText(url);
    if (body == null) return null;
    if (!RssService.looksLikeFeed(body)) return null;
    try {
      final info = _rss.parseFeedInfo(body, url);
      return DiscoveredFeed(
        url: url,
        title: info.title,
        type: _typeOf(body),
        siteUrl: info.siteUrl,
      );
    } catch (e) {
      AppLog.d('Feed at $url did not parse: $e');
      return null;
    }
  }

  List<DiscoveredFeed> _fromHtml(String html, String pageUrl) {
    final results = <DiscoveredFeed>[];
    final base = Uri.tryParse(pageUrl);
    try {
      final document = html_parser.parse(html);
      for (final link in document.querySelectorAll('link')) {
        final rel = (link.attributes['rel'] ?? '').toLowerCase();
        if (!rel.split(RegExp(r'\s+')).contains('alternate')) continue;
        final type = (link.attributes['type'] ?? '').toLowerCase().trim();
        if (!_feedMimeTypes.contains(type)) continue;
        final href = link.attributes['href'];
        if (href == null || href.trim().isEmpty) continue;

        final resolved = base != null && base.hasScheme
            ? base.resolve(href.trim()).toString()
            : href.trim();
        final title = (link.attributes['title'] ?? '').trim();
        final candidate = DiscoveredFeed(
          url: resolved,
          title: title.isEmpty ? _titleFallback(document, resolved) : title,
          type: type.contains('atom')
              ? 'atom'
              : (type.contains('json') ? 'json' : 'rss'),
          siteUrl: pageUrl,
        );
        if (!results.contains(candidate)) results.add(candidate);
      }
    } catch (e) {
      AppLog.d('Could not scan $pageUrl for feeds: $e');
    }
    return results;
  }

  String _titleFallback(dom.Document document, String url) {
    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) return title;
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// Confirms candidates really parse as feeds, keeping the ones that do.
  Future<List<DiscoveredFeed>> _verify(List<DiscoveredFeed> candidates) async {
    final verified = <DiscoveredFeed>[];
    for (final candidate in candidates.take(5)) {
      final feed = await _tryFeed(candidate.url);
      if (feed == null) continue;
      verified.add(
        DiscoveredFeed(
          url: candidate.url,
          title: candidate.title.isNotEmpty ? candidate.title : feed.title,
          type: feed.type,
          siteUrl: candidate.siteUrl ?? feed.siteUrl,
        ),
      );
    }
    return verified.isEmpty ? candidates : verified;
  }

  Future<String?> _fetchText(String url) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: RssService.defaultHeaders,
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final data = response.data;
      final bytes = data is List<int>
          ? data
          : (data is String ? data.codeUnits : const <int>[]);
      if (bytes.isEmpty) return null;
      String? contentType;
      try {
        contentType = response.headers.value('content-type');
      } catch (_) {
        contentType = null;
      }
      return RssService.decodeBody(bytes, contentType: contentType);
    } catch (e) {
      AppLog.d('Discovery fetch failed for $url: $e');
      return null;
    }
  }

  static String _typeOf(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{')) return 'json';
    if (RegExp(r'<feed[\s>]', caseSensitive: false).hasMatch(trimmed)) {
      return 'atom';
    }
    return 'rss';
  }

  static String _joinPath(Uri origin, String path) {
    if (path.startsWith('/?')) {
      return origin.replace(path: '/', query: path.substring(2)).toString();
    }
    return origin.replace(path: path).toString();
  }
}
