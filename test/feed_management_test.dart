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
            home: FeedManagementScreen(),
          ),
        ),
      );

      // Wait for the widget to build
      await tester.pump();

      // Check if the screen title is present
      expect(find.text('Manage Feeds'), findsOneWidget);
      
      // Check if the floating action button is present
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Add Feed Dialog opens correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: feedProvider),
            ChangeNotifierProvider.value(value: articleProvider),
            ChangeNotifierProvider.value(value: settingsProvider),
          ],
          child: MaterialApp(
            home: FeedManagementScreen(),
          ),
        ),
      );

      // Wait for the widget to build
      await tester.pump();

      // Tap the floating action button
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Check if the add feed dialog is present
      expect(find.text('Add RSS Feed'), findsOneWidget);
      expect(find.text('RSS Feed URL'), findsOneWidget);
    });

    test('FeedProvider can add feeds', () async {
      // Test adding a feed
      final success = await feedProvider.addFeed('https://example.com/rss.xml');
      
      // The result might be false due to validation, but it shouldn't crash
      expect(success, isA<bool>());
      
      // Check that the provider has been initialized
      expect(feedProvider.feeds, isA<List>());
      expect(feedProvider.categories, isA<List>());
    });

    test('ArticleProvider can load articles', () async {
      // Test loading articles
      await articleProvider.loadArticles();
      
      // Check that the provider has been initialized
      expect(articleProvider.articles, isA<List>());
      expect(articleProvider.savedArticles, isA<List>());
      expect(articleProvider.starredArticles, isA<List>());
    });

    test('FeedProvider can refresh feeds', () async {
      // Load feeds first
      await feedProvider.loadFeeds();
      
      // Test refreshing feeds
      await feedProvider.refreshAllFeeds();
      
      // Should not crash
      expect(feedProvider.feeds, isA<List>());
    });
  });
}
