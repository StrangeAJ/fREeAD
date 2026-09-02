import 'dart:async';

import '../models/article.dart';
import '../models/rss_feed.dart';
import '../services/rss/rss_service.dart';

/// Runs [fn] over [items] with at most [limit] operations in flight.
///
/// Results keep the order of [items]. Errors thrown by [fn] propagate to the
/// caller, so wrap [fn] in a try/catch when partial failures are acceptable.
/// [onProgress] is called after each item completes with `(done, total)`.
Future<List<T>> mapWithConcurrency<T, S>(
  Iterable<S> items,
  int limit,
  Future<T> Function(S item) fn, {
  void Function(int done, int total)? onProgress,
}) async {
  final list = items.toList(growable: false);
  final total = list.length;
  if (total == 0) return <T>[];

  final effectiveLimit = limit < 1 ? 1 : (limit > total ? total : limit);
  final results = List<T?>.filled(total, null);
  var next = 0;
  var done = 0;

  Future<void> worker() async {
    while (true) {
      final index = next;
      if (index >= total) return;
      next++;
      try {
        results[index] = await fn(list[index]);
      } finally {
        done++;
        onProgress?.call(done, total);
      }
    }
  }

  await Future.wait(<Future<void>>[
    for (var i = 0; i < effectiveLimit; i++) worker(),
  ]);

  return results.cast<T>();
}

/// Collapses bursts of calls into a single delayed call.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  /// Schedules [action], cancelling any previously scheduled one.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// True while a call is pending.
  bool get isPending => _timer?.isActive ?? false;

  /// Cancels a pending call without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}

// ---------------------------------------------------------------------------
// Isolate entry points (top level functions, usable with `compute`)
// ---------------------------------------------------------------------------

/// Fetches and parses a feed inside an isolate.
///
/// [params] must contain `url` and `feedId`, optionally `categoryId`.
FutureOr<List<Article>> parseRSSFeedIsolate(Map<String, String> params) async {
  final service = RssService();
  try {
    return await service.fetchFeedArticles(
      params['url']!,
      params['feedId']!,
      categoryId: params['categoryId'],
    );
  } finally {
    service.dispose();
  }
}

/// Fetches feed metadata inside an isolate.
FutureOr<RSSFeed> fetchFeedInfoIsolate(String url) async {
  final service = RssService();
  try {
    return await service.fetchFeedInfo(url);
  } finally {
    service.dispose();
  }
}
