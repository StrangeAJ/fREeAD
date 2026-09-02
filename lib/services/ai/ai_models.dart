import '../../models/app_settings.dart';

/// Limits shared by every AI call.
class AiLimits {
  AiLimits._();

  /// Longest article text handed to a model before it gets truncated.
  static const int maxInputChars = 24000;

  /// Appended when [maxInputChars] kicks in.
  static const String truncationNote = '\n\n[Article truncated]';

  /// `max_tokens` for interactive chat.
  static const int chatMaxTokens = 4096;

  /// `max_tokens` for summaries and categorisation.
  static const int taskMaxTokens = 1024;
}

/// Roles understood by every adapter.
class AiRole {
  AiRole._();

  static const String system = 'system';
  static const String user = 'user';
  static const String assistant = 'assistant';
}

/// The providers FreeAd can talk to.
///
/// [id] matches the string constants used by `SettingsProvider`
/// (`openai`, `claude`, `gemini`, `openrouter`, `perplexity`, `nvidia`,
/// `ollama`) so settings and the AI layer never drift apart.
enum AiProvider {
  openai('openai', 'OpenAI'),
  claude('claude', 'Claude'),
  gemini('gemini', 'Gemini'),
  openrouter('openrouter', 'OpenRouter'),
  perplexity('perplexity', 'Perplexity'),
  nvidia('nvidia', 'NVIDIA NIM'),
  ollama('ollama', 'Ollama');

  const AiProvider(this.id, this.label);

  /// Stable string id, also used as the SharedPreferences value.
  final String id;

  /// Human readable name shown in the UI and in error messages.
  final String label;

  /// Ollama runs locally and needs no credentials.
  bool get requiresApiKey => this != AiProvider.ollama;

  /// True when this provider speaks the OpenAI `/chat/completions` dialect.
  bool get isOpenAiCompatible =>
      this != AiProvider.claude && this != AiProvider.gemini;

  static AiProvider? tryFromId(String? id) {
    if (id == null) return null;
    final normalized = id.trim().toLowerCase();
    for (final provider in AiProvider.values) {
      if (provider.id == normalized) return provider;
    }
    return null;
  }

  /// Parses [id], falling back to [fallback] for unknown values.
  static AiProvider fromId(
    String? id, {
    AiProvider fallback = AiProvider.gemini,
  }) => tryFromId(id) ?? fallback;

  /// Display label for a raw provider id (used by error strings).
  static String labelForId(String id) => tryFromId(id)?.label ?? id;
}

/// Everything an adapter needs to make one request.
class AiConfig {
  const AiConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
  });

  final AiProvider provider;
  final String apiKey;
  final String model;

  /// Only meaningful for Ollama (`http://host:11434`).
  final String? baseUrl;

  /// True when this config can actually be used to make a request.
  bool get isUsable => !provider.requiresApiKey || apiKey.trim().isNotEmpty;

  AiConfig copyWith({
    AiProvider? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
  }) {
    return AiConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }

  @override
  String toString() => 'AiConfig(${provider.id}, model: $model)';
}

/// One turn of a conversation.
class AiMessage {
  const AiMessage({required this.role, required this.content});

  const AiMessage.system(this.content) : role = AiRole.system;
  const AiMessage.user(this.content) : role = AiRole.user;
  const AiMessage.assistant(this.content) : role = AiRole.assistant;

  /// 'system' | 'user' | 'assistant' - see [AiRole].
  final String role;
  final String content;

  bool get isSystem => role == AiRole.system;
  bool get isUser => role == AiRole.user;
  bool get isAssistant => role == AiRole.assistant;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  @override
  String toString() => 'AiMessage($role, ${content.length} chars)';
}

/// Per-request knobs. Deliberately tiny: no temperature, no thinking config.
class AiRequestOptions {
  const AiRequestOptions({
    this.maxTokens = AiLimits.chatMaxTokens,
    this.system,
  });

  final int maxTokens;
  final String? system;
}

/// A failure with a message that is safe to show the user.
///
/// Adapters never surface raw `DioException` text.
class AiException implements Exception {
  const AiException(
    this.userMessage, {
    this.statusCode,
    this.isAuth = false,
    this.isRateLimit = false,
    this.isNetwork = false,
    this.isRefusal = false,
    this.isCancelled = false,
  });

  /// Friendly, already-formatted message.
  final String userMessage;
  final int? statusCode;

  /// 401 / 403 - the key is missing, wrong or lacks access.
  final bool isAuth;

  /// 429 - rate limit or quota.
  final bool isRateLimit;

  /// Timeouts and connection failures.
  final bool isNetwork;

  /// The model declined the request (`stop_reason == "refusal"`).
  final bool isRefusal;

  /// The caller cancelled the request.
  final bool isCancelled;

  @override
  String toString() => userMessage;
}

/// Result of `AiService.testConnection`.
class AiTestResult {
  const AiTestResult({required this.ok, required this.message, this.latency});

  final bool ok;
  final String message;
  final Duration? latency;

  @override
  String toString() => 'AiTestResult(ok: $ok, message: $message)';
}

/// System prompt used for each [SummaryStyle]. Always plain Markdown.
String summaryStyleInstruction(SummaryStyle style) {
  const base =
      'You summarize articles for a reader app. Use the article text only; '
      'do not invent facts. Reply in plain Markdown with no preamble, no '
      'title and no closing remarks.';
  switch (style) {
    case SummaryStyle.brief:
      return '$base Write 3 to 5 sentences in a single paragraph.';
    case SummaryStyle.detailed:
      return '$base Write 2 to 4 short paragraphs covering the key points, '
          'the evidence and any caveats.';
    case SummaryStyle.bullets:
      return '$base Write 5 to 8 bullet points, one line each, starting with '
          '"- ".';
  }
}

/// Clips [text] to [AiLimits.maxInputChars], appending a note when it does.
String truncateForModel(String text, {int? maxChars}) {
  final limit = maxChars ?? AiLimits.maxInputChars;
  if (text.length <= limit) return text;
  return '${text.substring(0, limit)}${AiLimits.truncationNote}';
}
