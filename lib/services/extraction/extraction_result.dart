/// Where an [ExtractionResult] came from.
class ExtractionSource {
  static const String rss = 'rss';
  static const String http = 'http';
  static const String amp = 'amp';
  static const String webview = 'webview';
}

/// Outcome of an article extraction attempt.
///
/// Pure data with `toJson`/`fromJson` so it can cross an isolate boundary.
class ExtractionResult {
  const ExtractionResult({
    required this.html,
    required this.text,
    required this.wordCount,
    required this.quality,
    required this.source,
    this.title,
    this.author,
    this.siteName,
    this.excerpt,
    this.leadImageUrl,
    this.publishedAt,
    this.partial = false,
  });

  /// Sanitised article body as HTML.
  final String html;

  /// Plain text projection of [html].
  final String text;

  final String? title;
  final String? author;
  final String? siteName;
  final String? excerpt;
  final String? leadImageUrl;

  /// Publication timestamp as reported by the page, ISO 8601 when available.
  final String? publishedAt;

  final int wordCount;

  /// Confidence that [html] is the real article body, 0.0 - 1.0.
  final double quality;

  /// One of [ExtractionSource].
  final String source;

  /// True when the page only yielded a teaser (paywall, JS-only page, ...).
  final bool partial;

  /// Good enough to replace the RSS excerpt without asking the user.
  bool get isGood => quality >= 0.55 && wordCount >= 150;

  ExtractionResult copyWith({
    String? html,
    String? text,
    String? title,
    String? author,
    String? siteName,
    String? excerpt,
    String? leadImageUrl,
    String? publishedAt,
    int? wordCount,
    double? quality,
    String? source,
    bool? partial,
  }) {
    return ExtractionResult(
      html: html ?? this.html,
      text: text ?? this.text,
      title: title ?? this.title,
      author: author ?? this.author,
      siteName: siteName ?? this.siteName,
      excerpt: excerpt ?? this.excerpt,
      leadImageUrl: leadImageUrl ?? this.leadImageUrl,
      publishedAt: publishedAt ?? this.publishedAt,
      wordCount: wordCount ?? this.wordCount,
      quality: quality ?? this.quality,
      source: source ?? this.source,
      partial: partial ?? this.partial,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'html': html,
    'text': text,
    'title': title,
    'author': author,
    'siteName': siteName,
    'excerpt': excerpt,
    'leadImageUrl': leadImageUrl,
    'publishedAt': publishedAt,
    'wordCount': wordCount,
    'quality': quality,
    'source': source,
    'partial': partial,
  };

  factory ExtractionResult.fromJson(Map<String, dynamic> json) {
    return ExtractionResult(
      html: json['html'] as String? ?? '',
      text: json['text'] as String? ?? '',
      title: json['title'] as String?,
      author: json['author'] as String?,
      siteName: json['siteName'] as String?,
      excerpt: json['excerpt'] as String?,
      leadImageUrl: json['leadImageUrl'] as String?,
      publishedAt: json['publishedAt'] as String?,
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
      quality: (json['quality'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String? ?? ExtractionSource.http,
      partial: json['partial'] == true,
    );
  }

  @override
  String toString() =>
      'ExtractionResult(source: $source, words: $wordCount, '
      'quality: ${quality.toStringAsFixed(2)}, partial: $partial)';
}

/// Failure that already carries a message safe to show to the user.
class ExtractionException implements Exception {
  ExtractionException(this.userMessage, {this.statusCode});

  final String userMessage;
  final int? statusCode;

  @override
  String toString() => 'ExtractionException($userMessage, $statusCode)';
}
