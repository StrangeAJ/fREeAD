import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../utils/app_logger.dart';
import 'extraction_result.dart';
import 'html_sanitizer.dart';

/// Tier 3 of the extraction pipeline: render the page in a headless WebView
/// and run Mozilla's Readability.js inside it.
///
/// Used for JavaScript rendered pages and hosts that block plain HTTP clients.
/// Only meaningful on Android / iOS; every other platform returns null.
/// All plugin calls are wrapped in try/catch so unit tests on the host never
/// blow up.
class WebviewExtractor {
  WebviewExtractor();

  static const String _readabilityAsset = 'assets/js/Readability.js';
  static const Duration _overallTimeout = Duration(seconds: 25);
  static const Duration _stabilisePoll = Duration(milliseconds: 400);
  static const int _maxStabilisePolls = 15; // ~6 s

  String? _readabilityJs;

  /// Single-flight queue: WebViews are expensive, run one at a time.
  Future<void> _queue = Future<void>.value();

  /// True when a headless WebView can be created on this platform.
  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Extracts [url] using a headless WebView, or returns null when the
  /// platform is unsupported or the page yields nothing usable.
  Future<ExtractionResult?> extract(String url) {
    if (!isSupported) return Future<ExtractionResult?>.value();

    final completer = Completer<ExtractionResult?>();
    _queue = _queue
        .then((_) async {
          try {
            final result = await _run(url).timeout(_overallTimeout);
            if (!completer.isCompleted) completer.complete(result);
          } catch (e) {
            AppLog.w('WebView extraction failed for $url', e);
            if (!completer.isCompleted) completer.complete(null);
          }
        })
        .catchError((Object _) {
          if (!completer.isCompleted) completer.complete(null);
        });
    return completer.future;
  }

  Future<ExtractionResult?> _run(String url) async {
    final script = await _loadReadability();
    if (script == null) return null;

    HeadlessInAppWebView? headless;
    final loaded = Completer<void>();

    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          blockNetworkImage: true,
          mediaPlaybackRequiresUserGesture: true,
          transparentBackground: true,
          userAgent: _mobileUserAgent,
          cacheEnabled: false,
          incognito: true,
        ),
        onLoadStop: (controller, uri) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onReceivedError: (controller, request, error) {
          if (!loaded.isCompleted) {
            loaded.completeError(
              ExtractionException('The page could not be rendered.'),
            );
          }
        },
      );

      await headless.run();
      await loaded.future.timeout(const Duration(seconds: 15));

      final controller = headless.webViewController;
      if (controller == null) return null;

      await _waitForStableBody(controller);

      await controller.evaluateJavascript(source: script);
      final raw = await controller.evaluateJavascript(
        source: '''
(function () {
  try {
    var docClone = document.cloneNode(true);
    var article = new Readability(docClone).parse();
    if (!article) return null;
    return JSON.stringify({
      title: article.title,
      byline: article.byline,
      siteName: article.siteName,
      excerpt: article.excerpt,
      content: article.content,
      textContent: article.textContent,
      length: article.length
    });
  } catch (e) {
    return null;
  }
})();
''',
      );

      final parsed = _decode(raw);
      if (parsed == null) return null;

      final html = HtmlSanitizer.sanitize(
        parsed['content'] as String? ?? '',
        baseUrl: url,
      );
      if (html.trim().isEmpty) return null;

      final text = HtmlSanitizer.toPlainText(html);
      final words = text.trim().isEmpty
          ? 0
          : text.trim().split(RegExp(r'\s+')).length;

      return ExtractionResult(
        html: html,
        text: text,
        title: _string(parsed['title']),
        author: _string(parsed['byline']),
        siteName: _string(parsed['siteName']),
        excerpt: _string(parsed['excerpt']) ?? HtmlSanitizer.excerpt(html),
        leadImageUrl: null,
        publishedAt: null,
        wordCount: words,
        // Readability.js only returns a result when it is confident.
        quality: words >= 150 ? 0.8 : 0.35,
        source: ExtractionSource.webview,
        partial: words < 150,
      );
    } catch (e) {
      AppLog.w('Headless WebView error for $url', e);
      return null;
    } finally {
      try {
        await headless?.dispose();
      } catch (_) {
        // Already disposed.
      }
    }
  }

  /// Polls `document.body.innerText.length` until it stops growing.
  Future<void> _waitForStableBody(InAppWebViewController controller) async {
    var previous = -1;
    var stable = 0;
    for (var i = 0; i < _maxStabilisePolls; i++) {
      await Future<void>.delayed(_stabilisePoll);
      int length;
      try {
        final value = await controller.evaluateJavascript(
          source: '(document.body && document.body.innerText.length) || 0',
        );
        length = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      } catch (_) {
        return;
      }
      if (length == previous && length > 0) {
        stable++;
        if (stable >= 2) return;
      } else {
        stable = 0;
      }
      previous = length;
    }
  }

  Future<String?> _loadReadability() async {
    if (_readabilityJs != null) return _readabilityJs;
    try {
      _readabilityJs = await rootBundle.loadString(_readabilityAsset);
      return _readabilityJs;
    } catch (e) {
      AppLog.w('Could not load $_readabilityAsset', e);
      return null;
    }
  }

  static Map<String, dynamic>? _decode(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) return raw.cast<String, dynamic>();
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      if (decoded is String) {
        final nested = jsonDecode(decoded);
        if (nested is Map) return nested.cast<String, dynamic>();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static const String _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
}
