import 'package:html/parser.dart' as html_parser;

/// Where the cached [Article.fullContent] came from.
class FullContentSource {
  static const String rss = 'rss';
  static const String http = 'http';
  static const String amp = 'amp';
  static const String webview = 'webview';
}

class Article {
  final String id;
  final String title;
  final String description;
  final String? content;

  /// Full article body (sanitized HTML) fetched by the extraction pipeline.
  final String? fullContent;

  /// AI-generated summary.
  final String? summary;
  final String? imageUrl;
  final String url;
  final String? author;
  final DateTime publishedDate;
  final String feedId;
  final String? categoryId;
  final bool isRead;
  final bool isSaved;
  final bool isStarred;
  final DateTime dateAdded;

  /// Title reported by the extractor (may be better than the RSS title).
  final String? extractedTitle;

  /// Human readable site name reported by the extractor.
  final String? siteName;

  /// One of [FullContentSource] - 'rss' | 'http' | 'amp' | 'webview'.
  final String? fullContentSource;

  /// When [fullContent] was fetched.
  final DateTime? fullContentFetchedAt;

  /// Reading position, 0.0 - 1.0.
  final double scrollProgress;

  /// When the article was first marked as read.
  final DateTime? readAt;

  Article({
    required this.id,
    required this.title,
    required this.description,
    this.content,
    this.fullContent,
    this.summary,
    this.imageUrl,
    required this.url,
    this.author,
    required this.publishedDate,
    required this.feedId,
    this.categoryId,
    this.isRead = false,
    this.isSaved = false,
    this.isStarred = false,
    required this.dateAdded,
    this.extractedTitle,
    this.siteName,
    this.fullContentSource,
    this.fullContentFetchedAt,
    this.scrollProgress = 0,
    this.readAt,
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      content: json['content'],
      fullContent: json['fullContent'],
      summary: json['summary'],
      imageUrl: json['imageUrl'],
      url: json['url'],
      author: json['author'],
      publishedDate: DateTime.parse(json['publishedDate']),
      feedId: json['feedId'],
      categoryId: json['categoryId'],
      isRead: json['isRead'] is int
          ? json['isRead'] == 1
          : (json['isRead'] ?? false),
      isSaved: json['isSaved'] is int
          ? json['isSaved'] == 1
          : (json['isSaved'] ?? false),
      isStarred: json['isStarred'] is int
          ? json['isStarred'] == 1
          : (json['isStarred'] ?? false),
      dateAdded: DateTime.parse(json['dateAdded']),
      extractedTitle: json['extractedTitle'],
      siteName: json['siteName'],
      fullContentSource: json['fullContentSource'],
      fullContentFetchedAt: _parseDate(json['fullContentFetchedAt']),
      scrollProgress: (json['scrollProgress'] as num?)?.toDouble() ?? 0,
      readAt: _parseDate(json['readAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final text = value.toString();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'content': content,
      'fullContent': fullContent,
      'summary': summary,
      'imageUrl': imageUrl,
      'url': url,
      'author': author,
      'publishedDate': publishedDate.toIso8601String(),
      'feedId': feedId,
      'categoryId': categoryId,
      'isRead': isRead ? 1 : 0,
      'isSaved': isSaved ? 1 : 0,
      'isStarred': isStarred ? 1 : 0,
      'dateAdded': dateAdded.toIso8601String(),
      'extractedTitle': extractedTitle,
      'siteName': siteName,
      'fullContentSource': fullContentSource,
      'fullContentFetchedAt': fullContentFetchedAt?.toIso8601String(),
      'scrollProgress': scrollProgress,
      'readAt': readAt?.toIso8601String(),
    };
  }

  /// [clearFullContent]/[clearSummary]/[clearReadAt] allow nulling out fields
  /// that the normal `?? this.x` pattern cannot clear.
  Article copyWith({
    String? id,
    String? title,
    String? description,
    String? content,
    String? fullContent,
    String? summary,
    String? imageUrl,
    String? url,
    String? author,
    DateTime? publishedDate,
    String? feedId,
    String? categoryId,
    bool? isRead,
    bool? isSaved,
    bool? isStarred,
    DateTime? dateAdded,
    String? extractedTitle,
    String? siteName,
    String? fullContentSource,
    DateTime? fullContentFetchedAt,
    double? scrollProgress,
    DateTime? readAt,
    bool clearFullContent = false,
    bool clearSummary = false,
    bool clearReadAt = false,
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      content: content ?? this.content,
      fullContent: clearFullContent ? null : (fullContent ?? this.fullContent),
      summary: clearSummary ? null : (summary ?? this.summary),
      imageUrl: imageUrl ?? this.imageUrl,
      url: url ?? this.url,
      author: author ?? this.author,
      publishedDate: publishedDate ?? this.publishedDate,
      feedId: feedId ?? this.feedId,
      categoryId: categoryId ?? this.categoryId,
      isRead: isRead ?? this.isRead,
      isSaved: isSaved ?? this.isSaved,
      isStarred: isStarred ?? this.isStarred,
      dateAdded: dateAdded ?? this.dateAdded,
      extractedTitle: extractedTitle ?? this.extractedTitle,
      siteName: siteName ?? this.siteName,
      fullContentSource: clearFullContent
          ? null
          : (fullContentSource ?? this.fullContentSource),
      fullContentFetchedAt: clearFullContent
          ? null
          : (fullContentFetchedAt ?? this.fullContentFetchedAt),
      scrollProgress: scrollProgress ?? this.scrollProgress,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Article && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Article(id: $id, title: $title, url: $url)';
  }

  /// True when the extraction pipeline has cached a body for this article.
  bool get hasFullContent =>
      fullContent != null && fullContent!.trim().isNotEmpty;

  /// Best available body, HTML or plain text.
  String? get bestContent {
    if (hasFullContent) return fullContent;
    if (content != null && content!.trim().isNotEmpty) return content;
    if (description.trim().isNotEmpty) return description;
    return null;
  }

  /// Plain text of the best available body, tags stripped.
  String get plainText => stripHtml(bestContent ?? '');

  int get wordCount {
    final text = plainText.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  /// Estimated reading time in minutes (220 wpm, minimum 1).
  int get readingMinutes {
    final minutes = (wordCount / 220).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  /// True when the feed itself shipped a substantial body, so no fetch is
  /// needed to read the article comfortably.
  bool get isRssContentSubstantial {
    final raw = content;
    if (raw == null || raw.trim().isEmpty) return false;
    return stripHtml(raw).length >= 1200;
  }

  /// Strips HTML tags/entities from [input] using the `html` package.
  static String stripHtml(String input) {
    if (input.trim().isEmpty) return '';
    try {
      final document = html_parser.parseFragment(input);
      final text = document.text ?? '';
      return text.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ').trim();
    } catch (_) {
      return input.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    }
  }

  // Helper method to get readable time ago
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(publishedDate);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} year${difference.inDays >= 730 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${difference.inDays >= 60 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}
