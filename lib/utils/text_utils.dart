/// Small, dependency-free string / URL helpers shared across the app.
///
/// Everything here is pure Dart so it can also run inside `compute` isolates.
library;

/// Query parameters that only exist for campaign tracking.
const Set<String> _trackingParams = <String>{
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_name',
  'utm_reader',
  'utm_brand',
  'utm_social',
  'utm_social-type',
  'fbclid',
  'gclid',
  'dclid',
  'msclkid',
  'mc_cid',
  'mc_eid',
  'igshid',
  'ref_src',
  'ref_url',
  'yclid',
  'ncid',
  'cmpid',
  'sr_share',
  'at_medium',
  'at_campaign',
  '__twitter_impression',
};

/// Host of [url] without a leading `www.`, or null when [url] is unusable.
String? hostOf(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) {
    uri = Uri.tryParse('https://$trimmed');
  }
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Removes UTM / click-id parameters from [url]. Returns [url] unchanged when
/// it cannot be parsed.
String stripUtm(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return url;
  if (uri.queryParameters.isEmpty && !uri.hasFragment) return url;

  final kept = <String, List<String>>{};
  uri.queryParametersAll.forEach((key, values) {
    if (_trackingParams.contains(key.toLowerCase())) return;
    kept[key] = values;
  });

  final cleaned = uri.replace(
    queryParameters: kept.isEmpty ? null : kept,
  );
  var result = cleaned.toString();
  // Uri.replace with an empty map still leaves a dangling '?'.
  if (kept.isEmpty && result.endsWith('?')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Google's favicon service for the host of [siteOrFeedUrl].
///
/// Returns an empty string when no host can be derived, so callers can fall
/// back to initials.
String faviconUrlFor(String? siteOrFeedUrl) {
  final host = hostOf(siteOrFeedUrl);
  if (host == null) return '';
  return 'https://www.google.com/s2/favicons?domain=$host&sz=128';
}

/// Truncates [text] to at most [max] characters on a word boundary.
String truncate(String text, int max, {String ellipsis = '...'}) {
  final trimmed = text.trim();
  if (max <= 0) return '';
  if (trimmed.length <= max) return trimmed;
  var cut = trimmed.substring(0, max);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > max ~/ 2) cut = cut.substring(0, lastSpace);
  return '${cut.trimRight()}$ellipsis';
}

/// Collapses all runs of whitespace (including newlines) into single spaces.
String collapseWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Short, human readable "time ago" label, e.g. `3h`, `2d`, `Mar 4`.
String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);

  if (diff.isNegative) return 'Just now';
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 365) {
    return '${_monthNames[time.month - 1]} ${time.day}';
  }
  return '${_monthNames[time.month - 1]} ${time.day}, ${time.year}';
}

/// Bucket label used by date-grouped article lists.
String dateGroupLabel(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(time.year, time.month, time.day);
  final delta = today.difference(day).inDays;

  if (delta <= 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  if (delta < 7) return 'This week';
  return 'Earlier';
}

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Word count of a plain-text string.
int wordCountOf(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

/// Up to two initials for [name], used by avatar fallbacks.
String initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s\-_.]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final word = parts.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}
