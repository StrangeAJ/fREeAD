import 'package:flutter/foundation.dart';

import '../../models/app_settings.dart';
import '../../utils/app_logger.dart';
import 'extraction_isolate.dart';
import 'extraction_result.dart';
import 'html_fetcher.dart';
import 'html_sanitizer.dart';
import 'readability.dart';
import 'webview_extractor.dart';

/// Orchestrates the three extraction tiers described in the v3 plan.
///
/// * [ExtractionEngine.auto] - HTTP + readability, then the AMP page, then a
///   headless WebView. The first *good* result wins; otherwise the longest
///   partial result is returned.
/// * [ExtractionEngine.fast] - HTTP + AMP only, never spins up a WebView.
/// * [ExtractionEngine.browser] - WebView first, HTTP as the fallback.
class ArticleExtractor {
  ArticleExtractor({
    HtmlFetcher? fetcher,
    Readability? readability,
    WebviewExtractor? webview,
    bool? useIsolate,
  }) : _fetcher = fetcher,
       _readability = readability ?? const Readability(),
       _webview = webview,
       // Injected collaborators mean a test wants the in-process path.
       _useIsolate = useIsolate ?? (fetcher == null && readability == null);

  final HtmlFetcher? _fetcher;
  final Readability _readability;
  final WebviewExtractor? _webview;
  final bool _useIsolate;

  final Map<String, ExtractionResult> _memo = <String, ExtractionResult>{};

  /// Message of the most recent failure, per URL.
  final Map<String, String> _errors = <String, String>{};

  /// Result of the previous successful extraction for [url], if any.
  ExtractionResult? cached(String url) => _memo[url];

  /// Message describing why [url] could not be extracted.
  String? lastError(String url) => _errors[url];

  void clearCache() {
    _memo.clear();
    _errors.clear();
  }

  /// Extracts the readable body of [url].
  ///
  /// [rssHtml] is the HTML the feed itself shipped; it is used as the last
  /// resort when every tier fails. Throws [ExtractionException] when nothing
  /// at all could be produced and a network error explains why.
  Future<ExtractionResult?> extract(
    String url, {
    ExtractionEngine engine = ExtractionEngine.auto,
    String? rssHtml,
    bool force = false,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ExtractionException('This article has no link to open.');
    }

    if (!force) {
      final memo = _memo[trimmed];
      if (memo != null) return memo;
    }
    _errors.remove(trimmed);

    final partials = <ExtractionResult>[];
    String? failure;
    int? failureStatus;

    Future<ExtractionResult?> runHttp(String target, String source) async {
      try {
        final outcome = await _httpTier(target, source);
        if (outcome.error != null) {
          failure ??= outcome.error;
          failureStatus ??= outcome.statusCode;
        }
        final result = outcome.result;
        if (result != null) partials.add(result);
        return result;
      } catch (e) {
        failure ??= 'Could not load the article.';
        AppLog.w('HTTP extraction failed for $target', e);
        return null;
      }
    }

    Future<ExtractionResult?> runWebview() async {
      final webview = _webview;
      if (webview == null) return null;
      try {
        final result = await webview.extract(trimmed);
        if (result != null) partials.add(result);
        return result;
      } catch (e) {
        AppLog.w('WebView extraction failed for $trimmed', e);
        return null;
      }
    }

    if (engine == ExtractionEngine.browser) {
      final browser = await runWebview();
      if (browser != null && browser.isGood) return _remember(trimmed, browser);
      final http = await runHttp(trimmed, ExtractionSource.http);
      if (http != null && http.isGood) return _remember(trimmed, http);
    } else {
      final http = await runHttp(trimmed, ExtractionSource.http);
      if (http != null && http.isGood) return _remember(trimmed, http);

      final ampUrl = _lastAmpUrl;
      if (ampUrl != null && ampUrl != trimmed) {
        final amp = await runHttp(ampUrl, ExtractionSource.amp);
        if (amp != null && amp.isGood) return _remember(trimmed, amp);
      }

      if (engine == ExtractionEngine.auto) {
        final browser = await runWebview();
        if (browser != null && browser.isGood) {
          return _remember(trimmed, browser);
        }
      }
    }

    final rss = _rssResult(rssHtml, trimmed);
    if (rss != null) partials.add(rss);

    if (partials.isEmpty) {
      final message = failure ?? 'No readable content was found on this page.';
      _errors[trimmed] = message;
      throw ExtractionException(message, statusCode: failureStatus);
    }

    partials.sort((a, b) => b.wordCount.compareTo(a.wordCount));
    final best = partials.first;
    if (best.wordCount == 0) {
      final message = failure ?? 'No readable content was found on this page.';
      _errors[trimmed] = message;
      throw ExtractionException(message, statusCode: failureStatus);
    }
    return _remember(trimmed, best);
  }

  ExtractionResult _remember(String url, ExtractionResult result) {
    _memo[url] = result;
    _errors.remove(url);
    return result;
  }

  /// AMP URL discovered by the most recent HTTP tier run.
  String? _lastAmpUrl;

  Future<_HttpOutcome> _httpTier(String url, String source) async {
    if (_useIsolate) {
      final raw = await compute(fetchAndExtractIsolate, <String, dynamic>{
        'url': url,
        'source': source,
      });
      if (raw[ExtractionIsolateKeys.ok] != true) {
        return _HttpOutcome(
          error: raw[ExtractionIsolateKeys.error] as String?,
          statusCode: (raw[ExtractionIsolateKeys.statusCode] as num?)?.toInt(),
        );
      }
      _lastAmpUrl = raw[ExtractionIsolateKeys.ampUrl] as String?;
      final json = raw[ExtractionIsolateKeys.result];
      return _HttpOutcome(
        result: json is Map
            ? ExtractionResult.fromJson(json.cast<String, dynamic>())
            : null,
      );
    }

    final fetcher = _fetcher ?? HtmlFetcher();
    try {
      final page = await fetcher.fetch(url);
      _lastAmpUrl = page.ampUrl;
      final result = _readability.parse(
        page.html,
        page.finalUrl,
        source: source,
      );
      return _HttpOutcome(result: result);
    } on FetchException catch (e) {
      return _HttpOutcome(error: e.userMessage, statusCode: e.statusCode);
    }
  }

  /// Wraps the HTML the feed shipped so it can act as a fallback body.
  ExtractionResult? _rssResult(String? rssHtml, String url) {
    if (rssHtml == null || rssHtml.trim().isEmpty) return null;
    final html = HtmlSanitizer.sanitize(rssHtml, baseUrl: url);
    if (html.trim().isEmpty) return null;
    final text = HtmlSanitizer.toPlainText(html);
    if (text.trim().length < 200) return null;
    final words = text.trim().split(RegExp(r'\s+')).length;
    return ExtractionResult(
      html: html,
      text: text,
      excerpt: HtmlSanitizer.excerpt(html),
      wordCount: words,
      quality: words >= 400 ? 0.6 : 0.4,
      source: ExtractionSource.rss,
      partial: words < 400,
    );
  }
}

class _HttpOutcome {
  const _HttpOutcome({this.result, this.error, this.statusCode});

  final ExtractionResult? result;
  final String? error;
  final int? statusCode;
}
