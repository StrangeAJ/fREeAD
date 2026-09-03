import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:freead/providers/feed_provider.dart';
import 'package:freead/providers/article_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/screens/feed_management_screen.dart';
import 'package:freead/services/rss/feed_discovery_service.dart';

/// Answers every request with 404 so discovery finds nothing and no test ever
/// touches the network.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('not found', 404);

  @override
  void close({bool force = false}) {}
}

FeedDiscoveryService _offlineDiscovery() {
  final dio = Dio()..httpClientAdapter = _OfflineAdapter();
  return FeedDiscoveryService(dio: dio);
}

void main() {
  group('Feed Management Tests', () {
    late FeedProvider feedProvider;
    late ArticleProvider articleProvider;
    late SettingsProvider settingsProvider;

    setUp(() {
      feedProvider = FeedProvider(discovery: _offlineDiscovery());
      articleProvider = ArticleProvider();
      settingsProvider = SettingsProvider();
    });

    testWidgets('Feed Management Screen loads correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: feedProvider),
            ChangeNotifierProvider.value(value: articleProvider),
            ChangeNotifierProvider.value(value: settingsProvider),
          ],
          child: MaterialApp(home: const FeedManagementScreen()),
        ),
      );

      await tester.pump();
      expect(find.text('Manage Feeds'), findsOneWidget);
    });

    test('FeedProvider can add feeds', () async {
      final result = await feedProvider.addFeed('https://example.com/rss.xml');
      expect(result, isA<AddFeedResult>());
      // Nothing is reachable in tests, so discovery finds no candidates.
      expect(result.isSuccess, isFalse);
      expect(result.needsSelection, isFalse);
      expect(result.error, isNotNull);
      expect(feedProvider.feeds, isA<List>());
    });

    test('FeedProvider rejects empty input without discovery', () async {
      final result = await feedProvider.addFeed('   ');
      expect(result.hasError, isTrue);
      expect(result.feed, isNull);
    });

    test('FeedProvider exposes categories and unread counts', () async {
      await feedProvider.loadFeeds();
      expect(feedProvider.categories, isA<List>());
      expect(feedProvider.totalUnread, isA<int>());
      expect(feedProvider.unreadCountFor('missing'), equals(0));
      expect(feedProvider.unreadCountForCategory('general'), equals(0));
      expect(feedProvider.feedsByCategory, isA<Map<String, List<dynamic>>>());
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
