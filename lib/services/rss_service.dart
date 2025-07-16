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

  /// Parse RSS item to Article
  Article? _parseRSSItem(XmlElement item, String feedId) {
    try {
      final title = _getElementText(item, 'title');
      final description = _getElementText(item, 'description') ?? 
                         _getElementText(item, 'summary') ?? '';
      final link = _getElementText(item, 'link');
      final author = _getElementText(item, 'author') ?? 
                    _getElementText(item, 'dc:creator') ?? 'Unknown';
      final pubDateString = _getElementText(item, 'pubDate');
      final pubDate = _parseDate(pubDateString) ?? DateTime.now();
      final content = _getElementText(item, 'content:encoded') ?? description;
      final imageUrl = _getArticleImageUrl(item, content);

      print('Parsing RSS item:');
      print('  Title: $title');
      print('  Link: $link');
      print('  PubDate string: $pubDateString');
      print('  PubDate parsed: $pubDate');

      // Only require title and link, provide defaults for others
      if (title == null || title.isEmpty) {
        print('  Skipping item - missing title');
        return null;
      }
      
      if (link == null || link.isEmpty) {
        print('  Skipping item - missing link');
        return null;
      }

      return Article(
        id: _generateArticleId(link),
        title: _cleanText(title),
        description: _cleanText(description),
        content: _cleanText(content),
        url: link,
        feedId: feedId,
        publishedDate: pubDate,
        author: author,
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
      final linkElement = entry.findElements('link').first;
      final link = linkElement.getAttribute('href');
      final author = _getElementText(entry, 'author');
      final updated = _parseDate(_getElementText(entry, 'updated'));
      final imageUrl = _getArticleImageUrl(entry, content);

      if (title == null || link == null || updated == null) {
        return null;
      }

      return Article(
        id: _generateArticleId(link),
        title: _cleanText(title),
        description: _cleanText(summary ?? ''),
        content: _cleanText(content),
        imageUrl: imageUrl,
        url: link,
        author: author,
        publishedDate: updated,
        feedId: feedId,
        dateAdded: DateTime.now(),
      );
    } catch (e) {
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
      // Try media:content
      final mediaContent = item.findElements('media:content').isNotEmpty
          ? item.findElements('media:content').first
          : null;
      
      if (mediaContent != null) {
        final url = mediaContent.getAttribute('url');
        final type = mediaContent.getAttribute('type');
        if (url != null && type != null && type.startsWith('image/')) {
          return url;
        }
      }
      
      // Try enclosure
      final enclosure = item.findElements('enclosure').isNotEmpty
          ? item.findElements('enclosure').first
          : null;
      
      if (enclosure != null) {
        final url = enclosure.getAttribute('url');
        final type = enclosure.getAttribute('type');
        if (url != null && type != null && type.startsWith('image/')) {
          return url;
        }
      }
      
      // Parse HTML content for images
      if (content.isNotEmpty) {
        final document = html_parser.parse(content);
        final img = document.querySelector('img');
        if (img != null) {
          return img.attributes['src'];
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse date string to DateTime
  DateTime? _parseDate(String? dateString) {
    if (dateString == null) return null;
    
    try {
      // Try RFC 822 format (RSS)
      return DateTime.parse(dateString);
    } catch (e) {
      try {
        // Try ISO 8601 format (Atom)
        return DateTime.parse(dateString);
      } catch (e) {
        return null;
      }
    }
  }

  /// Clean text content
  String _cleanText(String text) {
    final document = html_parser.parse(text);
    return document.body?.text ?? text;
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
