import 'dart:convert';
import 'dart:math';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'extraction_result.dart';
import 'html_sanitizer.dart';

/// Dart port of the Readability algorithm, merged from the v2
/// `EnhancedArticleService` and `FullArticleService`.
///
/// Strategy, in order of preference:
/// 1. JSON-LD `articleBody` (author supplied full text).
/// 2. Microdata / RDFa `itemprop="articleBody"`.
/// 3. Site specific selectors for known publishers and CMS platforms.
/// 4. Readability style DOM scoring with sibling joining.
/// 5. `<article>` / `<main>` / `<body>` fallback.
/// 6. Open Graph description as a partial last resort.
///
/// Pure Dart on purpose (no Flutter imports) so it can run inside `compute`.
///
/// NOTE: the `html` package only implements a subset of CSS selectors.
/// `:scope`, `:has()` and other functional pseudo classes throw
/// `UnimplementedError`. Never use them here - walk `element.children`
/// instead. `test/readability_test.dart` asserts every selector used by this
/// file is supported.
class Readability {
  const Readability();

  static const int _minParagraphLength = 25;
  static const int _minStructuredBodyLength = 250;
  static const double _minCandidateScore = 15;

  /// Class/id fragments that mark boilerplate. Matched on word boundaries
  /// (split on space, dash, underscore) - never as raw substrings, so
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

  /// Class/id fragments that suggest the element IS the article.
  static final RegExp _positivePattern = RegExp(
    r'(^|[\s_-])(article|body|content|entry|hentry|h-entry|main|page|post|text|'
    r'blog|story|column)([\s_-]|$)',
    caseSensitive: false,
  );

  static final RegExp _articleTypePattern = RegExp(
    r'^(Article|NewsArticle|BlogPosting|ReportageNewsArticle|TechArticle|'
    r'ScholarlyArticle|SocialMediaPosting|LiveBlogPosting|Report|'
    r'AnalysisNewsArticle|OpinionNewsArticle|ReviewNewsArticle)$',
  );

  /// Blocks whose text opens with one of these is navigation chrome.
  static final RegExp _boilerplateOpeners = RegExp(
    r'^(read more|read next|related|related stories|related articles|'
    r'advertisement|sign up|subscribe|share this|follow us|more from|'
    r'also read|recommended|sponsored|newsletter|most read|trending now)\b',
    caseSensitive: false,
  );

  /// Site specific selectors, tried before generic scoring.
  static const Map<String, List<String>> siteSpecificSelectors =
      <String, List<String>>{
        // Platforms / CMS
        'medium.com': [
          'article section',
          '.postArticle-content',
          '.section-content',
        ],
        'substack.com': ['.body.markup', '.available-content', '.post-content'],
        'dev.to': ['#article-body', '.crayons-article__main', '.article-body'],
        'hashnode.dev': ['.prose', '#post-content-parent'],
        'hashnode.com': ['.prose', '#post-content-parent'],
        'ghost.io': ['.gh-content', '.post-content', '.article-content'],
        'wordpress.com': ['.entry-content', '.post-content', '.article-content'],
        'blogspot.com': ['.post-body', '.entry-content'],
        'blogger.com': ['.post-body', '.entry-content'],
        'tumblr.com': ['.post-content', '.body-text'],
        'notion.site': ['.notion-page-content', '.layout-content'],
        // News publishers
        'bbc.com': [
          '[data-component="text-block"]',
          'article',
          '.article__body-content',
          '.story-body__inner',
        ],
        'bbc.co.uk': [
          '[data-component="text-block"]',
          'article',
          '.story-body__inner',
        ],
        'theguardian.com': [
          '.article-body-commercial-selector',
          '.content__article-body',
          '#maincontent',
        ],
        'nytimes.com': [
          'section[name="articleBody"]',
          '.StoryBodyCompanionColumn',
          '.meteredContent',
        ],
        'reuters.com': [
          '[data-testid="ArticleBody"]',
          '.article-body__content',
          '.StandardArticleBody_body',
        ],
        'techcrunch.com': [
          '.entry-content',
          '.article-content',
          '.wp-block-post-content',
        ],
        'theverge.com': [
          '.duet--article--article-body-component-container',
          '.c-entry-content',
        ],
        'arstechnica.com': [
          '.post-content',
          '.article-content',
          '.article-guts',
        ],
        'wired.com': ['.body__inner-container', '.article__body'],
        'engadget.com': ['.article-text', '.o-article_block'],
        'cnbc.com': ['.ArticleBody-articleBody', '.group'],
        'bloomberg.com': ['.body-content', '.body-copy-v2'],
        'washingtonpost.com': ['.article-body', '.grid-body'],
        'ndtv.com': ['.sp-cn', '.ins_storybody', '#ins_storybody'],
        'timesofindia.indiatimes.com': ['._s30J', '.ga-headlines', '.Normal'],
        'indiatimes.com': ['._s30J', '.Normal'],
        'thehindu.com': ['.articlebodycontent', '[itemprop="articleBody"]'],
        'indianexpress.com': ['.story_details', '.full-details'],
        'hindustantimes.com': ['.detail', '.storyDetails'],
      };

