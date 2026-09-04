import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../providers/settings_provider.dart';

/// Schedules the periodic background feed refresh.
///
/// The interface exists so settings UI and tests never touch WorkManager
/// directly: production passes nothing (WorkManager), tests inject a fake.
abstract class RefreshScheduler {
  Future<void> schedulePeriodic({required Duration frequency});
  Future<void> cancelAll();
}

/// WorkManager-backed scheduler (Android; iOS registers a periodic refresh
/// where the OS allows it).
class WorkmanagerRefreshScheduler implements RefreshScheduler {
  const WorkmanagerRefreshScheduler();

  static const String uniqueName = 'freead-feed-refresh';
  static const String taskName = 'freeadFeedRefresh';

  @override
  Future<void> schedulePeriodic({required Duration frequency}) {
    final safe = frequency.inMinutes < 15
        ? const Duration(minutes: 15)
        : frequency;
    return Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: safe,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
    );
  }

  @override
  Future<void> cancelAll() => Workmanager().cancelAll();
}

/// Registers or cancels the background refresh to match [settings].
///
/// Cancels everywhere when notifications are off (the foreground
/// pull-to-refresh is unaffected) or on unsupported platforms.
/// [platformSupportedOverride] and [scheduler] exist for unit tests.
Future<void> syncNotificationSchedule(
  SettingsProvider settings, {
  RefreshScheduler? scheduler,
  bool? platformSupportedOverride,
}) async {
  bool supported;
  if (platformSupportedOverride != null) {
    supported = platformSupportedOverride;
  } else {
    try {
      supported = !kIsWeb && Platform.isAndroid;
    } catch (_) {
      supported = false;
    }
  }
  final active = scheduler ?? const WorkmanagerRefreshScheduler();
  if (!supported || !settings.notificationsEnabled) {
    try {
      await active.cancelAll();
    } catch (_) {
      // Scheduler missing (tests without a fake).
    }
    return;
  }
  await active.schedulePeriodic(
    frequency: Duration(
      minutes: settings.notificationCheckIntervalMinutes,
    ),
  );
}
