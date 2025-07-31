import 'dart:async';
import '../services/rss_service.dart';
import '../models/article.dart';
import '../services/full_article_service.dart';
import '../services/enhanced_article_service.dart';
import '../models/rss_feed.dart';

/// Top-level function to parse RSS feed in isolate
FutureOr<List<Article>> parseRSSFeedIsolate(Map<String, String> params) async {
  final service = RSSService();
  return await service.parseRSSFeed(params['url']!, params['feedId']!);
}

/// Top-level function to fetch full article content in isolate
FutureOr<String?> fetchFullArticleContentIsolate(String url) async {
  final service = FullArticleService();
  return await service.fetchFullArticleContent(url);
}

/// Top-level function to extract enhanced article content in isolate
FutureOr<Map<String, dynamic>?> extractEnhancedArticleContentIsolate(String url) async {
  final service = EnhancedArticleService();
  return await service.extractArticleContent(url);
}

/// Top-level function to fetch feed info in isolate
FutureOr<RSSFeed> fetchFeedInfoIsolate(String url) async {
  final service = RSSService();
  return await service.fetchFeedInfo(url);
}
