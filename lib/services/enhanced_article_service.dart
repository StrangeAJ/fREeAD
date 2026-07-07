import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter/foundation.dart';

/// Enhanced article extraction service inspired by Mozilla's Readability.js.
///
/// Extraction strategy, in order of preference:
/// 1. JSON-LD structured data (`articleBody`) — highest quality when present.
/// 2. Microdata / RDFa (`itemprop="articleBody"`) — common alternative to JSON-LD.
/// 3. Readability-style scoring: paragraph scores accumulate into parent and
///    grandparent candidates, the winner is scaled by link density, and
///    qualifying siblings are joined into the final article.
/// 4. Fallback to `<article>`, `<main>`, or `<body>`.
/// 5. Open Graph description as last-resort excerpt.
class EnhancedArticleService {
  final Dio _dio;

  static const int _minParagraphLength = 25;
  static const int _minJsonLdBodyLength = 250;
  static const double _minCandidateScore = 15;
  static const int _maxPaginationPages = 10;

  /// Class/id fragments that mark boilerplate. Matched on word boundaries
  /// (split on space, dash, underscore) — never as raw substrings, so
  /// "read-more" or "download" are not mistaken for ads.
  static final RegExp _negativePattern = RegExp(
    r'(^|[\s_-])(ad|ads|advert|advertisement|adsense|banner|breadcrumb|breadcrumbs|'
    r'combx|comment|comments|community|disqus|extra|footer|gdpr|header|hidden|'
    r'legends|menu|nav|navbar|navigation|outbrain|pager|pagination|popup|promo|'
    r'related|remark|replies|rss|share|sharing|shoutbox|sidebar|skyscraper|'
    r'social|sponsor|sponsored|subscribe|newsletter|supplemental|taboola|'
    r'toolbar|widget|masthead|cookie|consent|paywall|modal|overlay)([\s_-]|$)',
    caseSensitive: false,
  );

  /// Class/id fragments that suggest the element IS the article. An element
  /// matching this is never removed as boilerplate.
  static final RegExp _positivePattern = RegExp(
    r'(^|[\s_-])(article|body|content|entry|hentry|h-entry|main|page|post|text|'
    r'blog|story|column)([\s_-]|$)',
    caseSensitive: false,
  );

  /// Site-specific CSS selectors for popular content platforms.
  static const Map<String, List<String>> _siteSpecificSelectors = {
    'medium.com': ['article section', '.postArticle-content', '.section-content'],
    'dev.to': ['.crayons-article__main', '#article-body', '.article-body'],
    'substack.com': ['.body.markup', '.post-content', '.available-content'],
    'wordpress.com': ['.entry-content', '.post-content', '.article-content'],
    'ghost.io': ['.post-content', '.gh-content', '.article-content'],
    'blogger.com': ['.post-body.entry-content', '.post-body'],
    'tumblr.com': ['.post-content', '.body-text'],
    'hashnode.dev': ['.prose', '#post-content-parent'],
    'notion.site': ['.notion-page-content', '.layout-content'],
  };

