import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/rss_feed.dart';
import 'package:freead/models/category.dart';
import 'package:freead/models/article.dart';

void main() {
  group('Database Model Tests', () {
    test('RSSFeed toJson/fromJson handles booleans correctly', () {
      final feed = RSSFeed(
        id: 'test-1',
        title: 'Test Feed',
        url: 'https://example.com/feed.xml',
        description: 'Test Description',
        isActive: true,
        dateAdded: DateTime.now(),
      );

      final json = feed.toJson();
      expect(json['isActive'], equals(1)); // Should be integer

      final feedFromJson = RSSFeed.fromJson(json);
      expect(feedFromJson.isActive, equals(true)); // Should be boolean
    });

    test('Category toJson/fromJson handles booleans correctly', () {
      final category = Category(
        id: 'test-cat',
        name: 'Test Category',
        description: 'Test Description',
        dateCreated: DateTime.now(),
        isDefault: true,
      );

      final json = category.toJson();
      expect(json['isDefault'], equals(1)); // Should be integer

      final categoryFromJson = Category.fromJson(json);
      expect(categoryFromJson.isDefault, equals(true)); // Should be boolean
    });

    test('Article toJson/fromJson handles booleans correctly', () {
      final article = Article(
        id: 'test-article',
        title: 'Test Article',
        description: 'Test Description',
        url: 'https://example.com/article',
        publishedDate: DateTime.now(),
        feedId: 'test-feed',
        isRead: true,
        isSaved: false,
        isStarred: true,
        dateAdded: DateTime.now(),
      );

      final json = article.toJson();
      expect(json['isRead'], equals(1)); // Should be integer
      expect(json['isSaved'], equals(0)); // Should be integer
      expect(json['isStarred'], equals(1)); // Should be integer

      final articleFromJson = Article.fromJson(json);
      expect(articleFromJson.isRead, equals(true)); // Should be boolean
      expect(articleFromJson.isSaved, equals(false)); // Should be boolean
      expect(articleFromJson.isStarred, equals(true)); // Should be boolean
    });

    test('Article handles fullContent field', () {
      final article = Article(
        id: 'test-article',
        title: 'Test Article',
        description: 'Test Description',
        content: 'Short content',
        fullContent: 'Full article content here',
        url: 'https://example.com/article',
        publishedDate: DateTime.now(),
        feedId: 'test-feed',
        dateAdded: DateTime.now(),
      );

      final json = article.toJson();
      expect(json['fullContent'], equals('Full article content here'));

      final articleFromJson = Article.fromJson(json);
      expect(articleFromJson.fullContent, equals('Full article content here'));
    });
  });
}
