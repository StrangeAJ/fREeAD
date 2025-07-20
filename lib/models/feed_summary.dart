class FeedSummary {
  final String id;
  final String feedId;
  final String summary;
  final DateTime createdAt;
  final DateTime updatedAt;

  FeedSummary({
    required this.id,
    required this.feedId,
    required this.summary,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FeedSummary.fromJson(Map<String, dynamic> json) {
    return FeedSummary(
      id: json['id'],
      feedId: json['feedId'],
      summary: json['summary'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'feedId': feedId,
      'summary': summary,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  FeedSummary copyWith({
    String? id,
    String? feedId,
    String? summary,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FeedSummary(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper method to get readable time ago
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(updatedAt);

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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeedSummary && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'FeedSummary(id: $id, feedId: $feedId, createdAt: $createdAt)';
  }
}
