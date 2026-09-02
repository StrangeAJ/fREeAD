import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../models/chat_message.dart';
import '../services/ai/ai_models.dart';
import '../services/ai/ai_service.dart';
import '../services/ai/article_chat_repository.dart';
import '../utils/app_logger.dart';

/// Drives the "Ask AI about this article" conversation for one article.
///
/// Created per reader screen. The conversation is persisted in `article_chats`
/// so reopening the article restores it.
class AiChatProvider extends ChangeNotifier {
  AiChatProvider({
    required this.article,
    required AiService ai,
    ArticleChatRepository? repo,
  }) : _ai = ai,
       _repo = repo ?? ArticleChatRepository();

  /// The article the conversation is about.
  final Article article;

  final AiService _ai;
  final ArticleChatRepository _repo;

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isStreaming = false;
  String _partialResponse = '';
  String? _error;
  bool _loaded = false;
  bool _disposed = false;
  CancelToken? _cancelToken;
  String _providerLabel = '';
  String _model = '';
  String? _articleTextCache;

  /// Prompts offered when the conversation is empty.
  static const List<String> suggestedPrompts = <String>[
    'Summarize in 3 bullets',
    "Explain like I'm 12",
    'Key claims and evidence',
    'Counterarguments',
    'Action items',
    'Glossary of terms',
  ];

  // --- state -----------------------------------------------------------------

  /// Stored conversation, oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// True while a reply is streaming in.
  bool get isStreaming => _isStreaming;

  /// Text received so far for the in-flight reply ('' when idle).
  String get partialResponse => _partialResponse;

  /// User-safe error from the last attempt, or null.
  String? get error => _error;

  /// True once [load] has finished.
  bool get isLoaded => _loaded;

  /// True when nothing has been said yet and nothing is streaming.
  bool get isEmpty => _messages.isEmpty && _partialResponse.isEmpty;

  /// Display name of the configured provider, e.g. `Claude`.
  String get providerLabel => _providerLabel;

  /// Configured model id, e.g. `claude-opus-5`.
  String get model => _model;

  /// "Full article - 2,340 words" / "RSS excerpt - 180 words".
  String get contextInfo {
    final words = _wordCount(_articleText);
    final String label;
    if (article.hasFullContent) {
      label = 'Full article';
    } else if (words > 0) {
      label = 'RSS excerpt';
    } else {
      label = 'Headline only';
    }
    return '$label - ${_formatCount(words)} words';
  }

  /// System prompt sent with every turn.
  String get systemPrompt {
    final buffer = StringBuffer()
      ..writeln(
        'You are a reading assistant inside an RSS reader. Answer using the '
        'article below; if the answer is not in the article say so. Be '
        'concise. Use Markdown.',
      )
      ..writeln()
      ..writeln('Title: ${article.title}');
    final site = article.siteName;
    if (site != null && site.trim().isNotEmpty) {
      buffer.writeln('Site: $site');
    }
    if (article.url.trim().isNotEmpty) {
      buffer.writeln('URL: ${article.url}');
    }
    buffer
      ..writeln()
      ..writeln('---')
      ..writeln(truncateForModel(_articleText));
    return buffer.toString();
  }

  // --- actions ---------------------------------------------------------------

  /// Loads the stored conversation and the current provider/model labels.
  Future<void> load() async {
    final stored = await _repo.load(article.id);
    _messages
      ..clear()
      ..addAll(stored);
    await _refreshConfigInfo();
    _loaded = true;
    _safeNotify();
  }

  /// Sends [userText] and streams the reply.
  Future<void> send(String userText) async {
    final text = userText.trim();
    if (text.isEmpty || _isStreaming) return;

    _error = null;
    final message = ArticleChatRepository.newMessage(
      article.id,
      ChatRole.user,
      text,
    );
    _messages.add(message);
    _safeNotify();
    await _repo.appendMessage(message);
    await _runCompletion();
  }

  /// Cancels the in-flight reply. Whatever arrived so far is kept.
  void stop() {
    if (!_isStreaming) return;
    _cancelToken?.cancel('Stopped by the user');
  }

  /// Drops the last assistant reply and asks again.
  Future<void> regenerateLast() async {
    if (_isStreaming) return;
    while (_messages.isNotEmpty && _messages.last.isAssistant) {
      _messages.removeLast();
    }
    if (_messages.isEmpty) return;
    _error = null;
    _safeNotify();
    await _repo.replaceAll(article.id, _messages);
    await _runCompletion();
  }

  /// Deletes the whole conversation.
  Future<void> clear() async {
    _cancelToken?.cancel('Chat cleared');
    _messages.clear();
    _partialResponse = '';
    _error = null;
    _safeNotify();
    await _repo.clear(article.id);
  }

  // --- internals -------------------------------------------------------------

  Future<void> _runCompletion() async {
    _isStreaming = true;
    _partialResponse = '';
    _cancelToken = CancelToken();
    _safeNotify();

    final buffer = StringBuffer();
    try {
      await for (final chunk in _ai.chatStream(
        _apiMessages(),
        system: systemPrompt,
        maxTokens: AiLimits.chatMaxTokens,
        cancelToken: _cancelToken,
      )) {
        if (_disposed) return;
        buffer.write(chunk);
        _partialResponse = buffer.toString();
        _safeNotify();
      }
    } on AiException catch (e) {
      if (!e.isCancelled) _error = e.userMessage;
    } catch (e, st) {
      AppLog.e('Ask AI request failed', e, st);
      _error = 'Something went wrong talking to the AI provider.';
    } finally {
      _isStreaming = false;
      _cancelToken = null;
      _partialResponse = '';
      final answer = buffer.toString().trim();
      if (answer.isNotEmpty) {
        final assistant = ArticleChatRepository.newMessage(
          article.id,
          ChatRole.assistant,
          answer,
        );
        _messages.add(assistant);
        await _repo.appendMessage(assistant);
      }
      _safeNotify();
    }
  }

  List<AiMessage> _apiMessages() => [
    for (final message in _messages)
      if (!message.isSystem)
        AiMessage(role: message.role, content: message.content),
  ];

  Future<void> _refreshConfigInfo() async {
    try {
      final config = await _ai.currentConfig();
      _providerLabel = config.provider.label;
      _model = config.model;
    } catch (e) {
      AppLog.w('Could not read AI config for the chat sheet', e);
    }
  }

  /// Plain text handed to the model: full article, else RSS content, else
  /// the description.
  String get _articleText {
    final cached = _articleTextCache;
    if (cached != null) return cached;

    String text = '';
    if (article.hasFullContent) {
      text = Article.stripHtml(article.fullContent!);
    }
    if (text.trim().isEmpty) {
      final content = article.content;
      if (content != null && content.trim().isNotEmpty) {
        text = Article.stripHtml(content);
      }
    }
    if (text.trim().isEmpty) {
      text = Article.stripHtml(article.description);
    }
    _articleTextCache = text.trim();
    return _articleTextCache!;
  }

  static int _wordCount(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  static String _formatCount(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel('Chat closed');
    _cancelToken = null;
    super.dispose();
  }
}
