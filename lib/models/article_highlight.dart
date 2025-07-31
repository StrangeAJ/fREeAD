class ArticleHighlight {
  final String id;
  final String articleId;
  final String selectedText;
  final int startIndex;
  final int endIndex;
  final String color; // Color hex code for the highlight
  final String? note; // Optional note attached to the highlight
  final DateTime createdAt;
  final DateTime updatedAt;

  ArticleHighlight({
    required this.id,
    required this.articleId,
    required this.selectedText,
    required this.startIndex,
    required this.endIndex,
    required this.color,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ArticleHighlight.fromJson(Map<String, dynamic> json) {
    return ArticleHighlight(
      id: json['id'],
      articleId: json['articleId'],
      selectedText: json['selectedText'],
      startIndex: json['startIndex'],
      endIndex: json['endIndex'],
      color: json['color'],
      note: json['note'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'articleId': articleId,
      'selectedText': selectedText,
      'startIndex': startIndex,
      'endIndex': endIndex,
      'color': color,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ArticleHighlight copyWith({
    String? id,
    String? articleId,
    String? selectedText,
    int? startIndex,
    int? endIndex,
    String? color,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ArticleHighlight(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      selectedText: selectedText ?? this.selectedText,
      startIndex: startIndex ?? this.startIndex,
      endIndex: endIndex ?? this.endIndex,
      color: color ?? this.color,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArticleHighlight && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
