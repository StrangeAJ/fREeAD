import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter/foundation.dart';

/// Enhanced article extraction service inspired by Mozilla's Readability.js
class EnhancedArticleService {
  final Dio _dio;

  // Readability constants
  static const int defaultMaxElemsToParse = 0;
  static const int defaultNTopCandidates = 5;
  static const int defaultCharThreshold = 500;
  static const double defaultLinkDensityModifier = 0.0;

  // Flag constants
  static const int flagStripUnlikelys = 0x1;
  static const int flagWeightClasses = 0x2;
  static const int flagCleanConditionally = 0x4;

  EnhancedArticleService() : _dio = Dio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Cache-Control': 'no-cache',
      },
      followRedirects: true,
      maxRedirects: 5,
    );
  }

  /// Extracts article content using enhanced readability algorithm
  Future<Map<String, dynamic>?> extractArticleContent(String url) async {
    try {
      print('Fetching article from: $url');

      String requestUrl = url;
      if (kIsWeb) {
        requestUrl = 'https://api.allorigins.win/get?url=${Uri.encodeComponent(url)}';
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

      print('Successfully fetched HTML content (${htmlContent.length} chars)');

      // Parse and process the article
      final result = await _processArticle(htmlContent, url);

      if (result != null) {
        print('Successfully extracted article content');
        return result;
      }

      return null;
    } catch (e) {
      print('Error extracting article content: $e');
      return null;
    }
  }

  /// Processes HTML content using readability algorithm
  Future<Map<String, dynamic>?> _processArticle(String htmlContent, String url) async {
    try {
      // Parse HTML
      final document = html_parser.parse(htmlContent);

      // Pre-process document
      _prepareDocument(document);

      // Extract article metadata
      final metadata = _extractMetadata(document);

      // Find article content
      final articleContent = _grabArticle(document);

      if (articleContent == null) {
        print('No article content found');
        return null;
      }

      // Post-process content
      _postProcessContent(articleContent, url);

      // Get clean HTML content (not Markdown)
      final cleanContent = articleContent.outerHtml;

      if (cleanContent.isEmpty) {
        print('No clean content extracted');
        return null;
      }

      // Extract excerpt
      final excerpt = _extractExcerpt(cleanContent);

      return {
        'content': cleanContent,
        'excerpt': excerpt,
        'title': metadata['title'],
        'author': metadata['author'],
        'siteName': metadata['siteName'],
        'length': cleanContent.length,
      };
    } catch (e) {
      print('Error processing article: $e');
      return null;
    }
  }

  /// Prepares document for processing (removes unwanted elements)
  void _prepareDocument(dom.Document document) {
    // Remove unwanted elements
    final unwantedTags = ['script', 'style', 'noscript', 'iframe', 'embed', 'object'];
    for (final tag in unwantedTags) {
      final elements = document.querySelectorAll(tag);
      for (final element in elements) {
        element.remove();
      }
    }

    // Remove comments
    _removeComments(document);

    // Convert divs to paragraphs where appropriate
    _convertDivsToParagraphs(document);
  }

  /// Removes HTML comments from document
  void _removeComments(dom.Document document) {
    // Simple approach - remove script and style tags which contain most comments
    void findCommentsRecursively(dom.Node node) {
      for (final child in node.nodes.toList()) {
        if (child.nodeType == dom.Node.COMMENT_NODE) {
          child.remove();
        } else {
          findCommentsRecursively(child);
        }
      }
    }

    findCommentsRecursively(document);
  }

  /// Converts certain divs to paragraphs for better processing
  void _convertDivsToParagraphs(dom.Document document) {
    final divs = document.querySelectorAll('div');

    for (final div in divs) {
      // Only convert if div doesn't contain block elements
      if (!_hasChildBlockElement(div)) {
        final p = document.createElement('p');

        // Move children from div to p
        final children = div.children.toList();
        for (final child in children) {
          p.children.add(child);
        }

        // Copy text content
        if (div.text.trim().isNotEmpty) {
          p.text = div.text;
        }

        // Copy attributes
        for (final attr in div.attributes.keys) {
          p.attributes[attr] = div.attributes[attr]!;
        }

        div.replaceWith(p);
      }
    }
  }

  /// Checks if element has child block elements
  bool _hasChildBlockElement(dom.Element element) {
    final blockElements = ['p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
                          'blockquote', 'pre', 'ul', 'ol', 'li', 'table', 'tr', 'td'];

    for (final child in element.children) {
      if (blockElements.contains(child.localName?.toLowerCase())) {
        return true;
      }
      if (_hasChildBlockElement(child)) {
        return true;
      }
    }
    return false;
  }

  /// Extracts metadata from document
  Map<String, String?> _extractMetadata(dom.Document document) {
    final metadata = <String, String?>{};

    // Extract title
    metadata['title'] = _getTitle(document);

    // Extract author
    metadata['author'] = _getAuthor(document);

    // Extract site name
    metadata['siteName'] = _getSiteName(document);

    return metadata;
  }

  /// Extracts article title
  String? _getTitle(dom.Document document) {
    // Try h1 first
    final h1 = document.querySelector('h1');
    if (h1 != null && h1.text.trim().isNotEmpty) {
      return h1.text.trim();
    }

    // Try title tag
    final title = document.querySelector('title');
    if (title != null && title.text.trim().isNotEmpty) {
      return title.text.trim();
    }

    // Try meta property="og:title"
    final ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle != null) {
      final content = ogTitle.attributes['content'];
      if (content != null && content.trim().isNotEmpty) {
        return content.trim();
      }
    }

    return null;
  }

  /// Extracts article author
  String? _getAuthor(dom.Document document) {
    // Try common author selectors
    final authorSelectors = [
      '.author', '.byline', '.by-author', '.article-author',
      '[rel="author"]', '[itemprop="author"]', '.writer', '.journalist'
    ];

    for (final selector in authorSelectors) {
      final element = document.querySelector(selector);
      if (element != null && element.text.trim().isNotEmpty) {
        return element.text.trim();
      }
    }

    // Try meta tags
    final metaAuthor = document.querySelector('meta[name="author"]');
    if (metaAuthor != null) {
      final content = metaAuthor.attributes['content'];
      if (content != null && content.trim().isNotEmpty) {
        return content.trim();
      }
    }

    return null;
  }

  /// Extracts site name
  String? _getSiteName(dom.Document document) {
    // Try meta property="og:site_name"
    final ogSiteName = document.querySelector('meta[property="og:site_name"]');
    if (ogSiteName != null) {
      final content = ogSiteName.attributes['content'];
      if (content != null && content.trim().isNotEmpty) {
        return content.trim();
      }
    }

    return null;
  }

  /// Main article extraction algorithm (based on Readability.js)
  dom.Element? _grabArticle(dom.Document document) {
    final elementsToScore = <dom.Element>[];

    // Get all paragraph elements and their parents
    final paragraphs = document.querySelectorAll('p, td, pre');

    for (final paragraph in paragraphs) {
      final parentNode = paragraph.parent;
      final grandParentNode = parentNode?.parent;

      final innerText = paragraph.text;

      // Skip if paragraph is too short
      if (innerText.length < 25) continue;

      if (parentNode != null && !elementsToScore.contains(parentNode)) {
        elementsToScore.add(parentNode);
      }

      if (grandParentNode != null && !elementsToScore.contains(grandParentNode)) {
        elementsToScore.add(grandParentNode);
      }
    }

    // Score all elements
    final candidates = <dom.Element, double>{};

    for (final element in elementsToScore) {
      final score = _scoreElement(element);
      candidates[element] = score;
    }

    // Find the best candidate
    dom.Element? bestCandidate;
    double bestScore = 0;

    for (final entry in candidates.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestCandidate = entry.key;
      }
    }

    if (bestCandidate != null && bestScore > 20) {
      return bestCandidate;
    }

    // Fallback to body or first article element
    final article = document.querySelector('article');
    if (article != null) {
      return article;
    }

    final main = document.querySelector('main');
    if (main != null) {
      return main;
    }

    return document.body;
  }

  /// Scores an element based on readability factors
  double _scoreElement(dom.Element element) {
    double score = 0;

    // Score based on tag name
    switch (element.localName?.toLowerCase()) {
      case 'article':
        score += 30;
        break;
      case 'div':
        score += 5;
        break;
      case 'section':
        score += 8;
        break;
      case 'main':
        score += 25;
        break;
      case 'p':
        score += 3;
        break;
      case 'td':
        score += 3;
        break;
      case 'pre':
        score += 3;
        break;
      case 'address':
        score -= 3;
        break;
      case 'blockquote':
        score += 3;
        break;
      case 'form':
        score -= 3;
        break;
      case 'th':
        score -= 5;
        break;
    }

    // Score based on class and id
    final classAndId = '${element.className} ${element.id}';

    // Positive indicators
    final positivePattern = RegExp(
      r'article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story',
      caseSensitive: false
    );
    if (positivePattern.hasMatch(classAndId)) {
      score += 25;
    }

    // Negative indicators
    final negativePattern = RegExp(
      r'-ad-|hidden|^hid$| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget',
      caseSensitive: false
    );
    if (negativePattern.hasMatch(classAndId)) {
      score -= 25;
    }

    // Score based on link density
    final linkDensity = _getLinkDensity(element);
    score -= linkDensity * 10;

    // Score based on text length
    final textLength = element.text.length;
    score += textLength / 100;

    // Score based on paragraph count
    final paragraphCount = element.querySelectorAll('p').length;
    score += paragraphCount * 3;

    // Penalty for too many list items
    final listItems = element.querySelectorAll('li').length;
    if (listItems > paragraphCount) {
      score -= (listItems - paragraphCount) * 3;
    }

    return score;
  }

  /// Calculates link density (ratio of link text to total text)
  double _getLinkDensity(dom.Element element) {
    final textLength = element.text.length;
    if (textLength == 0) return 0;

    final links = element.querySelectorAll('a');
    var linkLength = 0;

    for (final link in links) {
      linkLength += link.text.length;
    }

    return linkLength / textLength;
  }

  /// Post-processes the article content
  void _postProcessContent(dom.Element articleContent, String baseUrl) {
    // Remove unwanted elements
    _removeUnwantedElements(articleContent);

    // Fix relative URLs
    _fixRelativeUrls(articleContent, baseUrl);

    // Clean attributes
    _cleanAttributes(articleContent);

    // Remove empty paragraphs
    _removeEmptyParagraphs(articleContent);
  }

  /// Removes unwanted elements from article content
  void _removeUnwantedElements(dom.Element element) {
    final unwantedSelectors = [
      'script', 'style', 'nav', 'header', 'footer', 'aside',
      '.advertisement', '.ads', '.ad', '.sidebar', '.menu',
      '.comments', '.social', '.share', '.related', '.tags',
      '.navigation', '.breadcrumb', '.pagination', '.toolbar',
      '[class*="ad"]', '[id*="ad"]', '[class*="sidebar"]',
      '[class*="menu"]', '[class*="nav"]', '[class*="comment"]',
      '[class*="social"]', '.widget', '.popup', '.modal',
      '.overlay', '.banner', '.promo', '.sponsored',
    ];

    for (final selector in unwantedSelectors) {
      try {
        final elements = element.querySelectorAll(selector);
        for (final el in elements) {
          el.remove();
        }
      } catch (e) {
        // Continue if selector fails
      }
    }
  }

  /// Fixes relative URLs to absolute URLs
  void _fixRelativeUrls(dom.Element element, String baseUrl) {
    try {
      final uri = Uri.parse(baseUrl);
      final baseUri = Uri(scheme: uri.scheme, host: uri.host, port: uri.port);

      // Fix image src attributes
      final images = element.querySelectorAll('img[src]');
      for (final img in images) {
        final src = img.attributes['src'];
        if (src != null && !src.startsWith('http')) {
          final absoluteUrl = baseUri.resolve(src).toString();
          img.attributes['src'] = absoluteUrl;
        }
      }

      // Fix link href attributes
      final links = element.querySelectorAll('a[href]');
      for (final link in links) {
        final href = link.attributes['href'];
        if (href != null && !href.startsWith('http') && !href.startsWith('mailto:')) {
          final absoluteUrl = baseUri.resolve(href).toString();
          link.attributes['href'] = absoluteUrl;
        }
      }
    } catch (e) {
      print('Error fixing relative URLs: $e');
    }
  }

  /// Cleans unwanted attributes from elements
  void _cleanAttributes(dom.Element element) {
    final unwantedAttributes = [
      'style', 'onclick', 'onload', 'onerror', 'onmouseover', 'onmouseout',
      'onfocus', 'onblur', 'onsubmit', 'onreset', 'onchange', 'onkeydown',
      'onkeyup', 'onkeypress', 'tabindex', 'contenteditable', 'draggable',
      'spellcheck', 'translate', 'dir', 'lang', 'xml:lang', 'xmlns',
    ];

    final attributesToRemove = <String>[];

    void cleanElementAttributes(dom.Element el) {
      attributesToRemove.clear();

      for (final attr in el.attributes.keys) {
        final attrStr = attr.toString().toLowerCase();
        if (unwantedAttributes.contains(attrStr) ||
            attrStr.startsWith('data-') ||
            attrStr.startsWith('aria-') ||
            attrStr.startsWith('on')) {
          attributesToRemove.add(attr.toString());
        }
      }

      for (final attr in attributesToRemove) {
        el.attributes.remove(attr);
      }
    }

    cleanElementAttributes(element);
    final allElements = element.querySelectorAll('*');
    for (final el in allElements) {
      cleanElementAttributes(el);
    }
  }

  /// Removes empty paragraphs and containers
  void _removeEmptyParagraphs(dom.Element element) {
    final paragraphs = element.querySelectorAll('p, div');

    for (final p in paragraphs) {
      if (p.text.trim().isEmpty && p.children.isEmpty) {
        p.remove();
      }
    }
  }

  /// Extracts excerpt from HTML content
  String _extractExcerpt(String htmlContent, {int maxLength = 200}) {
    // Parse HTML and extract text
    final document = html_parser.parse(htmlContent);
    final textContent = document.body?.text ?? htmlContent;

    // Clean up the text
    String excerpt = textContent
        .replaceAll(RegExp(r'\s+'), ' ')  // Replace multiple whitespace with single space
        .trim();

    if (excerpt.length <= maxLength) {
      return excerpt;
    }

    // Find the last complete sentence within the limit
    final sentences = excerpt.split(RegExp(r'[.!?]+'));
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      final testString = buffer.toString() + sentence + '.';
      if (testString.length <= maxLength) {
        buffer.write(sentence);
        buffer.write('.');
      } else {
        break;
      }
    }

    String result = buffer.toString();
    if (result.isEmpty || result.length < 50) {
      // Fallback to simple truncation
      result = excerpt.substring(0, maxLength);
      final lastSpace = result.lastIndexOf(' ');
      if (lastSpace > 0) {
        result = result.substring(0, lastSpace);
      }
      result += '...';
    }

    return result;
  }

  /// Disposes resources
  void dispose() {
    _dio.close();
  }
}