  /// Parses [html] fetched from [url] into an [ExtractionResult].
  ///
  /// Returns null when nothing usable could be found at all.
  ExtractionResult? parse(
    String html,
    String url, {
    String source = ExtractionSource.http,
  }) {
    if (html.trim().isEmpty) return null;

    dom.Document document;
    try {
      document = html_parser.parse(html);
    } catch (_) {
      return null;
    }

    // Read structured data and metadata BEFORE scripts are stripped.
    final jsonLd = _extractJsonLd(document);
    final metadata = _extractMetadata(document, jsonLd);
    final bodyText = _normalize(document.body?.text ?? '');
    final looksJsOnly = _looksJavaScriptOnly(document, bodyText);

    dom.Element? content;

    // 1. JSON-LD articleBody.
    final articleBody = jsonLd?['articleBody'];
    if (articleBody != null &&
        articleBody.trim().length >= _minStructuredBodyLength) {
      content = _paragraphsFromText(document, articleBody);
    }

    // 2. Microdata / RDFa.
    content ??= _microdataArticleBody(document);

    // 3. Site specific selectors.
    content ??= _siteSpecific(document, url);

    // 4. Readability scoring.
    if (content == null) {
      _prepareDocument(document);
      content = _grabArticle(document);
    }

    if (content == null) {
      return _openGraphFallback(metadata, url, source);
    }

    _postProcess(content, url, metadata['title']);

    final rawHtml = content.innerHtml;
    final safeHtml = HtmlSanitizer.sanitize(rawHtml, baseUrl: url);
    final text = HtmlSanitizer.toPlainText(safeHtml);
    if (text.trim().isEmpty) {
      return _openGraphFallback(metadata, url, source);
    }

    final words = _wordCount(text);
    // A page whose *rendered* body is empty can still carry the article in
    // structured data, so only trust the JS-only signal when little text was
    // recovered.
    final jsRequired = looksJsOnly && text.trim().length < 600;
    final quality = jsRequired
        ? 0.0
        : _score(
            element: content,
            text: text,
            words: words,
            bodyTextLength: bodyText.length,
          );

    return ExtractionResult(
      html: safeHtml,
      text: text,
      title: metadata['title'],
      author: metadata['author'],
      siteName: metadata['siteName'] ?? _hostOf(url),
      excerpt: metadata['excerpt'] ?? HtmlSanitizer.excerpt(safeHtml),
      leadImageUrl: metadata['leadImage'] ?? _firstImage(safeHtml),
      publishedAt: metadata['publishedTime'],
      wordCount: words,
      quality: quality,
      source: source,
      partial: jsRequired || words < 150,
    );
  }

