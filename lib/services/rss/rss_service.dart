import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../models/article.dart';
import '../../models/rss_feed.dart';
import '../../utils/app_logger.dart';
import '../extraction/html_sanitizer.dart';
import 'date_parser.dart';

/// Thrown when a document is not a feed we can read.
class FeedFormatException implements Exception {
  FeedFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fetches and parses RSS 2.0, RSS 1.0 (RDF), Atom and JSON Feed documents.
///
/// The network layer sends browser-like headers (many hosts answer 403 to the
/// default Dart agent), follows redirects and decodes bytes with the charset
/// declared by the transport or the XML prologue.
class RssService {
  RssService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      responseType: ResponseType.bytes,
      followRedirects: true,
      maxRedirects: 6,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (status) => status != null && status < 500,
    );
  }

  final Dio _dio;

  /// Most feeds ship far fewer; the cap keeps a pathological feed from
  /// flooding the database.
  static const int maxItems = 150;

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const String acceptHeader =
      'application/rss+xml, application/atom+xml, application/feed+json, '
      'application/xml;q=0.9, text/xml;q=0.9, */*;q=0.8';

  static Map<String, String> get defaultHeaders => const <String, String>{
    'User-Agent': userAgent,
    'Accept': acceptHeader,
    'Accept-Language': 'en-US,en;q=0.8',
  };

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  /// Fetches [url] and returns the decoded body.
  Future<String> fetchBody(String url) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: defaultHeaders,
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );
    } on DioException catch (e) {
      throw FeedFormatException(_dioMessage(e));
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw FeedFormatException(_statusMessage(status));
    }

    final body = decodeBody(
      _asBytes(response.data),
      contentType: _headerValue(response, 'content-type'),
    );
    if (body.trim().isEmpty) {
      throw FeedFormatException('The feed returned an empty document.');
    }
    return body;
  }

  /// Backwards compatible alias for [fetchFeedArticles].
  Future<List<Article>> parseRSSFeed(
    String url,
    String feedId, {
    String? categoryId,
  }) => fetchFeedArticles(url, feedId, categoryId: categoryId);

  /// Fetches [url] and returns its articles.
  Future<List<Article>> fetchFeedArticles(
    String url,
    String feedId, {
    String? categoryId,
  }) async {
    AppLog.d('Fetching feed $url');
    final body = await fetchBody(url);
    return parseFeedXml(
      body,
      feedId,
      feedUrl: url,
      categoryId: categoryId,
    );
  }

  /// Fetches [url] and returns the feed's own metadata.
  Future<RSSFeed> fetchFeedInfo(String url) async {
    final body = await fetchBody(url);
    return parseFeedInfo(body, url);
  }

  void dispose() {
    try {
      _dio.close(force: true);
    } catch (_) {
      // Already closed.
    }
  }

  // ---------------------------------------------------------------------------
  // Pure parsing (used directly by tests)
  // ---------------------------------------------------------------------------

  /// True when [body] parses as a feed document of any supported flavour.
  static bool looksLikeFeed(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed);
        return json is Map && json['items'] is List;
      } catch (_) {
        return false;
      }
    }
    try {
      final document = XmlDocument.parse(trimmed);
      return _formatOf(document) != _FeedFormat.unknown;
    } catch (_) {
      return false;
    }
  }

  /// Parses [body] (XML or JSON Feed) into articles.
  List<Article> parseFeedXml(
    String body,
    String feedId, {
    required String feedUrl,
    String? categoryId,
  }) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{')) {
      return _parseJsonFeedItems(trimmed, feedId, feedUrl, categoryId);
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } catch (e) {
      throw FeedFormatException('The feed is not valid XML ($e).');
    }

    final format = _formatOf(document);
    if (format == _FeedFormat.unknown) {
      throw FeedFormatException('Unsupported feed format.');
    }

    final base = Uri.tryParse(feedUrl);
    final itemName = format == _FeedFormat.atom ? 'entry' : 'item';
    final items = document.descendantElements
        .where((e) => e.name.local.toLowerCase() == itemName)
        .take(maxItems)
        .toList(growable: false);

    final articles = <Article>[];
    final seen = <String>{};
    for (final item in items) {
      final article = format == _FeedFormat.atom
          ? _parseAtomEntry(item, feedId, base, categoryId)
          : _parseRssItem(item, feedId, base, categoryId);
      if (article == null) continue;
      if (!seen.add(article.id)) continue;
      articles.add(article);
    }
    return articles;
  }

  /// Parses [body] into the feed's own metadata.
  RSSFeed parseFeedInfo(String body, String url) {
    final trimmed = body.trimLeft();
    final now = DateTime.now();

    if (trimmed.startsWith('{')) {
      final json = jsonDecode(trimmed);
      if (json is! Map || json['items'] is! List) {
        throw FeedFormatException('Unsupported feed format.');
      }
      final home = json['home_page_url']?.toString();
      return RSSFeed(
        id: feedIdFor(url),
        title: _cleanTitle(json['title']?.toString(), url),
        url: url,
        description: _plain(json['description']?.toString() ?? ''),
        imageUrl: json['icon']?.toString() ?? json['favicon']?.toString(),
        siteUrl: home,
        language: json['language']?.toString(),
        dateAdded: now,
      );
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } catch (e) {
      throw FeedFormatException('The feed is not valid XML ($e).');
    }

    final format = _formatOf(document);
    if (format == _FeedFormat.unknown) {
      throw FeedFormatException('Unsupported feed format.');
    }

    final base = Uri.tryParse(url);
    final root = document.rootElement;
    final channel = format == _FeedFormat.atom
        ? root
        : (_descendant(root, 'channel') ?? root);

    final title = _text(channel, 'title');
    final description =
        _text(channel, 'description') ??
        _text(channel, 'subtitle') ??
        _text(channel, 'tagline') ??
        '';

    String? siteUrl;
    if (format == _FeedFormat.atom) {
      siteUrl = _atomLink(channel, base);
    } else {
      final link = _text(channel, 'link');
      siteUrl = _resolve(link, base);
      siteUrl ??= _atomLink(channel, base);
    }

    String? imageUrl;
    final imageElement = _localChild(channel, 'image');
    if (imageElement != null) {
      imageUrl =
          _text(imageElement, 'url') ??
          imageElement.getAttribute('rdf:resource');
    }
    imageUrl ??= _prefixedChild(channel, 'itunes', 'image')?.getAttribute(
      'href',
    );
    imageUrl ??= _text(channel, 'logo');
    imageUrl ??= _text(channel, 'icon');
    imageUrl = _resolve(imageUrl, base);

    final language =
        _text(channel, 'language') ??
        root.getAttribute('xml:lang') ??
        _prefixedText(channel, 'dc', 'language');

    return RSSFeed(
      id: feedIdFor(url),
      title: _cleanTitle(title, url),
      url: url,
      description: _plain(description),
      imageUrl: imageUrl,
      siteUrl: siteUrl,
      language: language,
      dateAdded: now,
    );
  }

  // ---------------------------------------------------------------------------
  // Item parsing
  // ---------------------------------------------------------------------------

  Article? _parseRssItem(
    XmlElement item,
    String feedId,
    Uri? base,
    String? categoryId,
  ) {
    try {
      final title = _text(item, 'title');
      final link = _rssLink(item, base);
      if (link == null || link.isEmpty) return null;

      final rawContent =
          _prefixedText(item, 'content', 'encoded') ??
          _text(item, 'content') ??
          _text(item, 'description') ??
          _prefixedText(item, 'dc', 'description') ??
          '';
      final rawDescription = _text(item, 'description') ?? rawContent;

      final content = rawContent.trim().isEmpty
          ? null
          : HtmlSanitizer.sanitize(rawContent, baseUrl: link);

      final published =
          parseFeedDate(_text(item, 'pubDate')) ??
          parseFeedDate(_prefixedText(item, 'dc', 'date')) ??
          parseFeedDate(_text(item, 'date')) ??
          parseFeedDate(_text(item, 'published')) ??
          parseFeedDate(_text(item, 'updated'));

      final author =
          _cleanAuthor(_prefixedText(item, 'dc', 'creator')) ??
          _cleanAuthor(_text(item, 'author')) ??
          _cleanAuthor(_prefixedText(item, 'itunes', 'author')) ??
          _cleanAuthor(_atomAuthor(item));

      final now = DateTime.now();
      final resolvedTitle = _plain(title ?? '');
      return Article(
        id: articleIdFor(link),
        title: resolvedTitle.isEmpty ? '(untitled)' : resolvedTitle,
        description: HtmlSanitizer.excerpt(rawDescription, max: 300),
        content: content,
        imageUrl: _imageFor(item, content, base),
        url: link,
        author: author,
        publishedDate: published ?? now,
        feedId: feedId,
        categoryId: categoryId,
        dateAdded: now,
      );
    } catch (e) {
      AppLog.w('Skipping unreadable RSS item', e);
      return null;
    }
  }

  Article? _parseAtomEntry(
    XmlElement entry,
    String feedId,
    Uri? base,
    String? categoryId,
  ) {
    try {
      final title = _text(entry, 'title');
      final link = _atomLink(entry, base) ?? _text(entry, 'id');
      if (link == null || !link.startsWith('http')) return null;

      final rawContent =
          _text(entry, 'content') ??
          _prefixedText(entry, 'content', 'encoded') ??
          _text(entry, 'summary') ??
          '';
      final rawSummary = _text(entry, 'summary') ?? rawContent;

      final content = rawContent.trim().isEmpty
          ? null
          : HtmlSanitizer.sanitize(rawContent, baseUrl: link);

      final published =
          parseFeedDate(_text(entry, 'published')) ??
          parseFeedDate(_text(entry, 'updated')) ??
          parseFeedDate(_prefixedText(entry, 'dc', 'date'));

      final now = DateTime.now();
      final resolvedTitle = _plain(title ?? '');
      return Article(
        id: articleIdFor(link),
        title: resolvedTitle.isEmpty ? '(untitled)' : resolvedTitle,
        description: HtmlSanitizer.excerpt(rawSummary, max: 300),
        content: content,
        imageUrl: _imageFor(entry, content, base),
        url: link,
        author: _cleanAuthor(_atomAuthor(entry)),
        publishedDate: published ?? now,
        feedId: feedId,
        categoryId: categoryId,
        dateAdded: now,
      );
    } catch (e) {
      AppLog.w('Skipping unreadable Atom entry', e);
      return null;
    }
  }

  List<Article> _parseJsonFeedItems(
    String body,
    String feedId,
    String feedUrl,
    String? categoryId,
  ) {
    final dynamic json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      throw FeedFormatException('The feed is not valid JSON ($e).');
    }
    if (json is! Map || json['items'] is! List) {
      throw FeedFormatException('Unsupported feed format.');
    }

    final base = Uri.tryParse(feedUrl);
    final articles = <Article>[];
    final seen = <String>{};

    for (final raw in (json['items'] as List).take(maxItems)) {
      if (raw is! Map) continue;
      final link =
          _resolve(raw['url']?.toString(), base) ??
          _resolve(raw['external_url']?.toString(), base) ??
          _resolve(raw['id']?.toString(), base);
      if (link == null || !link.startsWith('http')) continue;

      final rawHtml =
          raw['content_html']?.toString() ??
          (raw['content_text'] != null
              ? '<p>${_escape(raw['content_text'].toString())}</p>'
              : null) ??
          raw['summary']?.toString() ??
          '';
      final content = rawHtml.trim().isEmpty
          ? null
          : HtmlSanitizer.sanitize(rawHtml, baseUrl: link);

      final now = DateTime.now();
      final title = _plain(raw['title']?.toString() ?? '');
      String? author;
      final authorField = raw['author'];
      if (authorField is Map) author = authorField['name']?.toString();
      final authorsField = raw['authors'];
      if (author == null && authorsField is List && authorsField.isNotEmpty) {
        final first = authorsField.first;
        if (first is Map) author = first['name']?.toString();
      }

      final article = Article(
        id: articleIdFor(link),
        title: title.isEmpty ? '(untitled)' : title,
        description: HtmlSanitizer.excerpt(
          raw['summary']?.toString() ?? rawHtml,
          max: 300,
        ),
        content: content,
        imageUrl:
            _resolve(raw['image']?.toString(), base) ??
            _resolve(raw['banner_image']?.toString(), base) ??
            _firstContentImage(content),
        url: link,
        author: _cleanAuthor(author),
        publishedDate:
            parseFeedDate(raw['date_published']?.toString()) ??
            parseFeedDate(raw['date_modified']?.toString()) ??
            now,
        feedId: feedId,
        categoryId: categoryId,
        dateAdded: now,
      );
      if (seen.add(article.id)) articles.add(article);
    }
    return articles;
  }

  // ---------------------------------------------------------------------------
  // Field helpers
  // ---------------------------------------------------------------------------

  String? _rssLink(XmlElement item, Uri? base) {
    final link = _text(item, 'link');
    final resolved = _resolve(link, base);
    if (resolved != null && resolved.startsWith('http')) return resolved;

    final atom = _atomLink(item, base);
    if (atom != null) return atom;

    final guid = _localChild(item, 'guid');
    if (guid != null) {
      final isPermaLink = guid.getAttribute('isPermaLink');
      final value = guid.innerText.trim();
      if (value.startsWith('http') && isPermaLink != 'false') {
        return value;
      }
    }
    return null;
  }

  String? _atomLink(XmlElement element, Uri? base) {
    final links = _localChildren(element, 'link').toList();
    if (links.isEmpty) return null;

    XmlElement? chosen;
    for (final link in links) {
      final rel = link.getAttribute('rel');
      final type = link.getAttribute('type');
      if (rel == 'alternate' &&
          (type == null || type.contains('html') || type.isEmpty)) {
        chosen = link;
        break;
      }
    }
    chosen ??= links.firstWhere(
      (l) => l.getAttribute('rel') == null && l.getAttribute('href') != null,
      orElse: () => links.first,
    );

    final href = chosen.getAttribute('href');
    final resolved = _resolve(href, base);
    if (resolved != null && resolved.startsWith('http')) return resolved;
    return null;
  }

  String? _atomAuthor(XmlElement element) {
    final author = _localChild(element, 'author');
    if (author == null) return null;
    return _text(author, 'name') ?? author.innerText.trim();
  }

  /// Best image for an item: media RSS, then enclosures, then the body HTML.
  String? _imageFor(XmlElement item, String? contentHtml, Uri? base) {
    String? best;
    var bestWidth = -1;

    Iterable<XmlElement> mediaContents = _prefixedChildren(
      item,
      'media',
      'content',
    );
    final group = _prefixedChild(item, 'media', 'group');
    if (group != null) {
      mediaContents = [
        ...mediaContents,
        ..._prefixedChildren(group, 'media', 'content'),
      ];
    }

    for (final media in mediaContents) {
      final url = media.getAttribute('url');
      if (url == null || url.isEmpty) continue;
      final type = media.getAttribute('type') ?? '';
      final medium = media.getAttribute('medium') ?? '';
      final looksImage =
          medium == 'image' ||
          type.startsWith('image/') ||
          (medium.isEmpty && type.isEmpty && _looksLikeImageUrl(url));
      if (!looksImage) continue;
      final width = int.tryParse(media.getAttribute('width') ?? '') ?? 0;
      if (width > bestWidth) {
        bestWidth = width;
        best = url;
      }
    }
    if (best != null) return _resolve(best, base);

    final thumbnail =
        _prefixedChild(item, 'media', 'thumbnail')?.getAttribute('url');
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return _resolve(thumbnail, base);
    }

    for (final enclosure in _localChildren(item, 'enclosure')) {
      final url = enclosure.getAttribute('url');
      if (url == null || url.isEmpty) continue;
      final type = enclosure.getAttribute('type') ?? '';
      if (type.startsWith('image/') ||
          (type.isEmpty && _looksLikeImageUrl(url))) {
        return _resolve(url, base);
      }
    }

    final itunes = _prefixedChild(item, 'itunes', 'image')?.getAttribute('href');
    if (itunes != null && itunes.isNotEmpty) return _resolve(itunes, base);

    return _firstContentImage(contentHtml);
  }

  static final RegExp _imgTag = RegExp(
    r'''<img\b[^>]*>''',
    caseSensitive: false,
  );
  static final RegExp _attr = RegExp(
    r'''(\w[\w:-]*)\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  );

  /// First image in [html] that is not a spacer or tracking pixel.
  String? _firstContentImage(String? html) {
    if (html == null || html.isEmpty) return null;
    for (final match in _imgTag.allMatches(html)) {
      final tag = match.group(0)!;
      final attributes = <String, String>{};
      for (final a in _attr.allMatches(tag)) {
        attributes[a.group(1)!.toLowerCase()] = a.group(2)!;
      }
      final src = attributes['src'];
      if (src == null || src.isEmpty) continue;
      if (src.startsWith('data:')) continue;
      if (!src.startsWith('http')) continue;
      final width = int.tryParse(attributes['width'] ?? '');
      final height = int.tryParse(attributes['height'] ?? '');
      if (width != null && width <= 50) continue;
      if (height != null && height <= 50) continue;
      if (_trackingImage.hasMatch(src)) continue;
      return src;
    }
    return null;
  }

  static final RegExp _trackingImage = RegExp(
    r'(pixel|/track|tracker|beacon|feedburner|doubleclick|1x1|spacer|'
    r'blank\.gif|stats\.wordpress)',
    caseSensitive: false,
  );

  static bool _looksLikeImageUrl(String url) => RegExp(
    r'\.(jpe?g|png|gif|webp|avif)(\?|$)',
    caseSensitive: false,
  ).hasMatch(url);

  String? _cleanAuthor(String? raw) {
    if (raw == null) return null;
    var value = _plain(raw);
    if (value.isEmpty) return null;
    // RSS `author` is an email address, often "me@site.com (Jane Doe)".
    final parenthesised = RegExp(r'\(([^)]+)\)$').firstMatch(value);
    if (parenthesised != null) value = parenthesised.group(1)!.trim();
    if (value.contains('@') && !value.contains(' ')) {
      final at = value.indexOf('@');
      value = value.substring(0, at);
    }
    if (value.isEmpty) return null;
    if (value.toLowerCase() == 'unknown') return null;
    if (value.length > 160) return null;
    return value;
  }

  String _cleanTitle(String? title, String url) {
    final value = _plain(title ?? '');
    if (value.isNotEmpty) return value;
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return 'Untitled feed';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _plain(String raw) {
    if (raw.trim().isEmpty) return '';
    if (!raw.contains('<') && !raw.contains('&')) {
      return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return HtmlSanitizer.toPlainText(raw)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String? _resolve(String? raw, Uri? base) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (base == null || !base.hasScheme) return value;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  // ---------------------------------------------------------------------------
  // XML navigation (namespace aware)
  // ---------------------------------------------------------------------------

  static const Map<String, String> _namespaceUris = <String, String>{
    'content': 'http://purl.org/rss/1.0/modules/content/',
    'dc': 'http://purl.org/dc/elements/1.1/',
    'media': 'http://search.yahoo.com/mrss/',
    'itunes': 'http://www.itunes.com/dtds/podcast-1.0.dtd',
    'atom': 'http://www.w3.org/2005/Atom',
  };

  static const Set<String> _modulePrefixes = <String>{
    'content',
    'dc',
    'media',
    'itunes',
  };

  /// Children of [parent] with local name [name] that are not part of a
  /// namespaced module (so `media:content` never shadows Atom's `content`).
  static Iterable<XmlElement> _localChildren(XmlElement parent, String name) {
    final target = name.toLowerCase();
    return parent.childElements.where((e) {
      if (e.name.local.toLowerCase() != target) return false;
      final prefix = e.name.prefix?.toLowerCase();
      if (prefix == null || prefix.isEmpty) return true;
      return !_modulePrefixes.contains(prefix);
    });
  }

  static XmlElement? _localChild(XmlElement parent, String name) {
    for (final element in _localChildren(parent, name)) {
      return element;
    }
    return null;
  }

  static Iterable<XmlElement> _prefixedChildren(
    XmlElement parent,
    String prefix,
    String name,
  ) {
    final targetPrefix = prefix.toLowerCase();
    final target = name.toLowerCase();
    final uri = _namespaceUris[targetPrefix];
    return parent.childElements.where((e) {
      if (e.name.local.toLowerCase() != target) return false;
      final elementPrefix = e.name.prefix?.toLowerCase();
      if (elementPrefix == targetPrefix) return true;
      if (uri == null) return false;
      try {
        return e.name.namespaceUri == uri;
      } catch (_) {
        return false;
      }
    });
  }

  static XmlElement? _prefixedChild(
    XmlElement parent,
    String prefix,
    String name,
  ) {
    for (final element in _prefixedChildren(parent, prefix, name)) {
      return element;
    }
    return null;
  }

  static String? _text(XmlElement parent, String name) {
    final element = _localChild(parent, name);
    if (element == null) return null;
    final value = element.innerText.trim();
    return value.isEmpty ? null : value;
  }

  static String? _prefixedText(
    XmlElement parent,
    String prefix,
    String name,
  ) {
    final element = _prefixedChild(parent, prefix, name);
    if (element == null) return null;
    final value = element.innerText.trim();
    return value.isEmpty ? null : value;
  }

  static XmlElement? _descendant(XmlElement root, String name) {
    final target = name.toLowerCase();
    for (final element in root.descendantElements) {
      if (element.name.local.toLowerCase() == target) return element;
    }
    return null;
  }

  static _FeedFormat _formatOf(XmlDocument document) {
    final XmlElement root;
    try {
      root = document.rootElement;
    } catch (_) {
      return _FeedFormat.unknown;
    }
    final name = root.name.local.toLowerCase();
    if (name == 'rss') return _FeedFormat.rss2;
    if (name == 'feed') return _FeedFormat.atom;
    if (name == 'rdf') return _FeedFormat.rdf;
    // Some servers ship a bare <channel> document.
    if (name == 'channel') return _FeedFormat.rss2;
    return _FeedFormat.unknown;
  }

  // ---------------------------------------------------------------------------
  // Ids, decoding, errors
  // ---------------------------------------------------------------------------

  /// Stable feed id: base64 of the URL without padding.
  ///
  /// Kept byte-for-byte compatible with v2 so existing databases keep working.
  static String feedIdFor(String url) =>
      base64Encode(utf8.encode(url)).replaceAll('=', '');

  /// Stable article id derived from its link.
  static String articleIdFor(String link) =>
      base64Encode(utf8.encode(link)).replaceAll('=', '');

  /// Decodes feed bytes using the transport charset, the BOM or the XML
  /// prologue, falling back to UTF-8 and then latin-1.
  static String decodeBody(List<int> bytes, {String? contentType}) {
    if (bytes.isEmpty) return '';

    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }

    String? charset;
    if (contentType != null) {
      charset = RegExp(
        r'charset\s*=\s*"?([\w-]+)"?',
        caseSensitive: false,
      ).firstMatch(contentType)?.group(1);
    }

    if (charset == null) {
      final head = latin1.decode(
        bytes.take(256).map((b) => b & 0xFF).toList(growable: false),
        allowInvalid: true,
      );
      charset = RegExp(
        r'''<\?xml[^>]*encoding\s*=\s*["']([\w-]+)["']''',
        caseSensitive: false,
      ).firstMatch(head)?.group(1);
    }

    final name = (charset ?? 'utf-8').toLowerCase().replaceAll('_', '-');
    switch (name) {
      case 'iso-8859-1':
      case 'latin1':
      case 'latin-1':
      case 'windows-1252':
      case 'cp1252':
      case 'iso-8859-15':
        return latin1.decode(
          bytes.map((b) => b & 0xFF).toList(growable: false),
          allowInvalid: true,
        );
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static List<int> _asBytes(dynamic data) {
    if (data == null) return const <int>[];
    if (data is Uint8List) return data;
    if (data is List<int>) return data;
    if (data is String) return utf8.encode(data);
    if (data is List) return data.cast<int>();
    return const <int>[];
  }

  static String? _headerValue(Response<dynamic> response, String name) {
    try {
      return response.headers.value(name);
    } catch (_) {
      return null;
    }
  }

  static String _statusMessage(int status) {
    switch (status) {
      case 401:
      case 403:
        return 'The feed host blocked the request (HTTP $status).';
      case 404:
      case 410:
        return 'The feed was not found (HTTP $status).';
      case 429:
        return 'The feed host is rate limiting requests (HTTP 429).';
      default:
        if (status >= 500) {
          return 'The feed host returned a server error (HTTP $status).';
        }
        return 'The feed host returned HTTP $status.';
    }
  }

  static String _dioMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The feed took too long to respond.';
      case DioExceptionType.badCertificate:
        return 'The feed host has an invalid security certificate.';
      case DioExceptionType.connectionError:
        return 'Could not reach the feed. Check your connection.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badResponse:
        return _statusMessage(e.response?.statusCode ?? 0);
      case DioExceptionType.unknown:
        return 'Could not load the feed.';
    }
  }
}

enum _FeedFormat { rss2, rdf, atom, unknown }

/// Historic alias kept so older imports keep compiling.
class RSSService extends RssService {
  RSSService({super.dio});
}
