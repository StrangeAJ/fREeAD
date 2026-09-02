/// Tolerant date parsing for feed documents.
///
/// Feeds are notoriously sloppy about dates: RSS 2.0 mandates RFC 822,
/// Atom mandates RFC 3339, and real feeds ship everything in between. Every
/// parser here returns a **local** [DateTime] so the UI can sort and group
/// without further conversion.
library;

const Map<String, int> _months = <String, int>{
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

/// Named time zones seen in RFC 822 dates, in minutes offset from UTC.
const Map<String, int> _namedZones = <String, int>{
  'gmt': 0,
  'ut': 0,
  'utc': 0,
  'z': 0,
  'est': -5 * 60,
  'edt': -4 * 60,
  'cst': -6 * 60,
  'cdt': -5 * 60,
  'mst': -7 * 60,
  'mdt': -6 * 60,
  'pst': -8 * 60,
  'pdt': -7 * 60,
};

/// `Tue, 15 Nov 1994 12:45:26 GMT` and its many relatives.
final RegExp _rfc822 = RegExp(
  r'^(?:[a-z]{3,9}\.?,?\s+)?'
  r'(\d{1,2})\s+([a-z]{3,9})\.?,?\s+(\d{2,4})'
  r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?'
  r'\s*(.*)$',
  caseSensitive: false,
);

/// `Nov 15, 1994 12:45:26 GMT` - the American ordering.
final RegExp _monthFirst = RegExp(
  r'^(?:[a-z]{3,9}\.?,?\s+)?'
  r'([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})'
  r'(?:\s+(?:at\s+)?(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?'
  r'\s*(.*)$',
  caseSensitive: false,
);

/// `2026-07-01 12:30:00` / `2026/07/01 12:30` with an optional zone.
final RegExp _numeric = RegExp(
  r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})'
  r'(?:[\sT]+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?'
  r'\s*(.*)$',
);

/// Trailing zone designators: `+0530`, `-05:30`, `GMT`, `GMT+0200`, `PST`, `Z`.
final RegExp _zonePattern = RegExp(
  r'^(?:(gmt|utc?)\s*)?([+-])(\d{1,2}):?(\d{2})?$|^([a-z]{1,4})$',
  caseSensitive: false,
);

/// Parses a feed date string into local time, or returns null.
///
/// Supports RFC 822/2822 (numeric, named and military zones, two digit years,
/// missing weekday, missing seconds), ISO 8601 / RFC 3339 (with or without a
/// zone, fractional seconds, space instead of `T`) and common sloppy formats
/// (`yyyy-MM-dd HH:mm:ss`, `dd MMM yyyy`, `MMM d, yyyy`).
DateTime? parseFeedDate(String? input) {
  if (input == null) return null;
  var text = input.trim();
  if (text.isEmpty) return null;

  // Strip a trailing parenthesised zone name: "+0000 (UTC)".
  text = text.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  if (text.isEmpty) return null;

  // 1. ISO 8601 / RFC 3339 - the cheapest and most precise path.
  final iso = _tryIso(text);
  if (iso != null) return iso;

  // 2. RFC 822 style: day month year.
  final rfc = _tryPattern(
    _rfc822.firstMatch(text),
    dayGroup: 1,
    monthGroup: 2,
    yearGroup: 3,
  );
  if (rfc != null) return rfc;

  // 3. American style: month day, year.
  final american = _tryPattern(
    _monthFirst.firstMatch(text),
    dayGroup: 2,
    monthGroup: 1,
    yearGroup: 3,
  );
  if (american != null) return american;

  // 4. Numeric year-first dates that DateTime.parse rejected (e.g. `2026/7/1`).
  final numeric = _numeric.firstMatch(text);
  if (numeric != null) {
    final year = int.tryParse(numeric.group(1)!);
    final month = int.tryParse(numeric.group(2)!);
    final day = int.tryParse(numeric.group(3)!);
    if (year != null && month != null && day != null) {
      return _build(
        year: year,
        month: month,
        day: day,
        hour: int.tryParse(numeric.group(4) ?? '') ?? 0,
        minute: int.tryParse(numeric.group(5) ?? '') ?? 0,
        second: int.tryParse(numeric.group(6) ?? '') ?? 0,
        zone: numeric.group(7),
        defaultToUtc: numeric.group(7)?.trim().isNotEmpty ?? false,
      );
    }
  }

  return null;
}

DateTime? _tryIso(String text) {
  // DateTime.parse handles `T`/space separators, fractional seconds, `Z` and
  // numeric offsets, but only for year-first values.
  if (!RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(text)) return null;

  final parsed = DateTime.tryParse(text);
  if (parsed != null) return parsed.toLocal();

  // Collapse odd separators: `2026-07-01  12:00:00` or a trailing zone name.
  final normalized = text.replaceFirst(RegExp(r'\s+'), 'T').trim();
  final retry = DateTime.tryParse(normalized);
  if (retry != null) return retry.toLocal();

  // `2026-07-01T12:00:00+05` (hour-only offset) is rejected by DateTime.parse.
  if (RegExp(r'[+-]\d{2}$').hasMatch(normalized)) {
    final padded = DateTime.tryParse('${normalized}00');
    if (padded != null) return padded.toLocal();
  }
  return null;
}

DateTime? _tryPattern(
  RegExpMatch? match, {
  required int dayGroup,
  required int monthGroup,
  required int yearGroup,
}) {
  if (match == null) return null;
  final month = _months[match.group(monthGroup)!.toLowerCase()];
  if (month == null) return null;
  final day = int.tryParse(match.group(dayGroup)!);
  if (day == null) return null;
  var year = int.tryParse(match.group(yearGroup)!);
  if (year == null) return null;
  if (year < 100) year = year < 50 ? 2000 + year : 1900 + year;

  return _build(
    year: year,
    month: month,
    day: day,
    hour: int.tryParse(match.group(4) ?? '') ?? 0,
    minute: int.tryParse(match.group(5) ?? '') ?? 0,
    second: int.tryParse(match.group(6) ?? '') ?? 0,
    zone: match.group(7),
    // RFC 822 requires a zone; a feed that omits it almost always means UTC.
    defaultToUtc: true,
  );
}

DateTime? _build({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  required int second,
  String? zone,
  bool defaultToUtc = true,
}) {
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 60) return null;

  final offsetMinutes = _zoneOffsetMinutes(zone);
  if (offsetMinutes == null && !defaultToUtc) {
    return DateTime(year, month, day, hour, minute, second);
  }

  final utc = DateTime.utc(year, month, day, hour, minute, second);
  // Guard against overflow like 31 February silently rolling over.
  if (utc.month != month || utc.day != day) return null;
  return utc.subtract(Duration(minutes: offsetMinutes ?? 0)).toLocal();
}

/// Offset of [zone] from UTC in minutes, or null when [zone] is absent.
int? _zoneOffsetMinutes(String? zone) {
  final text = zone?.trim();
  if (text == null || text.isEmpty) return null;

  final match = _zonePattern.firstMatch(text);
  if (match == null) return 0;

  final name = match.group(5);
  if (name != null) {
    final lower = name.toLowerCase();
    final known = _namedZones[lower];
    if (known != null) return known;
    // RFC 2822 4.3: single letter military zones should be treated as -0000.
    if (lower.length == 1) return 0;
    return 0;
  }

  final sign = match.group(2) == '-' ? -1 : 1;
  final hours = int.tryParse(match.group(3) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(4) ?? '0') ?? 0;
  if (hours > 14 || minutes > 59) return 0;
  return sign * (hours * 60 + minutes);
}
