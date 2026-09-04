import 'dart:convert';

/// Tap target of a FreeAd notification, carried as the notification payload.
///
/// Encoded as compact JSON so `main.dart` can route the tap without touching
/// the database: `{"kind":"article","id":"..."}`.
class NotificationPayload {
  const NotificationPayload._(this.kind, this.id);

  /// Opens one article in the reader.
  const NotificationPayload.article(String articleId)
    : this._('article', articleId);

  /// Opens one feed's article list.
  const NotificationPayload.feed(String feedId) : this._('feed', feedId);

  /// Opens the app home (used for multi-article digests).
  const NotificationPayload.home() : this._('home', null);

  final String kind;
  final String? id;

  bool get isArticle => kind == 'article';
  bool get isFeed => kind == 'feed';
  bool get isHome => kind == 'home';

  String encode() => jsonEncode({
    'kind': kind,
    if (id != null) 'id': id,
  });

  /// Null when [raw] is missing, malformed, or names an unknown target.
  static NotificationPayload? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final kind = decoded['kind']?.toString();
      final id = decoded['id']?.toString();
      switch (kind) {
        case 'article':
          if (id != null && id.isNotEmpty) {
            return NotificationPayload.article(id);
          }
          return null;
        case 'feed':
          if (id != null && id.isNotEmpty) {
            return NotificationPayload.feed(id);
          }
          return null;
        case 'home':
          return const NotificationPayload.home();
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'NotificationPayload($kind, $id)';
}