  // -------------------------------------------------------------------------
  // Structured data
  // -------------------------------------------------------------------------

  Map<String, String?>? _extractJsonLd(dom.Document document) {
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      try {
        final decoded = jsonDecode(script.text);
        final roots = decoded is List ? decoded : <dynamic>[decoded];
        for (final root in roots) {
          if (root is! Map) continue;
          final graph = root['@graph'];
          final nodes = <dynamic>[root, if (graph is List) ...graph];
          for (final node in nodes) {
            if (node is! Map) continue;
            final rawType = node['@type'];
            final types = rawType is List
                ? rawType.map((t) => t.toString())
                : <String>[rawType?.toString() ?? ''];
            if (!types.any(_articleTypePattern.hasMatch)) continue;

            return <String, String?>{
              'articleBody': node['articleBody']?.toString(),
              'headline': node['headline']?.toString(),
              'author': _jsonLdAuthor(node['author']),
              'datePublished': node['datePublished']?.toString(),
              'description': node['description']?.toString(),
              'image': _jsonLdImage(node['image']),
            };
          }
        }
      } catch (_) {
        // Malformed JSON-LD - keep looking.
      }
    }
    return null;
  }

  String? _jsonLdAuthor(dynamic author) {
    if (author == null) return null;
    if (author is String) return author;
    if (author is Map) return author['name']?.toString();
    if (author is List && author.isNotEmpty) {
      final names = author.map(_jsonLdAuthor).whereType<String>().toList();
      return names.isEmpty ? null : names.join(', ');
    }
    return null;
  }

  String? _jsonLdImage(dynamic image) {
    if (image == null) return null;
    if (image is String) return image;
    if (image is Map) return image['url']?.toString();
    if (image is List && image.isNotEmpty) return _jsonLdImage(image.first);
    return null;
  }

  dom.Element _paragraphsFromText(dom.Document document, String text) {
    final container = document.createElement('div');
    final paragraphs = text
        .split(RegExp(r'\r?\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    for (final paragraph in paragraphs) {
      final p = document.createElement('p');
      p.text = paragraph;
      container.append(p);
    }
    return container;
  }

  dom.Element? _microdataArticleBody(dom.Document document) {
    for (final selector in const [
      '[itemprop="articleBody"]',
      '[property="articleBody"]',
    ]) {
      final element = _query(document, selector);
      if (element == null) continue;
      if (_normalize(element.text).length >= _minStructuredBodyLength) {
        return element;
      }
    }
    return null;
  }

  dom.Element? _siteSpecific(dom.Document document, String url) {
    final host = _hostOf(url);
    if (host == null) return null;
    for (final entry in siteSpecificSelectors.entries) {
      if (!host.contains(entry.key)) continue;
      for (final selector in entry.value) {
        final element = _query(document, selector);
        if (element == null) continue;
        if (_normalize(element.text).length > 200) return element;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Metadata
  // -------------------------------------------------------------------------

  Map<String, String?> _extractMetadata(
    dom.Document document,
    Map<String, String?>? jsonLd,
  ) {
    return <String, String?>{
      'title': _nonEmpty(jsonLd?['headline']) ?? _title(document),
      'author': _nonEmpty(jsonLd?['author']) ?? _author(document),
      'siteName': _meta(document, const ['meta[property="og:site_name"]']),
      'publishedTime':
          _nonEmpty(jsonLd?['datePublished']) ?? _publishedTime(document),
      'excerpt': _nonEmpty(jsonLd?['description']) ?? _description(document),
      'leadImage':
          _nonEmpty(jsonLd?['image']) ??
          _meta(document, const [
            'meta[property="og:image"]',
            'meta[name="twitter:image"]',
            'meta[name="twitter:image:src"]',
          ]),
    };
  }

  String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _meta(dom.Document document, List<String> selectors) {
    for (final selector in selectors) {
      final content = _query(document, selector)?.attributes['content']?.trim();
      if (content != null && content.isNotEmpty) return content;
    }
    return null;
  }

  String? _title(dom.Document document) {
    final meta = _meta(document, const [
      'meta[property="og:title"]',
      'meta[name="twitter:title"]',
    ]);
    if (meta != null) return meta;

    final h1 = _query(document, 'h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;

    final title = _query(document, 'title')?.text.trim();
    if (title != null && title.isNotEmpty) {
      final parts = title.split(RegExp(r'\s[|\-–—]\s'));
      if (parts.length > 1 && parts.first.trim().length >= 15) {
        return parts.first.trim();
      }
      return title;
    }
    return null;
  }

  String? _author(dom.Document document) {
    final meta = _meta(document, const [
      'meta[name="author"]',
      'meta[property="article:author"]',
      'meta[name="parsely-author"]',
    ]);
    if (meta != null && !meta.startsWith('http')) return meta;

    for (final selector in const [
      '[rel="author"]',
      '[itemprop="author"]',
      '.author',
      '.byline',
      '.by-author',
      '.article-author',
    ]) {
      final text = _query(document, selector)?.text.trim();
      if (text != null && text.isNotEmpty && text.length < 120) {
        return _normalize(text);
      }
    }
    return null;
  }

  String? _publishedTime(dom.Document document) {
    final meta = _meta(document, const [
      'meta[property="article:published_time"]',
      'meta[name="date"]',
      'meta[name="parsely-pub-date"]',
      'meta[itemprop="datePublished"]',
    ]);
    if (meta != null) return meta;
    return _query(document, 'time[datetime]')?.attributes['datetime'];
  }

  String? _description(dom.Document document) => _meta(document, const [
    'meta[property="og:description"]',
    'meta[name="description"]',
    'meta[name="twitter:description"]',
  ]);

  // -------------------------------------------------------------------------
  // Document preparation
  // -------------------------------------------------------------------------

  void _prepareDocument(dom.Document document) {
    _recoverNoscriptImages(document);

    for (final tag in const [
      'script',
      'style',
      'noscript',
      'template',
      'iframe',
      'embed',
      'object',
      'link',
      'svg',
      'form',
      'button',
      'input',
      'select',
      'textarea',
    ]) {
      for (final element in document.querySelectorAll(tag)) {
        element.remove();
      }
    }

    _removeComments(document);
    _stripUnlikelyCandidates(document);
    _convertDivsToParagraphs(document);
  }

  /// Promotes real `<img>` tags out of `<noscript>` before it is stripped.
  void _recoverNoscriptImages(dom.Document document) {
    for (final noscript in document.querySelectorAll('noscript').toList()) {
      try {
        final fragment = html_parser.parseFragment(noscript.innerHtml);
        for (final img in fragment.querySelectorAll('img')) {
          final src = img.attributes['src'] ?? '';
          if (src.isEmpty || !src.startsWith('http')) continue;
          final replacement = document.createElement('img');
          replacement.attributes.addAll(img.attributes);
          noscript.parentNode?.insertBefore(replacement, noscript);
        }
      } catch (_) {
        // Unparseable noscript - ignore.
      }
    }
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

  void _stripUnlikelyCandidates(dom.Document document) {
    final body = document.body;
    if (body == null) return;

    for (final element in body.querySelectorAll('*').toList()) {
      if (element.parentNode == null) continue;

      final tag = element.localName ?? '';
      if (tag == 'body' ||
          tag == 'html' ||
          tag == 'article' ||
          tag == 'main') {
        continue;
      }

      if (tag == 'nav' || tag == 'aside') {
        element.remove();
        continue;
      }
      if ((tag == 'header' || tag == 'footer') &&
          element.parent?.localName == 'body') {
        element.remove();
        continue;
      }

      final match = '${element.className} ${element.id}';
      if (match.trim().isEmpty) continue;
      if (_negativePattern.hasMatch(match) &&
          !_positivePattern.hasMatch(match)) {
        element.remove();
      }
    }
  }

  /// Converts divs with no block-level children into paragraphs so they get
  /// scored. Moves child nodes so inline markup survives.
  void _convertDivsToParagraphs(dom.Document document) {
    for (final div in document.querySelectorAll('div').toList()) {
      if (div.parentNode == null) continue;
      if (_hasBlockChild(div)) continue;
      if (div.text.trim().isEmpty) continue;

      final p = document.createElement('p');
      for (final node in div.nodes.toList()) {
        p.append(node);
      }
      p.attributes.addAll(div.attributes);
      div.replaceWith(p);
    }
  }

  static const Set<String> _blockTags = <String>{
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre',
    'ul', 'ol', 'li', 'table', 'tr', 'td', 'section', 'article', 'figure',
  };

  bool _hasBlockChild(dom.Element element) {
    for (final child in element.children) {
      if (_blockTags.contains(child.localName)) return true;
      if (_hasBlockChild(child)) return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Scoring
  // -------------------------------------------------------------------------

  dom.Element? _grabArticle(dom.Document document) {
    final scores = <dom.Element, double>{};

    for (final paragraph in document.querySelectorAll(
      'p, td, pre, blockquote',
    )) {
      final parent = paragraph.parent;
      if (parent == null) continue;
      final grandParent = parent.parent;

      final text = _normalize(paragraph.text);
      if (text.length < _minParagraphLength) continue;

      double contentScore = 1;
      contentScore += ','.allMatches(text).length;
      contentScore += '，'.allMatches(text).length;
      contentScore += min(text.length / 100, 3);

      scores.update(
        parent,
        (s) => s + contentScore,
        ifAbsent: () => _initialScore(parent) + contentScore,
      );
      if (grandParent != null) {
        scores.update(
          grandParent,
          (s) => s + contentScore / 2,
          ifAbsent: () => _initialScore(grandParent) + contentScore / 2,
        );
      }
    }

    for (final entry in scores.entries.toList()) {
      final element = entry.key;
      double bonus = 0;

      bonus += element.querySelectorAll('blockquote').length * 3;
      bonus += element.querySelectorAll('figure').length * 3;

      for (final table in element.querySelectorAll('table')) {
        if (table.querySelectorAll('tr').length > 1) bonus += 3;
      }

      // `:scope > div` is NOT supported by the html package - walk children.
      final childDivs = element.children
          .where((child) => child.localName == 'div')
          .toList();
      if (childDivs.length > 5) {
        final textInDivs = childDivs.fold<int>(
          0,
          (sum, d) => sum + d.text.trim().length,
        );
        final totalText = element.text.trim().length;
        if (totalText > 0 && textInDivs / totalText < 0.3) bonus -= 5;
      }

      final images = element.querySelectorAll('img');
      final textLength = _normalize(element.text).length;
      if (images.length > 5 && textLength < images.length * 50) bonus -= 10;

      if (bonus != 0) scores[element] = entry.value + bonus;
    }

    dom.Element? best;
    double bestScore = 0;
    final scaled = <dom.Element, double>{};
    for (final entry in scores.entries) {
      final value = entry.value * (1 - _linkDensity(entry.key));
      scaled[entry.key] = value;
      if (value > bestScore) {
        bestScore = value;
        best = entry.key;
      }
    }

    if (best != null && bestScore >= _minCandidateScore) {
      return _joinSiblings(document, best, scaled, bestScore);
    }

    return _query(document, 'article') ??
        _query(document, 'main') ??
        document.body;
  }

  double _initialScore(dom.Element element) {
    final double score = switch (element.localName) {
      'article' => 30,
      'main' => 25,
      'section' => 8,
      'div' => 5,
      'pre' || 'td' || 'blockquote' || 'figure' => 3,
      'address' ||
      'ol' ||
      'ul' ||
      'dl' ||
      'dd' ||
      'dt' ||
      'li' ||
      'form' => -3,
      'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'th' => -5,
      _ => 0,
    };
    return score + _classWeight(element);
  }

  double _classWeight(dom.Element element) {
    final match = '${element.className} ${element.id}';
    if (match.trim().isEmpty) return 0;
    double weight = 0;
    if (_positivePattern.hasMatch(match)) weight += 25;
    if (_negativePattern.hasMatch(match)) weight -= 25;
    return weight;
  }

  dom.Element _joinSiblings(
    dom.Document document,
    dom.Element candidate,
    Map<dom.Element, double> scaled,
    double candidateScore,
  ) {
    final parent = candidate.parent;
    if (parent == null) return candidate;

    final threshold = max(10.0, candidateScore * 0.2);
    final candidateClass = candidate.className;
    final article = document.createElement('div');
    var appended = 0;

    for (final sibling in parent.children.toList()) {
      var append = false;

      if (identical(sibling, candidate)) {
        append = true;
      } else {
        double bonus = 0;
        if (candidateClass.isNotEmpty && sibling.className == candidateClass) {
          bonus = candidateScore * 0.2;
        }
        final siblingScore = scaled[sibling];
        if (siblingScore != null && siblingScore + bonus >= threshold) {
          append = true;
          appended++;
        } else if (sibling.localName == 'p') {
          final text = _normalize(sibling.text);
          final density = _linkDensity(sibling);
          if (text.length > 80 && density < 0.25) {
            append = true;
            appended++;
          } else if (text.isNotEmpty &&
              text.length <= 80 &&
              density == 0 &&
              RegExp(r'\.( |$)').hasMatch(text)) {
            append = true;
            appended++;
          }
        }
      }

      if (append) article.append(sibling);
    }

    if (appended == 0) {
      final only = article.children.length == 1 ? article.children.first : null;
      if (only != null) return only;
    }
    return article;
  }

  double _linkDensity(dom.Element element) {
    final textLength = _normalize(element.text).length;
    if (textLength == 0) return 0;
    var linkLength = 0;
    for (final link in element.querySelectorAll('a')) {
      linkLength += _normalize(link.text).length;
    }
    return linkLength / textLength;
  }

  // -------------------------------------------------------------------------
  // Post-processing
  // -------------------------------------------------------------------------

  void _postProcess(dom.Element content, String baseUrl, String? title) {
    _removeBoilerplate(content);
    _removeDuplicateTitle(content, title);
    _fixLazyImages(content);
    _fixRelativeUrls(content, baseUrl);
    _removeBoilerplateBlocks(content);
    _removeEmptyParagraphs(content);
  }

  void _removeBoilerplate(dom.Element root) {
    for (final tag in const [
      'script',
      'style',
      'nav',
      'aside',
      'form',
      'button',
      'footer',
      'header',
      'noscript',
    ]) {
      for (final element in root.querySelectorAll(tag)) {
        element.remove();
      }
    }

    for (final element in root.querySelectorAll('*').toList()) {
      if (element.parentNode == null) continue;
      final match = '${element.className} ${element.id}';
      if (match.trim().isEmpty) continue;
      if (_negativePattern.hasMatch(match) &&
          !_positivePattern.hasMatch(match)) {
        element.remove();
      }
    }
  }

  void _removeDuplicateTitle(dom.Element root, String? title) {
    if (title == null || title.isEmpty) return;
    final normalized = _normalize(title).toLowerCase();
    for (final heading in root.querySelectorAll('h1, h2')) {
      if (_normalize(heading.text).toLowerCase() == normalized) {
        heading.remove();
        return;
      }
    }
  }

  /// Promotes lazy-loading attributes to `src` and picks the largest srcset
  /// candidate, before attributes are stripped by the sanitiser.
  void _fixLazyImages(dom.Element root) {
    const lazyAttributes = <String>[
      'data-src',
      'data-lazy-src',
      'data-original',
      'data-url',
      'data-hi-res-src',
      'data-orig-file',
      'data-image-src',
      'data-echo',
    ];
    const lazySrcsets = <String>[
      'data-srcset',
      'data-lazy-srcset',
      'data-responsive-src',
    ];

    for (final img in root.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      final placeholder =
          src.isEmpty ||
          src.startsWith('data:image') ||
          src.contains('placeholder') ||
          src.contains('blank.') ||
          src.contains('1x1') ||
          src.contains('transparent.');
      if (!placeholder) continue;

      String? real;
      for (final attribute in lazyAttributes) {
        final value = img.attributes[attribute];
        if (value != null && value.trim().isNotEmpty) {
          real = value.trim();
          break;
        }
      }
      real ??= _largestSrcset(img.attributes['srcset']);
      for (final attribute in lazySrcsets) {
        real ??= _largestSrcset(img.attributes[attribute]);
      }

      if (real != null && real.isNotEmpty) {
        img.attributes['src'] = real;
        img.attributes.remove('srcset');
      }
    }

    // `<picture><source srcset>` without a usable `<img>` inside.
    for (final picture in root.querySelectorAll('picture')) {
      final img = picture.querySelector('img');
      final currentSrc = img?.attributes['src'] ?? '';
      if (currentSrc.isNotEmpty && !currentSrc.startsWith('data:')) continue;
      String? best;
      for (final source in picture.querySelectorAll('source')) {
        best ??= _largestSrcset(source.attributes['srcset']);
      }
      if (best == null) continue;
      if (img != null) {
        img.attributes['src'] = best;
      } else {
        final replacement = dom.Element.tag('img');
        replacement.attributes['src'] = best;
        picture.append(replacement);
      }
    }
  }

  String? _largestSrcset(String? srcset) {
    if (srcset == null || srcset.trim().isEmpty) return null;
    String? bestUrl;
    var bestWidth = -1;
    for (final part in srcset.split(',')) {
      final tokens = part.trim().split(RegExp(r'\s+'));
      if (tokens.isEmpty || tokens.first.isEmpty) continue;
      var width = 0;
      if (tokens.length > 1) {
        final descriptor = tokens[1];
        if (descriptor.endsWith('w')) {
          width =
              int.tryParse(descriptor.substring(0, descriptor.length - 1)) ?? 0;
        } else if (descriptor.endsWith('x')) {
          final scale =
              double.tryParse(descriptor.substring(0, descriptor.length - 1)) ??
              1;
          width = (scale * 1000).round();
        }
      }
      if (width > bestWidth) {
        bestWidth = width;
        bestUrl = tokens.first;
      }
    }
    return bestUrl;
  }

  void _fixRelativeUrls(dom.Element element, String baseUrl) {
    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme) return;

    for (final img in element.querySelectorAll('img[src]')) {
      final src = img.attributes['src']!;
      if (!src.startsWith('http') && !src.startsWith('data:')) {
        try {
          img.attributes['src'] = base.resolve(src).toString();
        } catch (_) {
          // Unresolvable - the sanitiser will drop it.
        }
      }
    }

    for (final link in element.querySelectorAll('a[href]')) {
      final href = link.attributes['href']!;
      if (!href.startsWith('http') &&
          !href.startsWith('mailto:') &&
          !href.startsWith('#')) {
        try {
          link.attributes['href'] = base.resolve(href).toString();
        } catch (_) {
          // Leave it; the sanitiser resolves against the base too.
        }
      }
    }
  }

  /// Drops short blocks that are navigation chrome ("Read more", "Related").
  void _removeBoilerplateBlocks(dom.Element root) {
    for (final element in root.querySelectorAll('p, div, section').toList()) {
      if (element.parentNode == null) continue;
      final text = _normalize(element.text);
      if (text.isEmpty || text.length > 200) continue;
      if (!_boilerplateOpeners.hasMatch(text)) continue;
      if (element.querySelector('img') != null) continue;
      element.remove();
    }
  }

  void _removeEmptyParagraphs(dom.Element element) {
    for (final el in element.querySelectorAll('p, div').toList()) {
      if (el.parentNode == null) continue;
      if (el.querySelector('img, video, audio, picture, figure') != null) {
        continue;
      }
      if (el.text.trim().isEmpty) el.remove();
    }
  }

  // -------------------------------------------------------------------------
  // Quality
  // -------------------------------------------------------------------------

  double _score({
    required dom.Element element,
    required String text,
    required int words,
    required int bodyTextLength,
  }) {
    final paragraphs = element
        .querySelectorAll('p')
        .where((p) => _normalize(p.text).length >= _minParagraphLength)
        .toList();
    final paragraphCount = paragraphs.isEmpty
        ? (text.length > 400 ? 1 : 0)
        : paragraphs.length;
    final avgParagraph = paragraphs.isEmpty
        ? text.length.toDouble()
        : paragraphs
                  .map((p) => _normalize(p.text).length)
                  .reduce((a, b) => a + b) /
              paragraphs.length;
    final density = _linkDensity(element);
    final ratio = bodyTextLength <= 0
        ? 1.0
        : (text.length / bodyTextLength).clamp(0.0, 1.0);

    double quality = 0;
    quality += min(paragraphCount / 8, 1) * 0.30;
    quality += min(avgParagraph / 220, 1) * 0.25;
    quality += (1 - min(density / 0.35, 1)) * 0.20;
    quality += min(ratio / 0.5, 1) * 0.15;
    quality += min(words / 400, 1) * 0.10;
    return quality.clamp(0.0, 1.0);
  }

  static final RegExp _jsPhrases = RegExp(
    r'(enable javascript|turn on javascript|javascript is (disabled|required)|'
    r'please enable js|requires javascript)',
    caseSensitive: false,
  );

  bool _looksJavaScriptOnly(dom.Document document, String bodyText) {
    if (_jsPhrases.hasMatch(bodyText) && bodyText.length < 2000) return true;
    if (bodyText.length >= 300) return false;

    if (document.querySelectorAll('noscript').isNotEmpty) return true;
    for (final id in const ['__next', 'root', 'app', '__nuxt']) {
      final mount = _query(document, '#$id');
      if (mount != null && mount.text.trim().length < 100) return true;
    }
    if (_query(document, 'app-root') != null) return true;
    return bodyText.length < 300;
  }

  // -------------------------------------------------------------------------
  // Fallbacks / helpers
  // -------------------------------------------------------------------------

  ExtractionResult? _openGraphFallback(
    Map<String, String?> metadata,
    String url,
    String source,
  ) {
    final description = metadata['excerpt'];
    if (description == null || description.trim().length < 50) return null;
    final html = '<p>${_escape(description.trim())}</p>';
    final text = description.trim();
    return ExtractionResult(
      html: html,
      text: text,
      title: metadata['title'],
      author: metadata['author'],
      siteName: metadata['siteName'] ?? _hostOf(url),
      excerpt: text,
      leadImageUrl: metadata['leadImage'],
      publishedAt: metadata['publishedTime'],
      wordCount: _wordCount(text),
      quality: 0,
      source: source,
      partial: true,
    );
  }

  /// `querySelector` that never throws on selectors the html package cannot
  /// evaluate.
  dom.Element? _query(dom.Document document, String selector) {
    try {
      return document.querySelector(selector);
    } catch (_) {
      return null;
    }
  }

  String? _firstImage(String html) {
    try {
      final fragment = html_parser.parseFragment(html);
      final img = fragment.querySelector('img');
      final src = img?.attributes['src'];
      if (src == null || src.isEmpty || src.startsWith('data:')) return null;
      return src;
    } catch (_) {
      return null;
    }
  }

  static String? _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static int _wordCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
