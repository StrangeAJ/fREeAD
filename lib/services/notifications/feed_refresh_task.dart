import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../models/article.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_logger.dart';
import '../database_service.dart';
import '../rss/rss_service.dart';
import 'notification_content.dart';
import 'notification_service.dart';

/// WorkManager entry point (must stay top-level; see `main.dart`).
@pragma('vm:entry-point')
void feedRefreshDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runFeedRefreshTask();
      return Future.value(true);
    } catch (e, st) {
      AppLog.e('Background feed refresh failed', e, st);
      // false -> WorkManager retries with exponential backoff.
      return Future.value(false);
    }
  });
}

/// One background run: refresh every active feed, then notify about what is
/// actually new (unless quiet hours are on).
///
/// Reads settings straight from SharedPreferences so it works in the
/// background isolate without the widget tree. Injected [database]/[rss]/
/// [prefsOverride]/[notifications] exist for tests.
Future<void> runFeedRefreshTask({
  DatabaseService? database,
  RssService? rss,
  SharedPreferences? prefsOverride,
  NotificationService? notifications,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = prefsOverride ?? await SharedPreferences.getInstance();
  if (prefs.getBool(SettingsProvider.notificationsEnabledKey) != true) {
    return;
  }

  final db = database ?? DatabaseService();
  final rssService = rss ?? RssService();
  final startedAt = DateTime.now();

  final feeds = await db.getAllFeeds();
  final feedTitles = <String, String>{
    for (final feed in feeds) feed.id: feed.title,
  };
  for (final feed in feeds.where((f) => f.isActive)) {
    try {
      final fetched = await rssService.fetchFeedArticles(
        feed.url,
        feed.id,
        categoryId: feed.categoryId,
      );
      await db.insertArticlesBatch(fetched);
      await db.updateFeedStatus(
        feed.id,
        lastFetchedAt: DateTime.now(),
        clearError: true,
      );
    } catch (e) {
      AppLog.w('Background refresh failed for ${feed.title}', e);
      try {
        await db.updateFeedStatus(feed.id, lastError: _short(e));
      } catch (_) {
        // Status is best effort.
      }
    }
  }
  await prefs.setString(
    SettingsProvider.lastRefreshAtKey,
    DateTime.now().toIso8601String(),
  );

  // The refresh above still runs during quiet hours; only the alert is
  // suppressed so the morning list is complete.
  final quiet = isQuietNow(
    enabled: prefs.getBool(SettingsProvider.quietHoursEnabledKey) ?? false,
    startMinutes:
        prefs.getInt(SettingsProvider.quietHoursStartKey) ??
        SettingsProvider.defaultQuietStartMinutes,
    endMinutes:
        prefs.getInt(SettingsProvider.quietHoursEndKey) ??
        SettingsProvider.defaultQuietEndMinutes,
  );
  if (quiet) return;

  final muted =
      prefs.getStringList(SettingsProvider.mutedNotificationFeedsKey)?.toSet() ??
      <String>{};
  final fresh = await db.getArticlesAddedSince(startedAt, limit: 50);
  final items = selectNotificationItems(
    articles: fresh,
    feedTitles: feedTitles,
    mutedFeedIds: muted,
  );
  final digest = buildNewArticlesDigest(items);
  if (digest == null) return;

  final service = notifications ?? NotificationService();
  try {
    await service.initForBackground();
    await service.ensureChannel(
      sound: prefs.getBool(SettingsProvider.notificationSoundKey) ?? true,
      vibrate: prefs.getBool(SettingsProvider.notificationVibrateKey) ?? true,
    );
    await service.showDigest(
      digest,
      sound: prefs.getBool(SettingsProvider.notificationSoundKey) ?? true,
      vibrate:
          prefs.getBool(SettingsProvider.notificationVibrateKey) ?? true,
    );
  } catch (e, st) {
    AppLog.e('Could not show new-articles notification', e, st);
  } finally {
    rssService.dispose();
  }
}

/// Picks the notifiable subset of freshly stored articles: drops muted feeds
/// and caps the list so a huge refresh cannot spam.
///
/// Pure (no I/O) for unit tests.
List<DigestItem> selectNotificationItems({
  required List<Article> articles,
  required Map<String, String> feedTitles,
  required Set<String> mutedFeedIds,
  int limit = 20,
}) {
  final items = <DigestItem>[];
  for (final article in articles) {
    if (mutedFeedIds.contains(article.feedId)) continue;
    items.add(
      DigestItem(
        articleId: article.id,
        title: article.title,
        feedTitle: feedTitles[article.feedId] ?? 'FreeAd',
        excerpt: article.description,
      ),
    );
    if (items.length >= limit) break;
  }
  return items;
}

String _short(Object error) {
  final text = error.toString().replaceAll('Exception: ', '');
  final firstLine = text.split('\n').first.trim();
  return firstLine.length > 160
      ? '${firstLine.substring(0, 157)}...'
      : firstLine;
}
