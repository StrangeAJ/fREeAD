class Article {
  final String id;
  final String title;
  final String description;
  final String? content;
  final String? fullContent; // New field for full article content
  final String? summary; // AI-generated summary
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
      isRead: json['isRead'] is int ? json['isRead'] == 1 : (json['isRead'] ?? false),
      isSaved: json['isSaved'] is int ? json['isSaved'] == 1 : (json['isSaved'] ?? false),
      isStarred: json['isStarred'] is int ? json['isStarred'] == 1 : (json['isStarred'] ?? false),
      dateAdded: DateTime.parse(json['dateAdded']),
    );
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
    };
  }

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
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      content: content ?? this.content,
      fullContent: fullContent ?? this.fullContent,
      summary: summary ?? this.summary,
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