  EnhancedArticleService() : _dio = Dio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Cache-Control': 'no-cache',
      },
      followRedirects: true,
      maxRedirects: 5,
    );
  }

  /// Extracts article content from [url].
  Future<Map<String, dynamic>?> extractArticleContent(String url) async {
    try {
      String requestUrl = url;
      if (kIsWeb) {
        requestUrl =
            'https://api.allorigins.win/get?url=${Uri.encodeComponent(url)}';
      }

      final response = await _dio.get(requestUrl);
      if (response.statusCode != 200) {
        print('Failed to fetch article: ${response.statusCode}');
        return null;
      }

      String htmlContent;
      if (kIsWeb) {
        final data = response.data;
        if (data is Map && data.containsKey('contents')) {
          htmlContent = data['contents'];
        } else {
          htmlContent = response.data.toString();
        }
      } else {
        htmlContent = response.data.toString();
      }

      final result = processHtml(htmlContent, url);

      // If we got a result, try multi-page pagination
      if (result != null) {
        final document = html_parser.parse(htmlContent);
        final paginatedContent = await _handlePagination(document, url, result);
        if (paginatedContent != null) {
          return paginatedContent;
        }
      }

      return result;
    } catch (e) {
      print('Error extracting article content: $e');
      return null;
    }
  }

  /// Processes raw [htmlContent] fetched from [url]. Exposed for testing.
  Map<String, dynamic>? processHtml(String htmlContent, String url) {
    try {
      final document = html_parser.parse(htmlContent);

      // Read structured data and metadata BEFORE scripts are stripped.
      final jsonLd = _extractJsonLd(document);
      final metadata = _extractMetadata(document, jsonLd);

      dom.Element? articleContent;

      // 1. JSON-LD articleBody is author-provided full text — prefer it.
      final articleBody = jsonLd?['articleBody'] as String?;
      if (articleBody != null &&
          articleBody.trim().length >= _minJsonLdBodyLength) {
        articleContent = _buildContentFromPlainText(document, articleBody);
      }

      // 2. Microdata / RDFa itemprop="articleBody" — common alternative.
      if (articleContent == null) {
        articleContent = _extractMicrodataArticleBody(document);
      }

      // 3. Site-specific selectors for known platforms.
      if (articleContent == null) {
        articleContent = _trySiteSpecificSelectors(document, url);
      }

      // 4. Readability-style DOM scoring.
      if (articleContent == null) {
        _prepareDocument(document);
        articleContent = _grabArticle(document);
      }

      // 5. Open Graph fallback — at least provide an excerpt.
      if (articleContent == null) {
        final ogResult = _openGraphFallback(document, metadata);
        if (ogResult != null) return ogResult;

        print('No article content found');
        return null;
      }

      _postProcessContent(articleContent, url, metadata['title']);

      final cleanContent = articleContent.outerHtml;
      final textContent = _normalizeWhitespace(articleContent.text);
      if (textContent.isEmpty) {
        print('No clean content extracted');
        return null;
      }

      return {
        'content': cleanContent,
        'excerpt': metadata['excerpt'] ?? _excerptFromText(textContent),
        'title': metadata['title'],
        'author': metadata['author'],
        'siteName': metadata['siteName'],
        'publishedTime': metadata['publishedTime'],
        'length': textContent.length,
      };
    } catch (e) {
      print('Error processing article: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // JSON-LD structured data
  // ---------------------------------------------------------------------

  static final RegExp _articleTypePattern = RegExp(
    r'^(Article|NewsArticle|BlogPosting|ReportageNewsArticle|TechArticle|'
    r'ScholarlyArticle|SocialMediaPosting|LiveBlogPosting)$',
  );

  Map<String, dynamic>? _extractJsonLd(dom.Document document) {
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(script.text);
        final roots = decoded is List ? decoded : [decoded];
        for (final root in roots) {
          if (root is! Map) continue;
          final graph = root['@graph'];
          final nodes = <dynamic>[root, if (graph is List) ...graph];
          for (final node in nodes) {
            if (node is! Map) continue;
            final rawType = node['@type'];
            final types = rawType is List
                ? rawType.map((t) => t.toString())
                : [rawType?.toString() ?? ''];
            if (!types.any(_articleTypePattern.hasMatch)) continue;

            return {
              'articleBody': node['articleBody']?.toString(),
              'headline': node['headline']?.toString(),
              'author': _jsonLdAuthorName(node['author']),
              'datePublished': node['datePublished']?.toString(),
              'description': node['description']?.toString(),
            };
          }
        }
      } catch (_) {
        // Malformed JSON-LD — ignore and keep looking.
      }
    }
    return null;
  }

  String? _jsonLdAuthorName(dynamic author) {
    if (author == null) return null;
    if (author is String) return author;
    if (author is Map) return author['name']?.toString();
    if (author is List && author.isNotEmpty) {
      final names =
          author.map(_jsonLdAuthorName).whereType<String>().toList();
      return names.isEmpty ? null : names.join(', ');
    }
    return null;
  }

  /// Wraps plain text (e.g. a JSON-LD articleBody) into paragraph elements.
  dom.Element _buildContentFromPlainText(dom.Document document, String text) {
    final container = document.createElement('div');
    final paragraphs = text
        .split(RegExp(r'\n{2,}|\r\n{2,}'))
        .expand((block) => block.split('\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    for (final paragraph in paragraphs) {
      final p = document.createElement('p');
      p.text = paragraph;
      container.append(p);
    }
    return container;
  }

  // ---------------------------------------------------------------------
  // Microdata / RDFa extraction
  // ---------------------------------------------------------------------

  /// Extracts article body from microdata (itemprop="articleBody") or
  /// RDFa (property="articleBody") elements.
  dom.Element? _extractMicrodataArticleBody(dom.Document document) {
    for (final selector in [
      '[itemprop="articleBody"]',
      '[property="articleBody"]',
    ]) {
      try {
        final element = document.querySelector(selector);
        if (element != null) {
          final text = _normalizeWhitespace(element.text);
          if (text.length >= _minJsonLdBodyLength) {
            return element;
          }
        }
      } catch (_) {
        // Selector might not be supported — continue.
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Site-specific selectors
  // ---------------------------------------------------------------------

  /// Tries site-specific selectors for known content platforms.
  dom.Element? _trySiteSpecificSelectors(dom.Document document, String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();

      for (final entry in _siteSpecificSelectors.entries) {
        if (host.contains(entry.key)) {
          for (final selector in entry.value) {
            try {
              final element = document.querySelector(selector);
              if (element != null) {
                final text = _normalizeWhitespace(element.text);
                if (text.length > 200) {
                  return element;
                }
              }
            } catch (_) {
              // Selector might fail — continue.
            }
          }
        }
      }
    } catch (_) {
      // URL parse failure — skip.
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Noscript image recovery
  // ---------------------------------------------------------------------

  /// Before stripping <noscript>, promotes real <img> tags inside to their
  /// parent — many sites put actual images in <noscript> alongside JS-only
  /// <picture> elements.
  void _recoverNoscriptImages(dom.Document document) {
    for (final noscript in document.querySelectorAll('noscript').toList()) {
      try {
        // Parse the noscript's inner HTML to find img tags
        final fragment = html_parser.parseFragment(noscript.innerHtml);
        final images = fragment.querySelectorAll('img');

        for (final img in images) {
          final src = img.attributes['src'] ?? '';
          if (src.isNotEmpty && src.startsWith('http')) {
            // Create a new img element and insert before noscript
            final newImg = document.createElement('img');
            for (final attr in img.attributes.entries) {
              newImg.attributes[attr.key] = attr.value;
            }
            noscript.parent?.insertBefore(newImg, noscript);
          }
        }
      } catch (_) {
        // Failed to parse noscript content — skip.
      }
    }
  }

  // ---------------------------------------------------------------------
  // Document preparation
  // ---------------------------------------------------------------------

  void _prepareDocument(dom.Document document) {
    // Recover images from noscript BEFORE stripping it
    _recoverNoscriptImages(document);

    for (final tag in ['script', 'style', 'noscript', 'template', 'iframe',
        'embed', 'object', 'link', 'svg', 'form', 'button', 'input',
        'select', 'textarea']) {
      for (final element in document.querySelectorAll(tag)) {
        element.remove();
      }
    }

    _removeComments(document);
    _stripUnlikelyCandidates(document);
    _convertDivsToParagraphs(document);
  }

  void _removeComments(dom.Node node) {
    for (final child in node.nodes.toList()) {
      if (child.nodeType == dom.Node.COMMENT_NODE) {
        child.remove();
      } else {
        _removeComments(child);
      }
    }
  }

  /// Readability's "strip unlikely candidates": remove elements whose
  /// class/id scream boilerplate, unless they also look like content.
  void _stripUnlikelyCandidates(dom.Document document) {
    final body = document.body;
    if (body == null) return;

    for (final element in body.querySelectorAll('*').toList()) {
      // Skip if already detached by an earlier removal.
      if (element.parent == null) continue;

      final tag = element.localName ?? '';
      if (tag == 'body' || tag == 'html' || tag == 'article' || tag == 'main') {
        continue;
      }

      // Structural boilerplate tags are always removed.
      if (tag == 'nav' || tag == 'aside') {
        element.remove();
        continue;
      }
      if ((tag == 'header' || tag == 'footer') &&
          element.parent?.localName == 'body') {
        element.remove();
        continue;
      }

      final matchString = '${element.className} ${element.id}';
      if (matchString.trim().isEmpty) continue;
      if (_negativePattern.hasMatch(matchString) &&
          !_positivePattern.hasMatch(matchString)) {
        element.remove();
      }
    }
  }

  /// Converts divs with no block-level children into paragraphs so they get
  /// scored. Moves child NODES (including text nodes) — never rewrites text,
  /// so inline markup is preserved.
  void _convertDivsToParagraphs(dom.Document document) {
    for (final div in document.querySelectorAll('div').toList()) {
      if (div.parent == null) continue;
      if (_hasChildBlockElement(div)) continue;
      if (div.text.trim().isEmpty) continue;

      final p = document.createElement('p');
      for (final node in div.nodes.toList()) {
        p.append(node);
      }
      for (final attr in div.attributes.keys) {
        p.attributes[attr] = div.attributes[attr]!;
      }
      div.replaceWith(p);
    }
  }

  static const Set<String> _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre',
    'ul', 'ol', 'li', 'table', 'tr', 'td', 'section', 'article', 'figure',
  };

  bool _hasChildBlockElement(dom.Element element) {
    for (final child in element.children) {
      if (_blockTags.contains(child.localName)) return true;
      if (_hasChildBlockElement(child)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------

  Map<String, String?> _extractMetadata(
      dom.Document document, Map<String, dynamic>? jsonLd) {
    return {
      'title': jsonLd?['headline'] as String? ?? _getTitle(document),
      'author': jsonLd?['author'] as String? ?? _getAuthor(document),
      'siteName': _getSiteName(document),
      'publishedTime':
          jsonLd?['datePublished'] as String? ?? _getPublishedTime(document),
      'excerpt': jsonLd?['description'] as String? ?? _getDescription(document),
    };
  }

  String? _metaContent(dom.Document document, List<String> selectors) {
    for (final selector in selectors) {
      final content =
          document.querySelector(selector)?.attributes['content']?.trim();
      if (content != null && content.isNotEmpty) return content;
    }
    return null;
  }

  String? _getTitle(dom.Document document) {
    // og:title is the article title; <h1> is often a site banner.
    final meta = _metaContent(document, [
      'meta[property="og:title"]',
      'meta[name="twitter:title"]',
    ]);
    if (meta != null) return meta;

    final h1 = document.querySelector('h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;

    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) {
      // Strip common " | Site Name" / " - Site Name" suffixes.
      final separators = RegExp(r'\s[|\-–—]\s');
      final parts = title.split(separators);
      if (parts.length > 1 && parts.first.trim().length >= 15) {
        return parts.first.trim();
      }
      return title;
    }
    return null;
  }

  String? _getAuthor(dom.Document document) {
    final meta = _metaContent(document, [
      'meta[name="author"]',
      'meta[property="article:author"]',
      'meta[name="parsely-author"]',
    ]);
    if (meta != null && !meta.startsWith('http')) return meta;

    for (final selector in [
      '[rel="author"]', '[itemprop="author"]', '.author', '.byline',
      '.by-author', '.article-author', '.writer', '.journalist',
    ]) {
      final text = document.querySelector(selector)?.text.trim();
      if (text != null && text.isNotEmpty && text.length < 120) {
        return _normalizeWhitespace(text);
      }
    }
    return null;
  }

  String? _getSiteName(dom.Document document) {
    return _metaContent(document, ['meta[property="og:site_name"]']);
  }

  String? _getPublishedTime(dom.Document document) {
    final meta = _metaContent(document, [
      'meta[property="article:published_time"]',
      'meta[name="date"]',
      'meta[name="parsely-pub-date"]',
    ]);
    if (meta != null) return meta;
    return document.querySelector('time[datetime]')?.attributes['datetime'];
  }

  String? _getDescription(dom.Document document) {
    return _metaContent(document, [
      'meta[property="og:description"]',
      'meta[name="description"]',
      'meta[name="twitter:description"]',
    ]);
  }

  // ---------------------------------------------------------------------
  // Core scoring algorithm
  // ---------------------------------------------------------------------

  dom.Element? _grabArticle(dom.Document document) {
    final candidateScores = <dom.Element, double>{};

    for (final paragraph
        in document.querySelectorAll('p, td, pre, blockquote')) {
      final parent = paragraph.parent;
      if (parent == null) continue;
      final grandParent = parent.parent;

      final innerText = _normalizeWhitespace(paragraph.text);
      if (innerText.length < _minParagraphLength) continue;

      // Readability paragraph score: base + commas + length bonus.
      double contentScore = 1;
      contentScore += ','.allMatches(innerText).length;
      contentScore += '，'.allMatches(innerText).length;
      contentScore += min(innerText.length / 100, 3);

      candidateScores.update(parent, (s) => s + contentScore,
          ifAbsent: () => _initializeCandidate(parent) + contentScore);
      if (grandParent != null) {
        candidateScores.update(grandParent, (s) => s + contentScore / 2,
            ifAbsent: () => _initializeCandidate(grandParent) + contentScore / 2);
      }
    }

    // Bonus scoring for rich content elements (blockquotes, figures, tables).
    for (final entry in candidateScores.entries.toList()) {
      final element = entry.key;
      double bonus = 0;

      // Blockquote bonus — articles with quotes are usually real content.
      final blockquotes = element.querySelectorAll('blockquote');
      bonus += blockquotes.length * 3;

      // Figure bonus — articles with figures have rich formatting.
      final figures = element.querySelectorAll('figure');
      bonus += figures.length * 3;

      // Data table bonus (tables with >1 row suggest tabular data in article).
      for (final table in element.querySelectorAll('table')) {
        final rows = table.querySelectorAll('tr');
        if (rows.length > 1) {
          bonus += 3;
        }
      }

      // Penalty for excessive child divs (usually wrappers, not content).
      final childDivs = element.querySelectorAll(':scope > div');
      if (childDivs.length > 5) {
        final textInDivs = childDivs.fold(0, (sum, d) => sum + d.text.trim().length);
        final totalText = element.text.trim().length;
        if (totalText > 0 && textInDivs / totalText < 0.3) {
          bonus -= 5; // Mostly wrapper divs with little text
        }
      }

      // Penalty for high image-to-text ratio (image galleries).
      final images = element.querySelectorAll('img');
      final textLength = _normalizeWhitespace(element.text).length;
      if (images.length > 5 && textLength < images.length * 50) {
        bonus -= 10; // Likely an image gallery, not an article
      }

      if (bonus != 0) {
        candidateScores[element] = entry.value + bonus;
      }
    }

    // Scale by link density: navigation-heavy blocks sink.
    dom.Element? bestCandidate;
    double bestScore = 0;
    final scaledScores = <dom.Element, double>{};
    for (final entry in candidateScores.entries) {
      final scaled = entry.value * (1 - _getLinkDensity(entry.key));
      scaledScores[entry.key] = scaled;
      if (scaled > bestScore) {
        bestScore = scaled;
        bestCandidate = entry.key;
      }
    }

    if (bestCandidate != null && bestScore >= _minCandidateScore) {
      return _joinSiblings(document, bestCandidate, scaledScores, bestScore);
    }

    return document.querySelector('article') ??
        document.querySelector('main') ??
        document.body;
  }

  double _initializeCandidate(dom.Element element) {
    double score;
    switch (element.localName) {
      case 'article':
        score = 30;
      case 'main':
        score = 25;
      case 'section':
        score = 8;
      case 'div':
        score = 5;
      case 'pre':
      case 'td':
      case 'blockquote':
        score = 3;
      case 'figure':
        score = 3;
      case 'address':
      case 'ol':
      case 'ul':
      case 'dl':
      case 'dd':
      case 'dt':
      case 'li':
      case 'form':
        score = -3;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'th':
        score = -5;
      default:
        score = 0;
    }
    return score + _getClassWeight(element);
  }

  double _getClassWeight(dom.Element element) {
    double weight = 0;
    final matchString = '${element.className} ${element.id}';
    if (matchString.trim().isEmpty) return 0;
    if (_positivePattern.hasMatch(matchString)) weight += 25;
    if (_negativePattern.hasMatch(matchString)) weight -= 25;
    return weight;
  }

  /// Joins the best candidate with sibling elements that carry enough score
  /// or look like real prose — recovers articles split across containers.
  dom.Element _joinSiblings(
    dom.Document document,
    dom.Element candidate,
    Map<dom.Element, double> scaledScores,
    double candidateScore,
  ) {
    final parent = candidate.parent;
    if (parent == null) return candidate;

    final threshold = max(10.0, candidateScore * 0.2);
    final candidateClass = candidate.className;
    final article = document.createElement('div');
    var appendedSiblings = 0;

    for (final sibling in parent.children.toList()) {
      var append = false;

      if (identical(sibling, candidate)) {
        append = true;
      } else {
        double bonus = 0;
        if (candidateClass.isNotEmpty && sibling.className == candidateClass) {
          bonus = candidateScore * 0.2;
        }
        final siblingScore = scaledScores[sibling];
        if (siblingScore != null && siblingScore + bonus >= threshold) {
          append = true;
          appendedSiblings++;
        } else if (sibling.localName == 'p') {
          final text = _normalizeWhitespace(sibling.text);
          final linkDensity = _getLinkDensity(sibling);
          if (text.length > 80 && linkDensity < 0.25) {
            append = true;
            appendedSiblings++;
          } else if (text.isNotEmpty &&
              text.length <= 80 &&
              linkDensity == 0 &&
              RegExp(r'\.( |$)').hasMatch(text)) {
            append = true;
            appendedSiblings++;
          }
        }
      }

      if (append) article.append(sibling);
    }

    // If nothing joined, don't add a wrapper for no reason.
    if (appendedSiblings == 0) {
      final only = article.children.length == 1 ? article.children.first : null;
      if (only != null) return only;
    }
    return article;
  }

  double _getLinkDensity(dom.Element element) {
    final textLength = _normalizeWhitespace(element.text).length;
    if (textLength == 0) return 0;

    var linkLength = 0;
    for (final link in element.querySelectorAll('a')) {
      linkLength += _normalizeWhitespace(link.text).length;
    }
    return linkLength / textLength;
  }

  // ---------------------------------------------------------------------
  // Multi-page / pagination support
  // ---------------------------------------------------------------------

  /// Detects common "next page" link patterns and recursively fetches
  /// additional pages, merging their content into the result.
  Future<Map<String, dynamic>?> _handlePagination(
    dom.Document document,
    String currentUrl,
    Map<String, dynamic> currentResult,
  ) async {
    try {
      final nextPageUrl = _findNextPageUrl(document, currentUrl);
      if (nextPageUrl == null) return null;

      final visitedUrls = <String>{currentUrl};
      var mergedContent = currentResult['content'] as String;
      var totalLength = currentResult['length'] as int;
      String? nextUrl = nextPageUrl;

      for (var page = 0; page < _maxPaginationPages && nextUrl != null; page++) {
        final currentNextUrl = nextUrl;
        if (visitedUrls.contains(currentNextUrl)) break;
        visitedUrls.add(currentNextUrl);

        try {
          final response = await _dio.get(currentNextUrl);
          if (response.statusCode != 200) break;

          final nextHtml = response.data.toString();
          final nextResult = processHtml(nextHtml, currentNextUrl);
          if (nextResult == null) break;

          mergedContent += '\n<hr>\n${nextResult['content']}';
          totalLength += nextResult['length'] as int;

          final nextDocument = html_parser.parse(nextHtml);
          nextUrl = _findNextPageUrl(nextDocument, currentNextUrl);
        } catch (_) {
          break;
        }
      }

      if (visitedUrls.length > 1) {
        return {
          ...currentResult,
          'content': mergedContent,
          'length': totalLength,
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Finds the URL for the next page of a paginated article.
  String? _findNextPageUrl(dom.Document document, String currentUrl) {
    try {
      final baseUri = Uri.parse(currentUrl);

      // 1. rel="next" link — the most reliable signal.
      final relNext = document.querySelector('link[rel="next"], a[rel="next"]');
      if (relNext != null) {
        final href = relNext.attributes['href'];
        if (href != null && href.trim().isNotEmpty) {
          return baseUri.resolve(href.trim()).toString();
        }
      }

      // 2. Common "next page" link patterns in pagination.
      for (final selector in [
        '.pagination a.next',
        '.pager a.next',
        '.nav-next a',
        'a.next-page',
        'a[aria-label="Next"]',
        'a[aria-label="Next page"]',
      ]) {
        try {
          final element = document.querySelector(selector);
          if (element != null) {
            final href = element.attributes['href'];
            if (href != null && href.trim().isNotEmpty) {
              return baseUri.resolve(href.trim()).toString();
            }
          }
        } catch (_) {
          // Selector failed — continue.
        }
      }

      // 3. Look for links with text like "Next", "Next Page", "Continue", ">>"
      for (final link in document.querySelectorAll('a[href]')) {
        final text = link.text.trim().toLowerCase();
        if (text == 'next' || text == 'next page' || text == 'continue reading' || text == '»' || text == '>>') {
          final href = link.attributes['href'];
          if (href != null && href.trim().isNotEmpty && !href.startsWith('#')) {
            // Verify it looks like a page URL (contains page number or similar)
            final resolved = baseUri.resolve(href.trim()).toString();
            if (resolved != currentUrl) {
              return resolved;
            }
          }
        }
      }
    } catch (_) {
      // URL parse failure — no next page.
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Open Graph fallback
  // ---------------------------------------------------------------------

  /// When all extraction strategies fail, use Open Graph / meta description
  /// as a last-resort partial result.
  Map<String, dynamic>? _openGraphFallback(
    dom.Document document,
    Map<String, String?> metadata,
  ) {
    final description = metadata['excerpt'];
    if (description == null || description.trim().length < 50) return null;

    final container = document.createElement('div');
    final p = document.createElement('p');
    p.text = description;
    container.append(p);

    return {
      'content': container.outerHtml,
      'excerpt': description,
      'title': metadata['title'],
      'author': metadata['author'],
      'siteName': metadata['siteName'],
      'publishedTime': metadata['publishedTime'],
      'length': description.length,
      'partial': true, // Flag that this is only a partial extraction
    };
  }

  // ---------------------------------------------------------------------
  // Post-processing
  // ---------------------------------------------------------------------

  void _postProcessContent(
      dom.Element articleContent, String baseUrl, String? title) {
    _removeBoilerplate(articleContent);
    _removeDuplicateTitle(articleContent, title);
    _fixLazyImages(articleContent);
    _fixRelativeUrls(articleContent, baseUrl);
    _cleanAttributes(articleContent);
    _removeEmptyParagraphs(articleContent);
  }

  void _removeBoilerplate(dom.Element root) {
    for (final tag in ['script', 'style', 'nav', 'aside', 'form', 'button',
        'footer', 'header']) {
      for (final el in root.querySelectorAll(tag)) {
        el.remove();
      }
    }

    for (final element in root.querySelectorAll('*').toList()) {
      if (element.parent == null) continue;
      final matchString = '${element.className} ${element.id}';
      if (matchString.trim().isEmpty) continue;
      if (_negativePattern.hasMatch(matchString) &&
          !_positivePattern.hasMatch(matchString)) {
        element.remove();
      }
    }
  }

  /// Removes a leading heading that duplicates the article title (it is
  /// rendered separately by the reader UI).
  void _removeDuplicateTitle(dom.Element root, String? title) {
    if (title == null || title.isEmpty) return;
    final normalizedTitle = _normalizeWhitespace(title).toLowerCase();
    for (final heading in root.querySelectorAll('h1, h2')) {
      if (_normalizeWhitespace(heading.text).toLowerCase() == normalizedTitle) {
        heading.remove();
        return;
      }
    }
  }

  /// Promotes lazy-loading attributes to `src` BEFORE data-* attributes are
  /// stripped, so images survive cleaning.
  void _fixLazyImages(dom.Element root) {
    const lazyAttributes = [
      'data-src', 'data-lazy-src', 'data-original', 'data-url',
      'data-hi-res-src', 'data-orig-file',
    ];
    const lazySrcsetAttributes = ['data-srcset', 'data-lazy-srcset'];

    for (final img in root.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      final isPlaceholder = src.isEmpty ||
          src.startsWith('data:image') ||
          src.contains('placeholder') ||
          src.contains('blank.') ||
          src.contains('1x1');
      if (!isPlaceholder) continue;

      String? realSrc;
      for (final attr in lazyAttributes) {
        final value = img.attributes[attr];
        if (value != null && value.trim().isNotEmpty) {
          realSrc = value.trim();
          break;
        }
      }
      realSrc ??= _firstSrcsetUrl(img.attributes['srcset']) ??
          lazySrcsetAttributes
              .map((a) => _firstSrcsetUrl(img.attributes[a]))
              .whereType<String>()
              .firstOrNull;

      if (realSrc != null) {
        img.attributes['src'] = realSrc;
      }
    }
  }

  String? _firstSrcsetUrl(String? srcset) {
    if (srcset == null || srcset.trim().isEmpty) return null;
    final first = srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? null : first;
  }

  /// Resolves relative URLs against the full article URL (honouring its
  /// path and any `<base href>`), not just the host root.
  void _fixRelativeUrls(dom.Element element, String baseUrl) {
    try {
      final baseUri = Uri.parse(baseUrl);

      for (final img in element.querySelectorAll('img[src]')) {
        final src = img.attributes['src']!;
        if (!src.startsWith('http') && !src.startsWith('data:')) {
          img.attributes['src'] = baseUri.resolve(src).toString();
        }
      }

      for (final link in element.querySelectorAll('a[href]')) {
        final href = link.attributes['href']!;
        if (!href.startsWith('http') &&
            !href.startsWith('mailto:') &&
            !href.startsWith('#')) {
          link.attributes['href'] = baseUri.resolve(href).toString();
        }
      }
    } catch (e) {
      print('Error fixing relative URLs: $e');
    }
  }

  static const Set<String> _keptAttributes = {
    'src', 'href', 'alt', 'title', 'width', 'height', 'colspan', 'rowspan',
  };

  void _cleanAttributes(dom.Element root) {
    void clean(dom.Element el) {
      final toRemove = el.attributes.keys
          .where((attr) =>
              !_keptAttributes.contains(attr.toString().toLowerCase()))
          .toList();
      for (final attr in toRemove) {
        el.attributes.remove(attr);
      }
    }

    clean(root);
    for (final el in root.querySelectorAll('*')) {
      clean(el);
    }
  }

  void _removeEmptyParagraphs(dom.Element element) {
    for (final el in element.querySelectorAll('p, div').toList()) {
      // Preserve figure, img, video, audio, picture elements
      final hasMedia = el.querySelector('img, video, audio, picture, figure') != null;
      if (!hasMedia && el.text.trim().isEmpty) {
        el.remove();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  String _normalizeWhitespace(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _excerptFromText(String text, {int maxLength = 200}) {
    if (text.length <= maxLength) return text;
    var cut = text.substring(0, maxLength);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > 0) cut = cut.substring(0, lastSpace);
    return '$cut...';
  }

  void dispose() {
    _dio.close();
  }
}
