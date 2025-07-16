import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/rss_service.dart';

void main() {
  group('RSS Service Tests', () {
    late RSSService rssService;

    setUp(() {
      rssService = RSSService();
    });

    test('Parse RSS feed from BBC', () async {
      try {
        final articles = await rssService.parseRSSFeed(
          'https://feeds.bbci.co.uk/news/rss.xml',
          'test_feed_id',
        );
        
        print('Parsed ${articles.length} articles');
        
        if (articles.isNotEmpty) {
          final article = articles.first;
          print('First article:');
          print('  Title: ${article.title}');
          print('  Description: ${article.description}');
          print('  URL: ${article.url}');
          print('  Author: ${article.author}');
          print('  Published: ${article.publishedDate}');
        }
        
        expect(articles.length, greaterThan(0));
      } catch (e) {
        print('Error parsing RSS feed: $e');
        fail('RSS parsing failed: $e');
      }
    });

    test('Parse RSS feed from CNN', () async {
      try {
        final articles = await rssService.parseRSSFeed(
          'https://rss.cnn.com/rss/edition.rss',
          'test_feed_id',
        );
        
        print('Parsed ${articles.length} articles');
        
        if (articles.isNotEmpty) {
          final article = articles.first;
          print('First article:');
          print('  Title: ${article.title}');
          print('  Description: ${article.description}');
          print('  URL: ${article.url}');
          print('  Author: ${article.author}');
          print('  Published: ${article.publishedDate}');
        }
        
        expect(articles.length, greaterThan(0));
      } catch (e) {
        print('Error parsing RSS feed: $e');
        fail('RSS parsing failed: $e');
      }
    });

    test('Parse RSS feed from NPR', () async {
      try {
        final articles = await rssService.parseRSSFeed(
          'https://feeds.npr.org/1001/rss.xml',
          'test_feed_id',
        );
        
        print('Parsed ${articles.length} articles');
        
        if (articles.isNotEmpty) {
          final article = articles.first;
          print('First article:');
          print('  Title: ${article.title}');
          print('  Description: ${article.description}');
          print('  URL: ${article.url}');
          print('  Author: ${article.author}');
          print('  Published: ${article.publishedDate}');
        }
        
        expect(articles.length, greaterThan(0));
      } catch (e) {
        print('Error parsing RSS feed: $e');
        fail('RSS parsing failed: $e');
      }
    });
  });
}
