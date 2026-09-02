class RSSFeed {
  final String id;
  final String title;
  final String url;
  final String description;
  final String? imageUrl;
  final String? categoryId;
  final DateTime dateAdded;
  final DateTime? lastUpdated;
  final bool isActive;

  /// Canonical website for the feed (channel `link` / atom `rel=alternate`).
  final String? siteUrl;

  /// Last time a refresh actually completed for this feed.
  final DateTime? lastFetchedAt;

  /// Friendly message for the last refresh failure, null when healthy.
  final String? lastError;

  /// Feed language tag, e.g. `en-US`.
  final String? language;

  RSSFeed({
    required this.id,
    required this.title,
    required this.url,
    required this.description,
    this.imageUrl,
    this.categoryId,
    required this.dateAdded,
    this.lastUpdated,
    this.isActive = true,
    this.siteUrl,
    this.lastFetchedAt,
    this.lastError,
    this.language,
  });

  String? get iconUrl => imageUrl;

  factory RSSFeed.fromJson(Map<String, dynamic> json) {
    return RSSFeed(
      id: json['id'],
      title: json['title'],
      url: json['url'],
      description: json['description'],
      imageUrl: json['imageUrl'],
      categoryId: json['categoryId'],
      dateAdded: DateTime.parse(json['dateAdded']),
      lastUpdated: _parseDate(json['lastUpdated']),
      isActive: json['isActive'] is int
          ? json['isActive'] == 1
          : (json['isActive'] ?? true),
      siteUrl: json['siteUrl'],
      lastFetchedAt: _parseDate(json['lastFetchedAt']),
      lastError: json['lastError'],
      language: json['language'],
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
      'url': url,
      'description': description,
      'imageUrl': imageUrl,
      'categoryId': categoryId,
      'dateAdded': dateAdded.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
      'isActive': isActive ? 1 : 0,
      'siteUrl': siteUrl,
      'lastFetchedAt': lastFetchedAt?.toIso8601String(),
      'lastError': lastError,
      'language': language,
    };
  }

  RSSFeed copyWith({
    String? id,
    String? title,
    String? url,
    String? description,
    String? imageUrl,
    String? categoryId,
    DateTime? dateAdded,
    DateTime? lastUpdated,
    bool? isActive,
    String? siteUrl,
    DateTime? lastFetchedAt,
    String? lastError,
    String? language,
    bool clearError = false,
  }) {
    return RSSFeed(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      categoryId: categoryId ?? this.categoryId,
      dateAdded: dateAdded ?? this.dateAdded,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isActive: isActive ?? this.isActive,
      siteUrl: siteUrl ?? this.siteUrl,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      language: language ?? this.language,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RSSFeed && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  /// Unread article count for this feed (populated by FeedProvider).
  int unreadCount = 0;

  @override
  String toString() {
    return 'RSSFeed(id: $id, title: $title, url: $url)';
  }
}
