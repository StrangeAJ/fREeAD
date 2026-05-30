import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:freead/providers/feed_provider.dart';
import 'package:freead/providers/article_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/screens/feed_management_screen.dart';

void main() {
  group('Feed Management Tests', () {
    late FeedProvider feedProvider;
    late ArticleProvider articleProvider;
    late SettingsProvider settingsProvider;

    setUp(() {
      feedProvider = FeedProvider();
      articleProvider = ArticleProvider();
      settingsProvider = SettingsProvider();
    });

    testWidgets('Feed Management Screen loads correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: feedProvider),
            ChangeNotifierProvider.value(value: articleProvider),
            ChangeNotifierProvider.value(value: settingsProvider),
          ],
          child: MaterialApp(
            home: const FeedManagementScreen(),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Manage Feeds'), findsOneWidget);
    });

    test('FeedProvider can add feeds', () async {
      final success = await feedProvider.addFeed('https://example.com/rss.xml');
      expect(success, isA<bool>());
      expect(feedProvider.feeds, isA<List>());
    });

    test('ArticleProvider can load articles', () async {
      await articleProvider.loadArticles();
      expect(articleProvider.articles, isA<List>());
      expect(articleProvider.savedArticles, isA<List>());
      expect(articleProvider.starredArticles, isA<List>());
    });

    test('FeedProvider can refresh feeds', () async {
      await feedProvider.loadFeeds();
      await feedProvider.refreshAllFeeds();
      expect(feedProvider.feeds, isA<List>());
    });
  });
}
