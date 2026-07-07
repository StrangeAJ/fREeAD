import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class FullArticleService {
  final Dio _dio = Dio();

  /// Boilerplate class/id fragments matched on word boundaries — a raw
  /// `[class*="ad"]` substring selector would also remove elements like
  /// "read-more" or "download".
  static final RegExp _negativePattern = RegExp(
    r'(^|[\s_-])(ad|ads|advert|advertisement|banner|breadcrumb|comment|comments|'
    r'disqus|footer|gdpr|header|menu|nav|navbar|navigation|outbrain|pager|'
    r'pagination|popup|promo|related|share|sharing|sidebar|skyscraper|social|'
    r'sponsor|sponsored|subscribe|newsletter|taboola|toolbar|widget|masthead|'
    r'cookie|consent|modal|overlay)([\s_-]|$)',
    caseSensitive: false,
  );

  static final RegExp _positivePattern = RegExp(
    r'(^|[\s_-])(article|body|content|entry|main|page|post|text|blog|story)([\s_-]|$)',
    caseSensitive: false,
  );

  /// Site-specific CSS selectors for popular content platforms.
  /// When the URL matches a domain key, these selectors are tried first
  /// (bypassing scoring entirely for maximum accuracy).
  static const Map<String, List<String>> _siteSpecificSelectors = {
    'medium.com': ['article section', '.postArticle-content', '.section-content'],
    'dev.to': ['.crayons-article__main', '#article-body', '.article-body'],
    'substack.com': ['.body.markup', '.post-content', '.available-content'],
    'ghost.io': ['.post-content', '.gh-content', '.article-content'],
    'blogger.com': ['.post-body.entry-content', '.post-body'],
    'tumblr.com': ['.post-content', '.body-text'],
    'hashnode.dev': ['.prose', '#post-content-parent'],
    'notion.site': ['.notion-page-content', '.layout-content'],
    'bbc.com': ['[data-component="text-block"]', '.article__body-content', '.story-body__inner'],
    'nytimes.com': ['.StoryBodyCompanionColumn', '.css-53u6y8', '.meteredContent'],
    'theguardian.com': ['.article-body-commercial-selector', '.content__article-body'],
    'reuters.com': ['.article-body__content', '.StandardArticleBody_body'],
    'techcrunch.com': ['.article-content', '.entry-content'],
  };

  FullArticleService() {
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 5;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    };
  }

  /// Fetches and parses the full article content from the given URL
  Future<String?> fetchFullArticleContent(String url) async {
    try {
      print('Fetching full article from: $url');
      
      // Fetch the webpage
      final response = await _dio.get(url);
      if (response.statusCode != 200) {
        print('Failed to fetch article: ${response.statusCode}');
        return null;
      }

      final htmlContent = response.data.toString();
      print('Successfully fetched HTML content (${htmlContent.length} chars)');
      
      // Parse the HTML
      final document = html_parser.parse(htmlContent);
      
      // Extract clean readable content
      final extractedContent = _extractReadableContent(document, url);
      
      if (extractedContent != null && extractedContent.isNotEmpty) {
        print('Extracted content length: ${extractedContent.length}');
        return extractedContent;
      }
      
      return null;
    } catch (e) {
      print('Error fetching full article: $e');
      return null;
    }
  }

  /// Extracts readable content from HTML document using readability-like algorithm
  String? _extractReadableContent(dom.Document document, String baseUrl) {
    try {
      // Recover images from noscript before stripping
      _recoverNoscriptImages(document);

      // Remove unwanted elements
      _removeUnwantedElements(document);

      // Try site-specific selectors first (bypasses scoring for known sites)
      final siteSpecificElement = _trySiteSpecificSelectors(document, baseUrl);
      if (siteSpecificElement != null) {
        return _processAndCleanHtml(siteSpecificElement, baseUrl);
      }
      
      // Try common article selectors
      final articleElement = _tryCommonSelectorsElement(document);
      if (articleElement != null) {
        return _processAndCleanHtml(articleElement, baseUrl);
      }
      
      // If common selectors fail, use content scoring algorithm
      final scoredElement = _scoreAndSelectContentElement(document);
      if (scoredElement != null) {
        return _processAndCleanHtml(scoredElement, baseUrl);
      }
      
      return null;
    } catch (e) {
      print('Error extracting readable content: $e');
      return null;
    }
  }

  /// Recovers real <img> tags from inside <noscript> before stripping.
  void _recoverNoscriptImages(dom.Document document) {
    for (final noscript in document.querySelectorAll('noscript').toList()) {
      try {
        final fragment = html_parser.parseFragment(noscript.innerHtml);
        final images = fragment.querySelectorAll('img');
        for (final img in images) {
          final src = img.attributes['src'] ?? '';
          if (src.isNotEmpty && src.startsWith('http')) {
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

  /// Removes unwanted elements from the document
  void _removeUnwantedElements(dom.Document document) {
    for (final tag in ['script', 'style', 'noscript', 'nav', 'aside', 'form']) {
      for (final element in document.querySelectorAll(tag)) {
        element.remove();
      }
    }
    // Only top-level header/footer — articles can legitimately contain them.
    for (final element in document.querySelectorAll('body > header, body > footer')) {
      element.remove();
    }
    final body = document.body;
    if (body != null) _removeBoilerplateByClass(body);
  }

  /// Removes elements whose class/id marks them as boilerplate, unless they
  /// also look like article content.
  void _removeBoilerplateByClass(dom.Element root) {
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

  /// Tries site-specific selectors when the URL matches a known domain.
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
                final text = element.text.trim();
                if (text.length > 200) {
                  return element;
                }
              }
            } catch (_) {
              // Selector may not be supported — continue.
            }
          }
        }
      }
    } catch (_) {
      // URL parse failure — skip.
    }
    return null;
  }

  /// Tries common article content selectors and returns the element
  dom.Element? _tryCommonSelectorsElement(dom.Document document) {
    final commonSelectors = [
      // Standard semantic selectors
      'article',
      '[role="main"]',
      'main',
      // WordPress patterns
      '.entry-content',
      '.post-content',
      '.article-content',
      '#content .entry-content',
      // Ghost CMS patterns
      '.post-content',
      '.gh-content',
      // Generic content patterns
      '.article-body',
      '.post-body',
      '.story-body',
      '.text',
      '.article-text',
      '.content',
      '.main-content',
      '#content',
      '#main',
      '#article',
      '.container .content',
      // Substack patterns
      '.body.markup',
      '.available-content',
      // Misc CMS patterns
      '.field-item',
      '.node-content',
      '.td-post-content',
      '#main-content',
    ];

    for (final selector in commonSelectors) {
      try {
        final element = document.querySelector(selector);
        if (element != null) {
          final text = element.text.trim();
          if (text.length > 200) { // Minimum content length
            return element;
          }
        }
      } catch (e) {
        // Continue if selector fails
      }
    }
    
    return null;
  }

  /// Scores content blocks and selects the best element
  dom.Element? _scoreAndSelectContentElement(dom.Document document) {
    final contentBlocks = document.querySelectorAll('div, article, section, p');
    dom.Element? bestElement;
    double bestScore = 0;

    for (final element in contentBlocks) {
      final score = _scoreElement(element);
      if (score > bestScore) {
        bestScore = score;
        bestElement = element;
      }
    }

    if (bestElement != null && bestScore > 10) {
      return bestElement;
    }

    return null;
  }

  /// Processes and cleans HTML content while preserving formatting
  String? _processAndCleanHtml(dom.Element element, String baseUrl) {
    try {
      // Clone the element to avoid modifying the original
      final clonedElement = element.clone(true);
      
      // Remove unwanted child elements
      _removeUnwantedChildElements(clonedElement);
      
      // Fix relative URLs
      _fixRelativeUrls(clonedElement, baseUrl);
      
      // Clean up the HTML
      _cleanHtmlElement(clonedElement);
      
      // Get the inner HTML
      final html = clonedElement.innerHtml;
      
      if (html.trim().isEmpty) {
        return null;
      }
      
      return html;
    } catch (e) {
      print('Error processing HTML: $e');
      return null;
    }
  }

  /// Removes unwanted child elements from the main content
  void _removeUnwantedChildElements(dom.Element element) {
    for (final tag in ['script', 'style', 'noscript', 'nav', 'aside', 'form']) {
      for (final el in element.querySelectorAll(tag)) {
        el.remove();
      }
    }
    _removeBoilerplateByClass(element);
  }

  /// Fixes relative URLs to absolute URLs, resolving against the full
  /// article URL (with path), not just the host root.
  void _fixRelativeUrls(dom.Element element, String baseUrl) {
    try {
      final baseUri = Uri.parse(baseUrl);

      // Fix image src attributes
      final images = element.querySelectorAll('img[src]');
      for (final img in images) {
        final src = img.attributes['src'];
        if (src != null && !src.startsWith('http') && !src.startsWith('data:')) {
          img.attributes['src'] = baseUri.resolve(src).toString();
        }
      }

      // Fix link href attributes
      final links = element.querySelectorAll('a[href]');
      for (final link in links) {
        final href = link.attributes['href'];
        if (href != null &&
            !href.startsWith('http') &&
            !href.startsWith('mailto:') &&
            !href.startsWith('#')) {
          link.attributes['href'] = baseUri.resolve(href).toString();
        }
      }
    } catch (e) {
      print('Error fixing relative URLs: $e');
    }
  }

  /// Cleans HTML element by removing unwanted attributes and elements
  void _cleanHtmlElement(dom.Element element) {
    // Remove unwanted attributes
    final unwantedAttributes = [
      'class', 'id', 'style', 'onclick', 'onload', 'onerror',
      'data-', 'aria-', 'role', 'tabindex', 'contenteditable',
    ];
    
    final allElements = element.querySelectorAll('*');
    allElements.add(element);
    
    for (final el in allElements) {
      final attributesToRemove = <String>[];
      
      for (final attr in el.attributes.keys) {
        final attrStr = attr.toString();
        if (unwantedAttributes.any((unwanted) => 
            attrStr.toLowerCase().startsWith(unwanted.toLowerCase()))) {
          attributesToRemove.add(attrStr);
        }
      }
      
      for (final attr in attributesToRemove) {
        el.attributes.remove(attr);
      }
      
      // Remove empty paragraphs and divs (but preserve figure/img containers)
      if ((el.localName == 'p' || el.localName == 'div') && 
          el.text.trim().isEmpty && 
          el.children.isEmpty &&
          el.querySelector('img, video, audio, picture, figure') == null) {
        el.remove();
      }
    }
  }

  /// Scores an element based on content quality indicators
  double _scoreElement(dom.Element element) {
    double score = 0;
    final text = element.text;
    
    // Score based on text length
    score += text.length * 0.01;
    
    // Score based on paragraph count
    final paragraphs = element.querySelectorAll('p');
    score += paragraphs.length * 3;
    
    // Score for having actual content paragraphs
    for (final p in paragraphs) {
      if (p.text.trim().length > 50) {
        score += 5;
      }
    }

    // Comma-based scoring (mimicking Readability.js) — commas indicate
    // natural language prose rather than navigation or UI text.
    final commaCount = ','.allMatches(text).length;
    score += commaCount * 1.5;
    
    // Bonus for article-like class names
    final className = element.className.toLowerCase();
    final idName = element.id.toLowerCase();
    final matchString = '$className $idName';

    if (_positivePattern.hasMatch(matchString)) {
      score += 15;
    }
    
    // Penalty for advertisement-like class names
    if (_negativePattern.hasMatch(matchString)) {
      score -= 25;
    }

    // Blockquote bonus — quotes suggest real editorial content.
    final blockquotes = element.querySelectorAll('blockquote');
    score += blockquotes.length * 3;

    // Figure bonus — figures with captions indicate curated content.
    final figures = element.querySelectorAll('figure');
    score += figures.length * 2;
    
    // Penalty for too many links relative to text
    final links = element.querySelectorAll('a');
    if (links.isNotEmpty) {
      final linkTextLength = links.fold(0, (sum, link) => sum + link.text.length);
      if (text.isNotEmpty) {
        final linkRatio = linkTextLength / text.length;
        if (linkRatio > 0.3) {
          score -= 10;
        }
      }
    }

    // Penalty for excessive child divs (wrapper-heavy structures).
    final childDivs = element.children.where((c) => c.localName == 'div').length;
    if (childDivs > 5 && paragraphs.isEmpty) {
      score -= 8; // Many divs, no paragraphs — probably not article content.
    }
    
    return score;
  }
}
