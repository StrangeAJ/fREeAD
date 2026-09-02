import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

/// A page that was fetched and decoded successfully.
class FetchedPage {
  const FetchedPage({
    required this.finalUrl,
    required this.statusCode,
    required this.html,
    this.ampUrl,
    this.canonicalUrl,
  });

  final String finalUrl;
  final int statusCode;
  final String html;

  /// `<link rel="amphtml">` target, if the page advertises one.
  final String? ampUrl;

  /// `<link rel="canonical">` target, if present.
  final String? canonicalUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'finalUrl': finalUrl,
    'statusCode': statusCode,
    'html': html,
    'ampUrl': ampUrl,
    'canonicalUrl': canonicalUrl,
  };

  factory FetchedPage.fromJson(Map<String, dynamic> json) => FetchedPage(
    finalUrl: json['finalUrl'] as String? ?? '',
    statusCode: (json['statusCode'] as num?)?.toInt() ?? 0,
    html: json['html'] as String? ?? '',
    ampUrl: json['ampUrl'] as String?,
    canonicalUrl: json['canonicalUrl'] as String?,
  );
}

/// A fetch failure with a message that is safe to show to the user.
class FetchException implements Exception {
  FetchException(this.userMessage, {this.statusCode});

  final String userMessage;
  final int? statusCode;

  @override
  String toString() => 'FetchException($statusCode): $userMessage';
}

/// Fetches article pages with browser-like headers, redirect following,
/// charset detection and a mobile retry for hosts that block desktop agents.
class HtmlFetcher {
  HtmlFetcher({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      responseType: ResponseType.bytes,
      followRedirects: true,
      maxRedirects: 8,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
    );
  }

  final Dio _dio;

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const String acceptHeader =
      'text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/avif,image/webp,*/*;q=0.8';

  /// Fetches [url]; retries once with a mobile UA + Referer on 403/429/503.
  Future<FetchedPage> fetch(String url, {bool mobileUa = false}) async {
    try {
      return await _fetchOnce(url, mobileUa: mobileUa);
    } on FetchException catch (e) {
      final retryable =
          e.statusCode == 403 || e.statusCode == 429 || e.statusCode == 503;
      if (!retryable || mobileUa) rethrow;
      return _fetchOnce(url, mobileUa: true, withReferer: true);
    }
  }

  Future<FetchedPage> _fetchOnce(
    String url, {
    required bool mobileUa,
    bool withReferer = false,
  }) async {
    final headers = <String, String>{
      'User-Agent': mobileUa ? mobileUserAgent : desktopUserAgent,
      'Accept': acceptHeader,
      'Accept-Language': 'en-US,en;q=0.8',
      'Cache-Control': 'no-cache',
      if (withReferer) 'Referer': 'https://www.google.com/',
    };

    Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw FetchException(_dioMessage(e), statusCode: e.response?.statusCode);
    } catch (e) {
      throw FetchException('Could not load the page: $e');
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw FetchException(_statusMessage(status), statusCode: status);
    }

    final bytes = _asBytes(response.data);
    if (bytes.isEmpty) {
      throw FetchException('The page was empty.', statusCode: status);
    }

    final contentType = _headerValue(response, 'content-type');
    final html = decodeBody(bytes, contentType: contentType);
    final finalUrl = response.realUri.toString();
    final links = _extractLinks(html, finalUrl);

