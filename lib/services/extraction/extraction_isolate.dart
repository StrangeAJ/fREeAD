/// Top level entry points for `compute`.
///
/// Everything here must be pure Dart plus `dio` (which works inside isolates)
/// and must only exchange JSON-compatible maps with the caller.
library;

import 'html_fetcher.dart';
import 'readability.dart';

/// Keys used by [fetchAndExtractIsolate]'s result map.
class ExtractionIsolateKeys {
  static const String ok = 'ok';
  static const String error = 'error';
  static const String statusCode = 'statusCode';
  static const String finalUrl = 'finalUrl';
  static const String ampUrl = 'ampUrl';
  static const String canonicalUrl = 'canonicalUrl';
  static const String result = 'result';
}

/// Fetches [args]`['url']` and runs [Readability] on it.
///
/// [args] accepts `url` (required), `mobileUa` (bool) and `source` (String).
/// Never throws: failures come back as `{ok: false, error: <message>}` so the
/// caller does not have to marshal exception types across the isolate.
Future<Map<String, dynamic>> fetchAndExtractIsolate(
  Map<String, dynamic> args,
) async {
  final url = args['url'] as String? ?? '';
  final mobileUa = args['mobileUa'] == true;
  final source = args['source'] as String? ?? 'http';

  if (url.isEmpty) {
    return <String, dynamic>{
      ExtractionIsolateKeys.ok: false,
      ExtractionIsolateKeys.error: 'No article URL.',
    };
  }

  final fetcher = HtmlFetcher();
  try {
    final page = await fetcher.fetch(url, mobileUa: mobileUa);
    final result = const Readability().parse(
      page.html,
      page.finalUrl,
      source: source,
    );
    return <String, dynamic>{
      ExtractionIsolateKeys.ok: true,
      ExtractionIsolateKeys.statusCode: page.statusCode,
      ExtractionIsolateKeys.finalUrl: page.finalUrl,
      ExtractionIsolateKeys.ampUrl: page.ampUrl,
      ExtractionIsolateKeys.canonicalUrl: page.canonicalUrl,
      ExtractionIsolateKeys.result: result?.toJson(),
    };
  } on FetchException catch (e) {
    return <String, dynamic>{
      ExtractionIsolateKeys.ok: false,
      ExtractionIsolateKeys.error: e.userMessage,
      ExtractionIsolateKeys.statusCode: e.statusCode,
    };
  } catch (e) {
    return <String, dynamic>{
      ExtractionIsolateKeys.ok: false,
      ExtractionIsolateKeys.error: 'Could not load the article ($e).',
    };
  } finally {
    fetcher.dispose();
  }
}

/// Runs [Readability] over already fetched HTML inside an isolate.
///
/// [args] accepts `html`, `url` and `source`.
Map<String, dynamic>? readabilityIsolate(Map<String, dynamic> args) {
  final html = args['html'] as String? ?? '';
  final url = args['url'] as String? ?? '';
  final source = args['source'] as String? ?? 'http';
  if (html.isEmpty) return null;
  return const Readability().parse(html, url, source: source)?.toJson();
}
