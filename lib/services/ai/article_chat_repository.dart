import '../../models/chat_message.dart';
import '../../utils/app_logger.dart';
import '../database_service.dart';

/// Persistence for the per-article "Ask AI" conversation (`article_chats`).
class ArticleChatRepository {
  ArticleChatRepository({DatabaseService? database})
    : _db = database ?? DatabaseService();

  final DatabaseService _db;

  /// Messages for [articleId], oldest first. Never throws.
  Future<List<ChatMessage>> load(String articleId) async {
    try {
      return await _db.getArticleChat(articleId);
    } catch (e, st) {
      AppLog.e('Could not load chat for $articleId', e, st);
      return const [];
    }
  }

  /// Stores [message]. Returns false when persistence failed.
  Future<bool> appendMessage(ChatMessage message) async {
    try {
      await _db.insertChatMessage(message);
      return true;
    } catch (e, st) {
      AppLog.e('Could not persist chat message ${message.id}', e, st);
      return false;
    }
  }

  /// Builds a [ChatMessage] with a unique id and stores it.
  Future<ChatMessage> append(
    String articleId,
    String role,
    String content, {
    DateTime? createdAt,
  }) async {
    final message = newMessage(articleId, role, content, createdAt: createdAt);
    await appendMessage(message);
    return message;
  }

  /// Replaces the whole conversation for [articleId].
  Future<void> replaceAll(String articleId, List<ChatMessage> messages) async {
    try {
      await _db.deleteArticleChat(articleId);
      for (final message in messages) {
        await _db.insertChatMessage(message);
      }
    } catch (e, st) {
      AppLog.e('Could not replace chat for $articleId', e, st);
    }
  }

  /// Deletes every message for [articleId].
  Future<void> clear(String articleId) async {
    try {
      await _db.deleteArticleChat(articleId);
    } catch (e, st) {
      AppLog.e('Could not clear chat for $articleId', e, st);
    }
  }

  /// Creates an unsaved [ChatMessage] with a collision-resistant id.
  static ChatMessage newMessage(
    String articleId,
    String role,
    String content, {
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return ChatMessage(
      id: '${articleId}_${now.microsecondsSinceEpoch}_$role',
      articleId: articleId,
      role: role,
      content: content,
      createdAt: now,
    );
  }
}