    return FetchedPage(
      finalUrl: finalUrl,
      statusCode: status,
      html: html,
      ampUrl: links.amp,
      canonicalUrl: links.canonical,
    );
  }

  void dispose() => _dio.close(force: true);

  // -------------------------------------------------------------------------
  // Decoding
  // -------------------------------------------------------------------------

  /// Decodes [bytes] using, in order: the `Content-Type` charset, the BOM,
  /// a `<meta charset>` declaration, then UTF-8 (malformed allowed) and
  /// finally latin-1.
  static String decodeBody(List<int> bytes, {String? contentType}) {
    final bom = _charsetFromBom(bytes);
    if (bom != null) return _decodeWith(bom, bytes);

    final header = _charsetFromContentType(contentType);
    if (header != null) return _decodeWith(header, bytes);

    // Sniff the first 2 KB as latin-1 to find a meta charset declaration.
    final head = latin1.decode(
      bytes.take(2048).map((b) => b & 0xFF).toList(growable: false),
      allowInvalid: true,
    );
    final meta = _charsetFromMeta(head);
    if (meta != null) return _decodeWith(meta, bytes);

    return _decodeWith('utf-8', bytes);
  }

  static String _decodeWith(String charset, List<int> bytes) {
    final name = charset.toLowerCase().replaceAll('_', '-');
    var data = bytes;
    // Strip a UTF-8 BOM, which utf8.decode would otherwise keep as U+FEFF.
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
    }
    switch (name) {
      case 'utf-8':
      case 'utf8':
      case 'ascii':
      case 'us-ascii':
        return utf8.decode(data, allowMalformed: true);
      case 'iso-8859-1':
      case 'latin1':
      case 'latin-1':
      case 'windows-1252':
      case 'cp1252':
      case 'iso-8859-15':
        return latin1.decode(
          data.map((b) => b & 0xFF).toList(growable: false),
          allowInvalid: true,
        );
      default:
        // Unknown charset (shift_jis, gb2312, ...): UTF-8 is the best guess
        // and never throws with allowMalformed.
        return utf8.decode(data, allowMalformed: true);
    }
  }

  static String? _charsetFromBom(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 'utf-8';
    }
    return null;
  }

  static String? _charsetFromContentType(String? contentType) {
    if (contentType == null) return null;
    final match = RegExp(
      r'charset\s*=\s*"?([\w-]+)"?',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(1);
  }

  static String? _charsetFromMeta(String head) {
    final direct = RegExp(
      r'''<meta[^>]+charset\s*=\s*["']?\s*([\w-]+)''',
      caseSensitive: false,
    ).firstMatch(head);
    if (direct != null) return direct.group(1);

    final httpEquiv = RegExp(
      r'''<meta[^>]+http-equiv\s*=\s*["']?content-type["']?[^>]+'''
      r'''content\s*=\s*["'][^"']*charset\s*=\s*([\w-]+)''',
      caseSensitive: false,
    ).firstMatch(head);
    return httpEquiv?.group(1);
  }

  static List<int> _asBytes(dynamic data) {
    if (data == null) return const <int>[];
    if (data is Uint8List) return data;
    if (data is List<int>) return data;
    if (data is String) return utf8.encode(data);
    if (data is List) return data.cast<int>();
    return const <int>[];
  }

  static String? _headerValue(Response<dynamic> response, String name) {
    try {
      return response.headers.value(name);
    } catch (_) {
      return null;
    }
  }

  static _PageLinks _extractLinks(String html, String baseUrl) {
    String? amp;
    String? canonical;
    try {
      final document = html_parser.parse(html);
      final base = Uri.tryParse(baseUrl);
      String? resolve(String? href) {
        if (href == null || href.trim().isEmpty) return null;
        final value = href.trim();
        if (base == null || !base.hasScheme) return value;
        try {
          return base.resolve(value).toString();
        } catch (_) {
          return value;
        }
      }

      amp = resolve(
        document.querySelector('link[rel="amphtml"]')?.attributes['href'],
      );
      canonical = resolve(
        document.querySelector('link[rel="canonical"]')?.attributes['href'],
      );
    } catch (_) {
      // Malformed head - links are optional.
    }
    return _PageLinks(amp, canonical);
  }

  // -------------------------------------------------------------------------
  // Error messages
  // -------------------------------------------------------------------------

  static String _statusMessage(int status) {
    switch (status) {
      case 401:
        return 'The article requires signing in (HTTP 401).';
      case 402:
      case 403:
        return 'The site blocked automated access (HTTP $status).';
      case 404:
      case 410:
        return 'The article page was not found (HTTP $status).';
      case 429:
        return 'The site is rate limiting requests (HTTP 429). '
            'Try again in a moment.';
      default:
        if (status >= 500) {
          return 'The site returned a server error (HTTP $status).';
        }
        return 'The site returned an unexpected response (HTTP $status).';
    }
  }

  static String _dioMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The site took too long to respond.';
      case DioExceptionType.badCertificate:
        return 'The site has an invalid security certificate.';
      case DioExceptionType.connectionError:
        return 'Could not reach the site. Check your connection.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badResponse:
        return _statusMessage(e.response?.statusCode ?? 0);
      case DioExceptionType.unknown:
        return 'Could not load the page.';
    }
  }
}

class _PageLinks {
  const _PageLinks(this.amp, this.canonical);

  final String? amp;
  final String? canonical;
}
