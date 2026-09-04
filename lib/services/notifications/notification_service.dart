import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_content.dart';
import 'notification_payload.dart';

/// Called with the tap target of a notification (main isolate only).
typedef NotificationTapHandler = Future<void> Function(
  NotificationPayload payload,
);

/// Thin wrapper around `flutter_local_notifications` for new-article alerts.
///
/// Channel, importance and style choices live here; text shaping in
/// `notification_content.dart`; scheduling in `refresh_scheduler.dart`.
/// All methods are safe no-ops off Android/iOS (unit tests, desktop).
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'freead_new_articles';
  static const String channelName = 'New articles';

  /// Shown when the user taps "Test notification" in settings.
  static const int testNotificationId = 1001;

  /// Single id per refresh run, so each digest replaces the previous one.
  static const int digestNotificationId = 1002;

  /// Remembers which sound/vibration combo the channel was created with
  /// (Android channels are immutable once created).
  static const String channelConfigKey = 'notification_channel_config';

  final FlutterLocalNotificationsPlugin _plugin;
  NotificationTapHandler? _onTap;
  bool _ready = false;

  /// Prepares the plugin. [onTap] handles live taps while the UI is up;
  /// cold-start taps are read separately via [consumeLaunchPayload].
  Future<void> init({NotificationTapHandler? onTap}) async {
    _onTap = onTap ?? _onTap;
    if (_ready) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
      _ready = true;
    } catch (_) {
      // Unsupported platform (tests, desktop) - every show() below guards
      // on _ready and stays silent.
      _ready = false;
    }
  }

  /// Minimal init for the background isolate (no tap handling there).
  Future<void> initForBackground() => init();

  void _handleResponse(NotificationResponse response) {
    final payload = NotificationPayload.tryDecode(response.payload);
    if (payload == null) return;
    final handler = _onTap;
    if (handler != null) unawaited(handler(payload));
  }

  /// Creates (or recreates, when sound/vibration changed) the channel.
  Future<void> ensureChannel({
    required bool sound,
    required bool vibrate,
  }) async {
    if (!_isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();
    if (android == null) return;
    try {
      await android.deleteNotificationChannel(channelId: channelId);
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Alerts when followed feeds publish new articles.',
          importance: Importance.high,
          playSound: sound,
          enableVibration: vibrate,
        ),
      );
    } catch (_) {
      // Best effort: a missing channel still shows on most devices.
    }
  }

  /// True when the OS currently allows us to post.
  Future<bool> areEnabled() async {
    if (!_isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
      return await android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Asks for the runtime permission (Android 13+ / iOS). False when the
  /// user declines or the platform needs no prompt.
  Future<bool> requestPermission() async {
    try {
      if (_isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (_) {
      // Plugin missing (tests) or already configured.
    }
    return false;
  }

  /// Shows [digest]: big-text for one article (deep link), inbox style for
  /// many (opens home).
  Future<void> showDigest(
    NewArticlesDigest digest, {
    required bool sound,
    required bool vibrate,
  }) async {
    if (!_ready) return;
    final bool single = digest.articleId != null;
    await showRaw(
      id: digestNotificationId,
      title: digest.title,
      body: digest.body,
      lines: single ? null : digest.lines,
      summaryText: digest.summaryText,
      payload: single
          ? NotificationPayload.article(digest.articleId!).encode()
          : const NotificationPayload.home().encode(),
      sound: sound,
      vibrate: vibrate,
    );
  }

  /// Low-level show used by [showDigest] and tests of the payload path.
  @visibleForTesting
  Future<void> showRaw({
    required int id,
    required String title,
    required String body,
    required String payload,
    required bool sound,
    required bool vibrate,
    List<String>? lines,
    String? summaryText,
  }) async {
    if (!_ready) return;
    final DefaultStyleInformation style = lines == null
        ? BigTextStyleInformation(body, contentTitle: title)
        : InboxStyleInformation(
            lines,
            contentTitle: title,
            summaryText: summaryText,
          );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: style,
            playSound: sound,
            enableVibration: vibrate,
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {
      // Notifications must never crash a refresh.
    }
  }

  /// A sample alert so users can verify sound, vibration and tap behaviour.
  Future<void> showTest({required bool sound, required bool vibrate}) async {
    if (!_ready) return;
    await showRaw(
      id: testNotificationId,
      title: 'Notifications are on',
      body: 'FreeAd will alert you when followed feeds publish.',
      payload: const NotificationPayload.home().encode(),
      sound: sound,
      vibrate: vibrate,
    );
  }

  /// Payload of the notification that cold-started the app, if any.
  Future<NotificationPayload?> consumeLaunchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return NotificationPayload.tryDecode(
        details?.notificationResponse?.payload,
      );
    } catch (_) {
      return null;
    }
  }

  static bool get _isAndroid {
    try {
      return !kIsWeb && Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}
