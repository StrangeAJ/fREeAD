import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import '../models/article.dart';
import '../models/rss_feed.dart';

class RssService {
  final Dio _dio = Dio();

  RssService() {
    _dio.options.followRedirects = true;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  Future<List<Article>> parseRSSFeed(String url, String feedId) async {
    return fetchFeedArticles(url, feedId);
  }

  Future<RSSFeed> fetchFeedInfo(String url) async {
    final response = await _dio.get(url);
    final document = XmlDocument.parse(response.data.toString());
    final channel = document.findAllElements('channel').first;

    return RSSFeed(
      id: base64Encode(utf8.encode(url)).replaceAll('=', ''),
      title: channel.findElements('title').first.innerText,
      url: url,
      description: channel.findElements('description').first.innerText,
      dateAdded: DateTime.now(),
    );
  }

  Future<List<Article>> fetchFeedArticles(String url, String feedId) async {
    try {
      print('Fetching feed: $url');
      final response = await _dio.get(url);
      final document = XmlDocument.parse(response.data.toString());

      final rssElement = document.findElements('rss').firstOrNull;
      final atomElement = document.findElements('feed').firstOrNull;

      if (rssElement != null) {
        return _parseRss(document, feedId);
      } else if (atomElement != null) {
        return _parseAtom(document, feedId);
      } else {
        throw Exception('Unsupported feed format');
      }
    } catch (e) {
      print('Error fetching feed $url: $e');
      rethrow;
    }
  }

  List<Article> _parseRss(XmlDocument document, String feedId) {
    final items = document.findAllElements('item');
    return items
        .map((item) => _parseRssItem(item, feedId))
        .whereType<Article>()
        .toList();
  }

  List<Article> _parseAtom(XmlDocument document, String feedId) {
    final entries = document.findAllElements('entry');
    return entries
        .map((entry) => _parseAtomEntry(entry, feedId))
        .whereType<Article>()
        .toList();
  }

  Article? _parseRssItem(XmlElement item, String feedId) {
    try {
      final title = _getElementText(item, 'title');
      final link = _getElementText(item, 'link') ?? _getElementText(item, 'guid');
      final description = _getElementText(item, 'description') ?? '';
      final content = _getElementText(item, 'content:encoded') ?? description;
      final author = _getElementText(item, 'dc:creator') ?? _getElementText(item, 'author') ?? 'Unknown';
      final pubDateString = _getElementText(item, 'pubDate');
      final pubDate = _parseDate(pubDateString) ?? DateTime.now();
      final imageUrl = _getArticleImageUrl(item, content);

      if (title == null || title.isEmpty || link == null || link.isEmpty) {
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
        author: _cleanText(author),
        isRead: false,
        isStarred: false,
        isSaved: false,
        imageUrl: imageUrl,
        dateAdded: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  Article? _parseAtomEntry(XmlElement entry, String feedId) {
    try {
      final title = _getElementText(entry, 'title');
      final summary = _getElementText(entry, 'summary');
      final content = _getElementText(entry, 'content') ?? summary ?? '';
      
      final linkElement = entry.findElements('link').firstWhere(
        (e) => e.getAttribute('rel') == 'alternate' || e.getAttribute('rel') == null,
        orElse: () => entry.findElements('link').first,
      );
      final link = linkElement.getAttribute('href');
      
      final authorElement = entry.findElements('author').firstOrNull;
      final author = authorElement != null 
          ? (_getElementText(authorElement, 'name') ?? 'Unknown')
          : 'Unknown';
      
      final publishedString = _getElementText(entry, 'published') ?? _getElementText(entry, 'updated');
      final pubDate = _parseDate(publishedString) ?? DateTime.now();
      
      final imageUrl = _getArticleImageUrl(entry, content);

      if (title == null || title.isEmpty || link == null || link.isEmpty) {
        return null;
      }

      return Article(
        id: _generateArticleId(link),
        title: _cleanText(title),
        description: _cleanText(summary ?? ''),
        content: _cleanText(content),
        imageUrl: imageUrl,
        url: link,
        author: _cleanText(author),
        publishedDate: pubDate,
        feedId: feedId,
        isRead: false,
        isStarred: false,
        isSaved: false,
        dateAdded: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  String? _getElementText(XmlElement parent, String tagName) {
    try {
      final elements = parent.findElements(tagName);
      if (elements.isEmpty) return null;
      return elements.first.innerText;
    } catch (e) {
      return null;
    }
  }

  String? _getArticleImageUrl(XmlElement item, String content) {
    try {
      final mediaContent = item.findElements('media:content').firstOrNull;
      if (mediaContent != null) {
        final url = mediaContent.getAttribute('url');
        if (url != null) return url;
      }
      final enclosure = item.findElements('enclosure').firstOrNull;
      if (enclosure != null) {
        final url = enclosure.getAttribute('url');
        final type = enclosure.getAttribute('type');
        if (url != null && (type == null || type.startsWith('image/'))) {
          return url;
        }
      }
      if (content.isNotEmpty) {
        final document = html_parser.parse(content);
        final img = document.querySelector('img');
        if (img != null) {
          final src = img.attributes['src'];
          if (src != null && src.isNotEmpty && src.startsWith('http')) {
            return src;
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  DateTime? _parseDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      return DateTime.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  String _cleanText(String text) {
    if (text.isEmpty) return text;
    try {
      final document = html_parser.parse(text);
      String cleanText = document.body?.text ?? text;
      cleanText = cleanText
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'");
      return cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (e) {
      return text.trim();
    }
  }

  String _generateArticleId(String url) {
    return base64Encode(utf8.encode(url)).replaceAll('=', '');
  }

  void dispose() {
    _dio.close();
  }
}

class RSSService extends RssService {}
