import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Log levels used by [AppLog].
enum AppLogLevel { debug, info, warning, error }

/// Lightweight application logger.
///
/// Never use `print(` in `lib/`. Use [AppLog.d]/[AppLog.i]/[AppLog.w]/[AppLog.e]
/// instead: output goes to `dart:developer`'s `log` (so it shows up structured in
/// DevTools / logcat) and is suppressed entirely in release builds.
class AppLog {
  AppLog._();

  static const String _name = 'FreeAd';

  /// Set to false to silence all logging (used by tests that assert on stdout).
  static bool enabled = true;

  /// Minimum level that gets emitted.
  static AppLogLevel minLevel = kReleaseMode
      ? AppLogLevel.warning
      : AppLogLevel.debug;

  /// Debug-level message.
  static void d(String msg, [Object? err, StackTrace? st]) =>
      _log(AppLogLevel.debug, msg, err, st);

  /// Informational message.
  static void i(String msg, [Object? err, StackTrace? st]) =>
      _log(AppLogLevel.info, msg, err, st);

  /// Warning: something unexpected but recoverable.
  static void w(String msg, [Object? err, StackTrace? st]) =>
      _log(AppLogLevel.warning, msg, err, st);

  /// Error: an operation failed.
  static void e(String msg, [Object? err, StackTrace? st]) =>
      _log(AppLogLevel.error, msg, err, st);

  static void _log(
    AppLogLevel level,
    String msg, [
    Object? err,
    StackTrace? st,
  ]) {
    if (!enabled) return;
    if (level.index < minLevel.index) return;
    if (kReleaseMode) return;

    developer.log(
      msg,
      name: _name,
      level: _developerLevel(level),
      error: err,
      stackTrace: st,
      time: DateTime.now(),
    );

    // `developer.log` is not always surfaced by the tooling in profile mode, so
    // mirror the important levels to the console as well.
    if (level.index >= AppLogLevel.warning.index) {
      debugPrint('[$_name] ${level.name.toUpperCase()}: $msg');
      if (err != null) debugPrint('[$_name]   error: $err');
      if (st != null) debugPrint('[$_name]   $st');
    }
  }

  static int _developerLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return 500;
      case AppLogLevel.info:
        return 800;
      case AppLogLevel.warning:
        return 900;
      case AppLogLevel.error:
        return 1000;
    }
  }
}
