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
  });

  factory RSSFeed.fromJson(Map<String, dynamic> json) {
    return RSSFeed(
      id: json['id'],
      title: json['title'],
      url: json['url'],
      description: json['description'],
      imageUrl: json['imageUrl'],
      categoryId: json['categoryId'],
      dateAdded: DateTime.parse(json['dateAdded']),
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.parse(json['lastUpdated']) 
          : null,
      isActive: json['isActive'] is int ? json['isActive'] == 1 : (json['isActive'] ?? true),
    );
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
      'isActive': isActive,
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
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RSSFeed && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'RSSFeed(id: $id, title: $title, url: $url)';
  }
}
