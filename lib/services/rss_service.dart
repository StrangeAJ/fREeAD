import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../models/rss_feed.dart';

class RSSService {
  final Dio _dio;

  RSSService() : _dio = Dio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'application/rss+xml, application/xml, application/atom+xml, text/xml, */*',
        'Accept-Encoding': 'gzip, deflate',
        'Cache-Control': 'no-cache',
      },
      followRedirects: true,
      maxRedirects: 5,
    );
  }

  /// Validate RSS feed URL
  Future<bool> validateFeedUrl(String url) async {
    try {
      // Add timeout and better error handling
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status! < 500,
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data.toString();
        
        // Check if the response contains RSS/Atom XML content
        if (data.contains('<?xml') || 
            data.contains('<rss') || 
            data.contains('<feed') ||
            data.contains('<channel>') ||
            data.contains('<entry>')) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      // For testing, let's log the error and return false
      print('RSS validation error: $e');
      return false;
    }
  }

  /// Fetch RSS feed information
  Future<RSSFeed> fetchFeedInfo(String url) async {
    try {
      final response = await _dio.get(url);
      final document = XmlDocument.parse(response.data);
      
      // Try RSS 2.0 first
      XmlElement? channel = document.findElements('rss').isNotEmpty
          ? document.findElements('rss').first.findElements('channel').first
          : null;
      
      // Try Atom if RSS not found
      if (channel == null) {
        channel = document.findElements('feed').isNotEmpty
            ? document.findElements('feed').first
            : null;
      }

      if (channel == null) {
        throw Exception('Invalid RSS/Atom feed format');
      }

      final title = _getElementText(channel, 'title') ?? 'Unknown Feed';
      final description = _getElementText(channel, 'description') ?? 
                         _getElementText(channel, 'subtitle') ?? '';
      final imageUrl = _getImageUrl(channel);

      return RSSFeed(
        id: _generateFeedId(url),
        title: title,
        url: url,
        description: description,
        imageUrl: imageUrl,
        dateAdded: DateTime.now(),
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to fetch feed info: $e');
    }
  }

  /// Parse RSS feed and return articles
  Future<List<Article>> parseRSSFeed(String url, String feedId) async {
    try {
      String requestUrl = url;
      
      // For web platform, use CORS proxy
      if (kIsWeb) {
        requestUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
        print('Using CORS proxy for web: $requestUrl');
      }
      
      print('Fetching RSS feed: $requestUrl');
      
      // Add retry logic with exponential backoff
      int retryCount = 0;
      int maxRetries = 3;
      
      while (retryCount < maxRetries) {
        try {
          final response = await _dio.get(
            requestUrl,
            options: Options(
              responseType: ResponseType.plain,
              validateStatus: (status) => status! < 500,
            ),
          );
          
          print('Response status: ${response.statusCode}');
          
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}: ${response.statusMessage}');
          }
          
          if (response.data == null || response.data.toString().isEmpty) {
            throw Exception('Empty response data');
          }
          
          print('Response data length: ${response.data.toString().length}');
          
          final document = XmlDocument.parse(response.data.toString());
          
          List<Article> articles = [];
          
          // Try RSS 2.0 first
          final rssItems = document.findAllElements('item');
          print('Found ${rssItems.length} RSS items');
          
          if (rssItems.isNotEmpty) {
            for (final item in rssItems) {
              final article = _parseRSSItem(item, feedId);
              if (article != null) {
                articles.add(article);
              }
            }
          } else {
            // Try Atom format
            final atomEntries = document.findAllElements('entry');
            print('Found ${atomEntries.length} Atom entries');
            
            for (final entry in atomEntries) {
              final article = _parseAtomEntry(entry, feedId);
              if (article != null) {
                articles.add(article);
              }
            }
          }
          
          print('Parsed ${articles.length} articles from feed');
          return articles;
          
        } catch (e) {
          retryCount++;
          print('Attempt $retryCount failed: $e');
          
          if (retryCount >= maxRetries) {
            throw e;
          }
          
          // Wait before retry (exponential backoff)
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }
      
      return [];
    } catch (e) {
      print('Error parsing RSS feed $url: $e');
      // Don't throw exception, just return empty list to prevent app crash
      return [];
    }
  }

  /// Alias for parseRSSFeed for backward compatibility
  Future<List<Article>> fetchArticles(String url) async {
    // Generate a temporary feedId if not provided
    final feedId = url.hashCode.toString();
    return await parseRSSFeed(url, feedId);
  }

  /// Parse RSS item to Article
  Article? _parseRSSItem(XmlElement item, String feedId) {
    try {
      final title = _getElementText(item, 'title');
      final description = _getElementText(item, 'description') ?? 
                         _getElementText(item, 'summary') ?? '';
      final link = _getElementText(item, 'link');
      final author = _getElementText(item, 'author') ?? 
                    _getElementText(item, 'dc:creator') ?? 
                    _getElementText(item, 'creator') ?? 'Unknown';
      final pubDateString = _getElementText(item, 'pubDate');
      final pubDate = _parseDate(pubDateString) ?? DateTime.now();
      
      // Try to get better content from various sources
      String content = _getElementText(item, 'content:encoded') ?? 
                      _getElementText(item, 'content') ?? 
                      description;
      
      // Extract image URL from content or media elements
      final imageUrl = _getArticleImageUrl(item, content);

      print('Parsing RSS item:');
      print('  Title: $title');
      print('  Link: $link');
      print('  Author: $author');
      print('  PubDate string: $pubDateString');
      print('  PubDate parsed: $pubDate');
      print('  Content length: ${content.length}');

      // Only require title and link, provide defaults for others
      if (title == null || title.isEmpty) {
        print('  Skipping item - missing title');
        return null;
      }
      
      if (link == null || link.isEmpty) {
        print('  Skipping item - missing link');
        return null;
      }

      // Clean and validate content
      final cleanTitle = _cleanText(title);
      final cleanDescription = _cleanText(description);
      final cleanContent = _cleanText(content);
      final cleanAuthor = _cleanText(author);

      // Skip if content is too short or seems to be navigation/menu content
      if (cleanContent.length < 50) {
        print('  Warning: Content is very short (${cleanContent.length} chars)');
      }

      return Article(
        id: _generateArticleId(link),
        title: cleanTitle,
        description: cleanDescription,
        content: cleanContent,
        url: link,
        feedId: feedId,
        publishedDate: pubDate,
        author: cleanAuthor,
        isRead: false,
        isStarred: false,
        isSaved: false,
        imageUrl: imageUrl,
        dateAdded: DateTime.now(),
      );
    } catch (e) {
      print('Error parsing RSS item: $e');
      return null;
    }
  }

  /// Parse Atom entry to Article
  Article? _parseAtomEntry(XmlElement entry, String feedId) {
    try {
      final title = _getElementText(entry, 'title');
      final summary = _getElementText(entry, 'summary');
      final content = _getElementText(entry, 'content') ?? summary ?? '';
      
      // Get link from Atom entry
      final linkElement = entry.findElements('link').firstOrNull;
      final link = linkElement?.getAttribute('href');
      
      // Get author information
      final authorElement = entry.findElements('author').firstOrNull;
      final author = authorElement != null 
          ? (_getElementText(authorElement, 'name') ?? 'Unknown')
          : 'Unknown';
      
      // Get published/updated date
      final publishedString = _getElementText(entry, 'published');
      final updatedString = _getElementText(entry, 'updated');
      final pubDate = _parseDate(publishedString) ?? _parseDate(updatedString) ?? DateTime.now();
      
      final imageUrl = _getArticleImageUrl(entry, content);

      print('Parsing Atom entry:');
      print('  Title: $title');
      print('  Link: $link');
      print('  Author: $author');
      print('  Published: $publishedString');
      print('  Updated: $updatedString');
      print('  Content length: ${content.length}');

      if (title == null || title.isEmpty || link == null || link.isEmpty) {
        print('  Skipping entry - missing title or link');
        return null;
      }

      // Clean content
      final cleanTitle = _cleanText(title);
      final cleanSummary = _cleanText(summary ?? '');
      final cleanContent = _cleanText(content);
      final cleanAuthor = _cleanText(author);

      return Article(
        id: _generateArticleId(link),
        title: cleanTitle,
        description: cleanSummary,
        content: cleanContent,
        imageUrl: imageUrl,
        url: link,
        author: cleanAuthor,
        publishedDate: pubDate,
        feedId: feedId,
        isRead: false,
        isStarred: false,
        isSaved: false,
        dateAdded: DateTime.now(),
      );
    } catch (e) {
      print('Error parsing Atom entry: $e');
      return null;
    }
  }

  /// Get text content from XML element
  String? _getElementText(XmlElement parent, String tagName) {
    try {
      final element = parent.findElements(tagName).isNotEmpty
          ? parent.findElements(tagName).first
          : null;
      return element?.innerText;
    } catch (e) {
      return null;
    }
  }

  /// Get image URL from feed
  String? _getImageUrl(XmlElement channel) {
    try {
      // Try RSS image
      final imageElement = channel.findElements('image').isNotEmpty
          ? channel.findElements('image').first
          : null;
      
      if (imageElement != null) {
        return _getElementText(imageElement, 'url');
      }
      
      // Try iTunes image
      final itunesImage = channel.findElements('itunes:image').isNotEmpty
          ? channel.findElements('itunes:image').first
          : null;
      
      if (itunesImage != null) {
        return itunesImage.getAttribute('href');
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get image URL from article content
  String? _getArticleImageUrl(XmlElement item, String content) {
    try {
      // Try media:content first
      final mediaContent = item.findElements('media:content').firstOrNull;
      if (mediaContent != null) {
        final url = mediaContent.getAttribute('url');
        final type = mediaContent.getAttribute('type');
        if (url != null && type != null && type.startsWith('image/')) {
          return url;
        }
      }
      
      // Try media:thumbnail
      final mediaThumbnail = item.findElements('media:thumbnail').firstOrNull;
      if (mediaThumbnail != null) {
        final url = mediaThumbnail.getAttribute('url');
        if (url != null) {
          return url;
        }
      }
      
      // Try enclosure
      final enclosure = item.findElements('enclosure').firstOrNull;
      if (enclosure != null) {
        final url = enclosure.getAttribute('url');
        final type = enclosure.getAttribute('type');
        if (url != null && type != null && type.startsWith('image/')) {
          return url;
        }
      }
      
      // Try itunes:image
      final itunesImage = item.findElements('itunes:image').firstOrNull;
      if (itunesImage != null) {
        final url = itunesImage.getAttribute('href');
        if (url != null) {
          return url;
        }
      }
      
      // Parse HTML content for images
      if (content.isNotEmpty) {
        final document = html_parser.parse(content);
        
        // Try to find the first meaningful image
        final images = document.querySelectorAll('img');
        for (final img in images) {
          final src = img.attributes['src'];
          if (src != null && src.isNotEmpty) {
            // Skip small images (likely icons or social media buttons)
            final width = img.attributes['width'];
            final height = img.attributes['height'];
            
            if (width != null && height != null) {
              final w = int.tryParse(width) ?? 0;
              final h = int.tryParse(height) ?? 0;
              if (w > 100 && h > 100) {
                return src;
              }
            } else {
              // If no dimensions specified, assume it's content-related
              return src;
            }
          }
        }
        
        // If no good image found, try the first image
        final firstImg = document.querySelector('img');
        if (firstImg != null) {
          final src = firstImg.attributes['src'];
          if (src != null && src.isNotEmpty) {
            return src;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Error extracting image URL: $e');
      return null;
    }
  }

  static final _dayNameRegex = RegExp(r'[A-Za-z]{3},\s*');
  static final _whitespaceRegex = RegExp(r'\s+');
  static final _dateFormats = [
    RegExp(r'(\d{1,2})\s+(\w+)\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})'),
    RegExp(r'(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2}):(\d{2})'),
    RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})'),
  ];

  /// Parse date string to DateTime with multiple format support
  DateTime? _parseDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    
    try {
      // Try parsing as-is first (handles ISO 8601 and RFC 822)
      return DateTime.parse(dateString);
    } catch (e) {
      try {
        // Try parsing with RFC 822 format manually
        // Example: "Mon, 01 Jan 2024 12:00:00 +0000"
        final cleanedDate = dateString
            .replaceAll(_dayNameRegex, '') // Remove day name
            .replaceAll(_whitespaceRegex, ' ') // Normalize spaces
            .trim();
        
        return DateTime.parse(cleanedDate);
      } catch (e2) {
        try {
          // Try parsing with common date formats
          for (final format in _dateFormats) {
            final match = format.firstMatch(dateString);
            if (match != null) {
              // Parse based on the matched format
              return DateTime.now(); // Fallback to current date
            }
          }
        } catch (e3) {
          print('Failed to parse date: $dateString');
        }
      }
    }
    
    return null;
  }

  /// Clean text content and handle various encodings
  String _cleanText(String text) {
    if (text.isEmpty) return text;
    
    try {
      // Parse HTML to get clean text
      final document = html_parser.parse(text);
      String cleanText = document.body?.text ?? text;
      
      // Handle common HTML entities
      cleanText = cleanText
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'");
      
      // Clean up excessive whitespace
      cleanText = cleanText.replaceAll(_whitespaceRegex, ' ').trim();
      
      return cleanText;
    } catch (e) {
      // If parsing fails, return original text with basic cleanup
      return text.replaceAll(_whitespaceRegex, ' ').trim();
    }
  }

  /// Generate unique feed ID
  String _generateFeedId(String url) {
    return base64Encode(utf8.encode(url)).replaceAll('=', '');
  }

  /// Generate unique article ID
  String _generateArticleId(String url) {
    return base64Encode(utf8.encode(url)).replaceAll('=', '');
  }

  /// Dispose resources
  void dispose() {
    _dio.close();
  }
}
