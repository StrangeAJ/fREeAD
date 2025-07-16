import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class FullArticleService {
  final Dio _dio = Dio();

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
      // Remove unwanted elements
      _removeUnwantedElements(document);
      
      // Try common article selectors first
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

  /// Removes unwanted elements from the document
  void _removeUnwantedElements(dom.Document document) {
    final unwantedSelectors = [
      'script', 'style', 'nav', 'header', 'footer', 'aside',
      '.advertisement', '.ads', '.ad', '.sidebar', '.menu',
      '.comments', '.social', '.share', '.related', '.tags',
      '.navigation', '.breadcrumb', '.pagination', '.toolbar',
      '[class*="ad"]', '[id*="ad"]', '[class*="sidebar"]',
      '[class*="menu"]', '[class*="nav"]', '[class*="header"]',
      '[class*="footer"]', '[class*="comment"]', '[class*="social"]',
      '.widget', '.popup', '.modal', '.overlay', '.banner',
    ];

    for (final selector in unwantedSelectors) {
      try {
        final elements = document.querySelectorAll(selector);
        for (final element in elements) {
          element.remove();
        }
      } catch (e) {
        // Continue if selector fails
      }
    }
  }

  /// Tries common article content selectors and returns the element
  dom.Element? _tryCommonSelectorsElement(dom.Document document) {
    final commonSelectors = [
      'article',
      '.article-content',
      '.post-content',
      '.entry-content',
      '.content',
      '.main-content',
      '.article-body',
      '.post-body',
      '.story-body',
      '.text',
      '.article-text',
      '[role="main"]',
      'main',
      '#content',
      '#main',
      '.container .content',
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
      
      // Remove empty paragraphs and divs
      if ((el.localName == 'p' || el.localName == 'div') && 
          el.text.trim().isEmpty && el.children.isEmpty) {
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
    
    // Bonus for article-like class names
    final className = element.className.toLowerCase();
    if (className.contains('article') || className.contains('content') || 
        className.contains('post') || className.contains('story')) {
      score += 10;
    }
    
    // Penalty for advertisement-like class names
    if (className.contains('ad') || className.contains('sidebar') || 
        className.contains('menu') || className.contains('nav')) {
      score -= 20;
    }
    
    // Penalty for too many links relative to text
    final links = element.querySelectorAll('a');
    if (links.length > 0) {
      final linkTextLength = links.fold(0, (sum, link) => sum + link.text.length);
      final linkRatio = linkTextLength / text.length;
      if (linkRatio > 0.3) {
        score -= 10;
      }
    }
    
    return score;
  }
}
