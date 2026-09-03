import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/rss/date_parser.dart';

/// Expects [input] to parse to the given UTC instant.
void expectUtc(String input, DateTime expected) {
  final parsed = parseFeedDate(input);
  expect(parsed, isNotNull, reason: 'failed to parse "$input"');
  expect(
    parsed!.toUtc(),
    expected,
    reason: '"$input" parsed to ${parsed.toUtc()} instead of $expected',
  );
}

void main() {
  group('RFC 822 / 2822', () {
    test('canonical form with GMT', () {
      expectUtc(
        'Tue, 15 Nov 1994 12:45:26 GMT',
        DateTime.utc(1994, 11, 15, 12, 45, 26),
      );
    });

    test('numeric offset', () {
      expectUtc(
        'Mon, 01 Sep 2025 10:30:00 +0530',
        DateTime.utc(2025, 9, 1, 5, 0, 0),
      );
    });

    test('numeric offset with a colon', () {
      expectUtc(
        'Mon, 01 Sep 2025 10:30:00 -05:00',
        DateTime.utc(2025, 9, 1, 15, 30, 0),
      );
    });

    test('missing weekday', () {
      expectUtc(
        '15 Nov 1994 12:45:26 GMT',
        DateTime.utc(1994, 11, 15, 12, 45, 26),
      );
    });

    test('missing seconds', () {
      expectUtc(
        'Mon, 30 Jun 2026 22:15 GMT',
        DateTime.utc(2026, 6, 30, 22, 15),
      );
    });

    test('two digit year below 50 is 20xx', () {
      expectUtc(
        '15 Nov 26 12:45:26 UT',
        DateTime.utc(2026, 11, 15, 12, 45, 26),
      );
    });

    test('two digit year above 50 is 19xx', () {
      expectUtc(
        '15 Nov 99 12:45:26 GMT',
        DateTime.utc(1999, 11, 15, 12, 45, 26),
      );
    });

    test('named US zones', () {
      expectUtc(
        'Sat, 07 Sep 2002 09:42:31 EST',
        DateTime.utc(2002, 9, 7, 14, 42, 31),
      );
      expectUtc(
        'Sat, 07 Sep 2002 09:42:31 PDT',
        DateTime.utc(2002, 9, 7, 16, 42, 31),
      );
      expectUtc(
        'Sat, 07 Sep 2002 09:42:31 CDT',
        DateTime.utc(2002, 9, 7, 14, 42, 31),
      );
      expectUtc(
        'Sat, 07 Sep 2002 09:42:31 MST',
        DateTime.utc(2002, 9, 7, 16, 42, 31),
      );
    });

    test('single letter military zone is treated as UTC', () {
      expectUtc(
        'Sat, 07 Sep 2002 09:42:31 A',
        DateTime.utc(2002, 9, 7, 9, 42, 31),
      );
    });

    test('full weekday and month names', () {
      expectUtc(
        'Tuesday, 15 November 1994 12:45:26 GMT',
        DateTime.utc(1994, 11, 15, 12, 45, 26),
      );
    });

    test('trailing parenthesised zone name is ignored', () {
      expectUtc(
        'Tue, 15 Nov 1994 12:45:26 +0000 (UTC)',
        DateTime.utc(1994, 11, 15, 12, 45, 26),
      );
    });

    test('no zone at all falls back to UTC', () {
      expectUtc(
        'Tue, 15 Nov 1994 12:45:26',
        DateTime.utc(1994, 11, 15, 12, 45, 26),
      );
    });
  });

  group('ISO 8601 / RFC 3339', () {
    test('with Z', () {
      expectUtc('2026-07-01T12:00:00Z', DateTime.utc(2026, 7, 1, 12));
    });

    test('with fractional seconds', () {
      expectUtc(
        '2026-07-02T09:15:30.250Z',
        DateTime.utc(2026, 7, 2, 9, 15, 30, 250),
      );
    });

    test('with a numeric offset', () {
      expectUtc('2026-06-29T14:05:00+02:00', DateTime.utc(2026, 6, 29, 12, 5));
    });

    test('space instead of T', () {
      expectUtc('2026-07-01 08:00:00 +0000', DateTime.utc(2026, 7, 1, 8));
    });

    test('date only is local midnight', () {
      final parsed = parseFeedDate('2026-06-28');
      expect(parsed, DateTime(2026, 6, 28));
    });

    test('local time without a zone stays local', () {
      final parsed = parseFeedDate('2026-07-01T12:00:00');
      expect(parsed, DateTime(2026, 7, 1, 12));
    });
  });

  group('Sloppy formats', () {
    test('yyyy-MM-dd HH:mm:ss without a zone', () {
      final parsed = parseFeedDate('2026-07-01 12:30:45');
      expect(parsed, DateTime(2026, 7, 1, 12, 30, 45));
    });

    test('slash separated date', () {
      expectUtc('2026/07/01 12:00:00 GMT', DateTime.utc(2026, 7, 1, 12));
    });

    test('dd MMM yyyy without a time', () {
      expectUtc('01 Jul 2026', DateTime.utc(2026, 7, 1));
    });

    test('MMM d, yyyy', () {
      expectUtc('Jul 1, 2026', DateTime.utc(2026, 7, 1));
    });

    test('MMM d, yyyy with a time', () {
      expectUtc(
        'Nov 15, 1994 12:45:26 GMT',
        DateTime.utc(1994, 11, 15, 12, 45, 26),
      );
    });
  });

  group('Rejections', () {
    test('null, empty and garbage return null', () {
      expect(parseFeedDate(null), isNull);
      expect(parseFeedDate(''), isNull);
      expect(parseFeedDate('   '), isNull);
      expect(parseFeedDate('not a date at all'), isNull);
      expect(parseFeedDate('Fri, 32 Xyz 2026 99:99:99 GMT'), isNull);
    });

    test('impossible calendar dates return null', () {
      expect(parseFeedDate('31 Feb 2026 00:00:00 GMT'), isNull);
    });
  });

  test('returns local time', () {
    final parsed = parseFeedDate('Tue, 15 Nov 1994 12:45:26 GMT');
    expect(parsed!.isUtc, isFalse);
  });
}
