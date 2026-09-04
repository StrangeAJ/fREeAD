// Pure helpers behind new-article notifications: quiet-hours checks, digest
// text and feed filtering. No Flutter or plugin imports, so unit tests cover
// everything here. Delivery lives in notification_service.dart; the
// background fetch in feed_refresh_task.dart.

/// One article worth telling the user about.
class DigestItem {
  const DigestItem({
    required this.articleId,
    required this.title,
    required this.feedTitle,
    this.excerpt = '',
  });

  final String articleId;
  final String title;
  final String feedTitle;
  final String excerpt;
}

/// Rendered form of a new-articles notification.
class NewArticlesDigest {
  const NewArticlesDigest({
    required this.title,
    required this.body,
    this.lines = const <String>[],
    this.summaryText,
    this.articleId,
    required this.count,
  });

  /// Headline. Single article: the article title. Many: "N new articles".
  final String title;

  /// Single article: "Feed name - excerpt". Many: first line, reused as the
  /// collapsed body.
  final String body;

  /// Inbox-style lines for multi-article digests (capped by the builder).
  final List<String> lines;

  /// Inbox summary ("+3 more"), null when everything fits.
  final String? summaryText;

  /// Set for single-article digests so the tap opens the reader.
  final String? articleId;

  final int count;
}

/// Builds the notification for [items], or null when there is nothing new.
///
/// Single article -> big-text style with a deep link. Many -> inbox style
/// with up to [maxLines] rows and a "+N more" summary.
NewArticlesDigest? buildNewArticlesDigest(
  List<DigestItem> items, {
  int maxLines = 5,
}) {
  if (items.isEmpty) return null;

  if (items.length == 1) {
    final item = items.single;
    final excerpt = item.excerpt.trim();
    return NewArticlesDigest(
      title: item.title.trim().isEmpty ? item.feedTitle : item.title.trim(),
      body: excerpt.isEmpty
          ? item.feedTitle
          : '${item.feedTitle} - ${_truncate(excerpt, 200)}',
      articleId: item.articleId,
      count: 1,
    );
  }

  final lines = items
      .take(maxLines)
      .map((item) => _truncate('${item.feedTitle}: ${item.title}', 80))
      .toList();
  final remaining = items.length - lines.length;
  return NewArticlesDigest(
    title: '${items.length} new articles',
    body: lines.first,
    lines: lines,
    summaryText: remaining > 0 ? '+$remaining more' : null,
    count: items.length,
  );
}

/// True when notifications must stay silent right now.
///
/// Overnight windows (e.g. 22:00-07:00) wrap past midnight. A window where
/// start equals end means "no quiet hours".
bool isQuietNow({
  required bool enabled,
  required int startMinutes,
  required int endMinutes,
  DateTime? now,
}) {
  if (!enabled) return false;
  final start = startMinutes.clamp(0, 24 * 60 - 1);
  final end = endMinutes.clamp(0, 24 * 60 - 1);
  if (start == end) return false;
  final current = now ?? DateTime.now();
  final minutes = current.hour * 60 + current.minute;
  if (start < end) return minutes >= start && minutes < end;
  return minutes >= start || minutes < end;
}

/// Minutes-since-midnight (0-1439) clamped into range.
int clampDayMinutes(int value) => value.clamp(0, 24 * 60 - 1);

/// "HH:MM" for settings rows, e.g. 22:00 or 07:05.
String formatDayMinutes(int minutes) {
  final clamped = clampDayMinutes(minutes);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _truncate(String text, int max) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= max) return trimmed;
  return '${trimmed.substring(0, max - 1).trimRight()}…';
}
