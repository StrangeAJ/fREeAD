/// A user-saved Ask AI prompt.
///
/// Stored as JSON inside SharedPreferences (see
/// `SettingsProvider.savedPromptsKey`) - no database table needed.
class SavedPrompt {
  const SavedPrompt({
    required this.id,
    required this.title,
    required this.prompt,
    required this.createdAt,
  });

  /// Stable id, `DateTime.now().microsecondsSinceEpoch` at creation.
  final String id;

  /// Short label shown on the prompt chip/row.
  final String title;

  /// The full prompt text sent to the chat.
  final String prompt;

  final DateTime createdAt;

  factory SavedPrompt.fromJson(Map<String, dynamic> json) {
    return SavedPrompt(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'prompt': prompt,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  SavedPrompt copyWith({String? title, String? prompt}) {
    return SavedPrompt(
      id: id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SavedPrompt && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SavedPrompt(id: $id, title: $title)';
}
