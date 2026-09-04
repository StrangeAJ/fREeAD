import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/article.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/services/notifications/feed_refresh_task.dart';
import 'package:freead/services/notifications/notification_content.dart';
import 'package:freead/services/notifications/notification_payload.dart';
import 'package:freead/services/notifications/refresh_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements RefreshScheduler {
  Duration? lastFrequency;
  int cancels = 0;

  @override
  Future<void> schedulePeriodic({required Duration frequency}) async {
    lastFrequency = frequency;
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
  }
}

Article _article(String id, String feedId, {String title = 'Title'}) =>
    Article(
      id: id,
      title: title,
      description: 'Excerpt.',
      url: 'https://example.com/$id',
      publishedDate: DateTime(2026, 8, 30, 9, 30),
      feedId: feedId,
      dateAdded: DateTime(2026, 8, 30, 10),
    );

Future<SettingsProvider> _settings() async {
  final provider = SettingsProvider();
  await provider.init();
  return provider;
}

void _mockChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async => null,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationPayload', () {
    test('article round trip', () {
      const payload = NotificationPayload.article('abc');
      final restored = NotificationPayload.tryDecode(payload.encode());
      expect(restored, isNotNull);
      expect(restored!.isArticle, isTrue);
      expect(restored.id, 'abc');
    });

    test('feed and home round trips', () {
      final feed = NotificationPayload.tryDecode(
        const NotificationPayload.feed('f1').encode(),
      );
      expect(feed?.isFeed, isTrue);
      expect(feed?.id, 'f1');

      final home = NotificationPayload.tryDecode(
        const NotificationPayload.home().encode(),
      );
      expect(home?.isHome, isTrue);
    });

    test('garbage decodes to null', () {
      expect(NotificationPayload.tryDecode(null), isNull);
      expect(NotificationPayload.tryDecode(''), isNull);
      expect(NotificationPayload.tryDecode('not json'), isNull);
      expect(NotificationPayload.tryDecode('{"kind":"nope"}'), isNull);
      expect(
        NotificationPayload.tryDecode('{"kind":"article"}'),
        isNull,
      );
      expect(NotificationPayload.tryDecode('[]'), isNull);
    });
  });

  group('isQuietNow', () {
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 8, 30, hour, minute);

    test('disabled never quiets', () {
      expect(
        isQuietNow(enabled: false, startMinutes: 22 * 60, endMinutes: 7 * 60),
        isFalse,
      );
    });

    test('daytime window', () {
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 23 * 60,
          now: at(22, 30),
        ),
        isTrue,
      );
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 23 * 60,
          now: at(21, 59),
        ),
        isFalse,
      );
      // End is exclusive.
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 23 * 60,
          now: at(23),
        ),
        isFalse,
      );
    });

    test('overnight window wraps past midnight', () {
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
          now: at(23),
        ),
        isTrue,
      );
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
          now: at(3),
        ),
        isTrue,
      );
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
          now: at(12),
        ),
        isFalse,
      );
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
          now: at(7),
        ),
        isFalse,
      );
    });

    test('start equals end means no quiet hours', () {
      expect(
        isQuietNow(
          enabled: true,
          startMinutes: 60,
          endMinutes: 60,
          now: at(1),
        ),
        isFalse,
      );
    });
  });

  group('day minutes helpers', () {
    test('formatDayMinutes pads correctly', () {
      expect(formatDayMinutes(0), '00:00');
      expect(formatDayMinutes(7 * 60 + 5), '07:05');
      expect(formatDayMinutes(22 * 60), '22:00');
      expect(formatDayMinutes(24 * 60 - 1), '23:59');
    });

    test('clampDayMinutes keeps range', () {
      expect(clampDayMinutes(-5), 0);
      expect(clampDayMinutes(24 * 60 + 99), 24 * 60 - 1);
      expect(clampDayMinutes(512), 512);
    });
  });

  group('buildNewArticlesDigest', () {
    test('empty means no notification', () {
      expect(buildNewArticlesDigest(const <DigestItem>[]), isNull);
    });

    test('single article links back to the reader', () {
      final digest = buildNewArticlesDigest(const <DigestItem>[
        DigestItem(
          articleId: 'a1',
          title: 'Big story',
          feedTitle: 'Example',
          excerpt: 'Something happened.',
        ),
      ])!;
      expect(digest.count, 1);
      expect(digest.title, 'Big story');
      expect(digest.body, contains('Example'));
      expect(digest.articleId, 'a1');
      expect(digest.lines, isEmpty);
    });

    test('many articles become an inbox digest with a cap', () {
      final items = <DigestItem>[
        for (var i = 0; i < 8; i++)
          DigestItem(
            articleId: 'a$i',
            title: 'Story $i',
            feedTitle: 'Feed',
          ),
      ];
      final digest = buildNewArticlesDigest(items, maxLines: 5)!;
      expect(digest.count, 8);
      expect(digest.title, '8 new articles');
      expect(digest.lines, hasLength(5));
      expect(digest.summaryText, '+3 more');
      expect(digest.articleId, isNull);
    });

    test('everything fitting needs no summary line', () {
      final digest = buildNewArticlesDigest(const <DigestItem>[
        DigestItem(articleId: 'a', title: 'One', feedTitle: 'F'),
        DigestItem(articleId: 'b', title: 'Two', feedTitle: 'F'),
      ])!;
      expect(digest.summaryText, isNull);
      expect(digest.lines, hasLength(2));
    });
  });

  group('selectNotificationItems', () {
    test('drops muted feeds and caps the list', () {
      final articles = <Article>[
        _article('a1', 'muted'),
        _article('a2', 'loud', title: 'Second'),
        _article('a3', 'loud', title: 'Third'),
      ];
      final items = selectNotificationItems(
        articles: articles,
        feedTitles: {'muted': 'Muted', 'loud': 'Loud'},
        mutedFeedIds: {'muted'},
        limit: 2,
      );
      expect(items.map((i) => i.articleId), ['a2', 'a3']);
      expect(items.first.feedTitle, 'Loud');
    });

    test('unknown feeds fall back to the app name', () {
      final items = selectNotificationItems(
        articles: [_article('a1', 'gone')],
        feedTitles: const <String, String>{},
        mutedFeedIds: const <String>{},
      );
      expect(items.single.feedTitle, 'FreeAd');
    });
  });

  group('syncNotificationSchedule', () {
    test('disabled cancels the work', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _mockChannels();
      final settings = await _settings();
      final fake = _FakeScheduler();
      await syncNotificationSchedule(
        settings,
        scheduler: fake,
        platformSupportedOverride: true,
      );
      expect(fake.cancels, 1);
      expect(fake.lastFrequency, isNull);
      settings.dispose();
    });

    test('enabled schedules the configured interval', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _mockChannels();
      final settings = await _settings();
      await settings.setNotificationsEnabled(true);
      await settings.setNotificationCheckIntervalMinutes(30);
      final fake = _FakeScheduler();
      await syncNotificationSchedule(
        settings,
        scheduler: fake,
        platformSupportedOverride: true,
      );
      expect(fake.lastFrequency, const Duration(minutes: 30));
      expect(fake.cancels, 0);
      settings.dispose();
    });

    test('unsupported platforms cancel instead of scheduling', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _mockChannels();
      final settings = await _settings();
      await settings.setNotificationsEnabled(true);
      final fake = _FakeScheduler();
      await syncNotificationSchedule(
        settings,
        scheduler: fake,
        platformSupportedOverride: false,
      );
      expect(fake.cancels, 1);
      expect(fake.lastFrequency, isNull);
      settings.dispose();
    });
  });

  group('SettingsProvider notifications', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _mockChannels();
    });

    test('defaults are off with hourly checks', () async {
      final settings = await _settings();
      expect(settings.notificationsEnabled, isFalse);
      expect(settings.notificationCheckIntervalMinutes, 60);
      expect(settings.quietHoursEnabled, isFalse);
      expect(settings.quietHoursStartMinutes, 22 * 60);
      expect(settings.quietHoursEndMinutes, 7 * 60);
      expect(settings.notificationSound, isTrue);
      expect(settings.notificationVibrate, isTrue);
      expect(settings.mutedNotificationFeeds, isEmpty);
      settings.dispose();
    });

    test('values round trip and reset restores defaults', () async {
      final settings = await _settings();
      await settings.setNotificationsEnabled(true);
      await settings.setNotificationCheckIntervalMinutes(15);
      await settings.setQuietHoursEnabled(true);
      await settings.setQuietHoursStartMinutes(23 * 60);
      await settings.setQuietHoursEndMinutes(6 * 60 + 30);
      await settings.setNotificationSound(false);
      await settings.setFeedMutedForNotifications('feed-1', true);

      final reloaded = await _settings();
      expect(reloaded.notificationsEnabled, isTrue);
      expect(reloaded.notificationCheckIntervalMinutes, 15);
      expect(reloaded.quietHoursEnabled, isTrue);
      expect(reloaded.quietHoursStartMinutes, 23 * 60);
      expect(reloaded.quietHoursEndMinutes, 6 * 60 + 30);
      expect(reloaded.notificationSound, isFalse);
      expect(reloaded.isFeedMutedForNotifications('feed-1'), isTrue);

      await reloaded.setFeedMutedForNotifications('feed-1', false);
      expect(reloaded.isFeedMutedForNotifications('feed-1'), isFalse);

      await reloaded.resetAllSettings();
      expect(reloaded.notificationsEnabled, isFalse);
      expect(reloaded.notificationCheckIntervalMinutes, 60);
      expect(reloaded.mutedNotificationFeeds, isEmpty);
      settings.dispose();
      reloaded.dispose();
    });

    test('unknown interval falls back to hourly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsProvider.notificationIntervalKey: 999,
      });
      final settings = await _settings();
      expect(settings.notificationCheckIntervalMinutes, 60);
      settings.dispose();
    });
  });
}
