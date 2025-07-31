class ArticleNote {
  final String id;
  final String articleId;
  final String content;
  final int? position; // Position in the article where the note is attached
  final String? highlightId; // Reference to highlight if note is attached to a highlight
  final DateTime createdAt;
  final DateTime updatedAt;

  ArticleNote({
    required this.id,
    required this.articleId,
    required this.content,
    this.position,
    this.highlightId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ArticleNote.fromJson(Map<String, dynamic> json) {
    return ArticleNote(
      id: json['id'],
      articleId: json['articleId'],
      content: json['content'],
      position: json['position'],
      highlightId: json['highlightId'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'articleId': articleId,
      'content': content,
      'position': position,
      'highlightId': highlightId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ArticleNote copyWith({
    String? id,
    String? articleId,
    String? content,
    int? position,
    String? highlightId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ArticleNote(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      content: content ?? this.content,
      position: position ?? this.position,
      highlightId: highlightId ?? this.highlightId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArticleNote && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
