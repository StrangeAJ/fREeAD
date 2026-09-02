import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show protected;

import '../../utils/app_logger.dart';
import 'ai_models.dart';

/// Anthropic Messages API endpoint.
const String kAnthropicMessagesUrl = 'https://api.anthropic.com/v1/messages';

/// Anthropic API version header value.
const String kAnthropicVersion = '2023-06-01';

/// Base URL for the Gemini generative language API.
const String kGeminiBaseUrl =
    'https://generativelanguage.googleapis.com/v1beta';

/// Default Ollama server.
const String kDefaultOllamaBaseUrl = 'http://localhost:11434';

/// Referer/title headers OpenRouter asks integrations to send.
const String kOpenRouterReferer = 'https://github.com/StrangeAJ/fREeAD';
const String kOpenRouterTitle = 'FreeAd';

/// Normalises a user supplied base URL (adds a scheme, drops a trailing `/`).
String normalizeBaseUrl(String url) {
  var normalized = url.trim();
  if (normalized.isEmpty) return kDefaultOllamaBaseUrl;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'http://$normalized';
  }
  return normalized;
}

/// Maps an HTTP failure to an [AiException] whose message is safe to display.
AiException aiHttpError(AiProvider provider, int? status, String bodyText) {
  final label = provider.label;
  final detail = _detailFromBody(bodyText);
  final suffix = detail.isEmpty ? '' : '\n$detail';

  switch (status) {
    case 401:
    case 403:
      return AiException(
        '$label rejected the API key (HTTP $status). '
        'Check the key in Settings > AI.$suffix',
        statusCode: status,
        isAuth: true,
      );
    case 404:
      return AiException(
        '$label endpoint or model not found (HTTP 404). '
        'The configured model may be unavailable.$suffix',
        statusCode: status,
      );
    case 429:
      return AiException(
        '$label rate limit or quota exceeded (HTTP 429). '
        'Try again later.$suffix',
        statusCode: status,
        isRateLimit: true,
      );
    default:
      return AiException(
        '$label request failed (HTTP $status).$suffix',
        statusCode: status,
      );
  }
}

/// Maps a transport failure to an [AiException].
AiException aiNetworkError(AiProvider provider, DioException e) {
  if (CancelToken.isCancel(e)) {
    return const AiException('Request cancelled.', isCancelled: true);
  }
  final label = provider.label;
  final isOllama = provider == AiProvider.ollama;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return AiException(
        'Request to $label timed out. '
        '${isOllama ? 'Make sure the Ollama server is running and reachable.' : 'Check your internet connection and try again.'}',
        isNetwork: true,
      );
    case DioExceptionType.connectionError:
      return AiException(
        'Could not connect to $label. '
        '${isOllama ? 'Make sure the Ollama server is running at the configured URL. On an Android device use your computer\'s LAN IP, not localhost.' : 'Check your internet connection.'}',
        isNetwork: true,
      );
    case DioExceptionType.badCertificate:
      return AiException(
        'Could not verify the TLS certificate for $label.',
        isNetwork: true,
      );
    default:
      return AiException(
        'Network error with $label: ${e.message ?? e.type.name}',
        isNetwork: true,
      );
  }
}

String _detailFromBody(String bodyText) {
  final trimmed = bodyText.trim();
  if (trimmed.isEmpty) return '';
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (error is String && error.isNotEmpty) return error;
      if (decoded['message'] != null) return decoded['message'].toString();
      if (decoded['detail'] != null) return decoded['detail'].toString();
      // Structured but unrecognised - do not echo raw JSON at the user.
      return '';
    }
  } catch (_) {
    // Not JSON - fall through and show a short raw excerpt.
  }
  return trimmed.length > 300 ? '${trimmed.substring(0, 300)}...' : trimmed;
}

/// Streams assistant text for one provider dialect.
///
/// Implementations never throw raw `DioException`s - every failure surfaces as
/// an [AiException] whose `userMessage` can be shown directly.
abstract class AiAdapter {
  /// Streams the assistant reply as incremental text chunks.
  Stream<String> stream(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  });

  /// Non-streaming variant, used for summaries and as the streaming fallback.
  Future<String> complete(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  });
}

/// Shared HTTP plumbing, SSE parsing and error mapping.
abstract class BaseAiAdapter implements AiAdapter {
  BaseAiAdapter(this.dio);

  final Dio dio;

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  /// POSTs [body] and returns the raw byte stream response.
  @protected
  Future<Response<ResponseBody>> openStream(
    AiProvider provider,
    String url,
    Map<String, String> headers,
    Map<String, dynamic> body,
    CancelToken? cancelToken,
  ) async {
    try {
      return await dio.post<ResponseBody>(
        url,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw networkError(provider, e);
    }
  }

  /// POSTs [body] and returns the decoded body plus status code.
  @protected
  Future<({int? status, String text})> postText(
    AiProvider provider,
    String url,
    Map<String, String> headers,
    Map<String, dynamic> body,
    CancelToken? cancelToken,
  ) async {
    try {
      final response = await dio.post<String>(
        url,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      return (status: response.statusCode, text: response.data ?? '');
    } on DioException catch (e) {
      throw networkError(provider, e);
    }
  }

  /// GETs [url] and returns the decoded body plus status code.
  @protected
  Future<({int? status, String text})> getText(
    AiProvider provider,
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final response = await dio.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      return (status: response.statusCode, text: response.data ?? '');
    } on DioException catch (e) {
      throw networkError(provider, e);
    }
  }

  // ---------------------------------------------------------------------------
  // SSE
  // ---------------------------------------------------------------------------

  /// Yields the payload of every `data:` line, tolerating `event:` lines,
  /// comments, blank lines and chunk boundaries that fall mid-line.
  @protected
  Stream<String> sseDataPayloads(ResponseBody body) async* {
    final lines = const Utf8Decoder(
      allowMalformed: true,
    ).bind(body.stream).transform(const LineSplitter());
    await for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      yield payload;
    }
  }

  /// Reads the whole response body as text (used for error payloads).
  @protected
  Future<String> drain(ResponseBody body) async {
    final buffer = StringBuffer();
    try {
      await for (final chunk in const Utf8Decoder(
        allowMalformed: true,
      ).bind(body.stream)) {
        buffer.write(chunk);
        if (buffer.length > 8000) break;
      }
    } catch (e) {
      AppLog.w('Could not read error body', e);
    }
    return buffer.toString();
  }

  /// Handles a non-200 streaming response: retries without streaming when the
  /// server complained about streaming, otherwise throws a friendly error.
  @protected
  Future<String> failOrFallback(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options,
    CancelToken? cancelToken,
    int? status,
    String bodyText,
  ) async {
    if (status == 400 && _mentionsStreaming(bodyText)) {
      AppLog.w(
        '${config.provider.label} rejected streaming, retrying without it',
      );
      return complete(config, messages, options, cancelToken: cancelToken);
    }
    throw httpError(config.provider, status, bodyText);
  }

  static bool _mentionsStreaming(String body) {
    final lower = body.toLowerCase();
    return lower.contains('stream');
  }

  // ---------------------------------------------------------------------------
  // Errors
  // ---------------------------------------------------------------------------

  /// Maps an HTTP failure to a friendly [AiException].
  @protected
  AiException httpError(AiProvider provider, int? status, String bodyText) =>
      aiHttpError(provider, status, bodyText);

  /// Maps a transport failure to a friendly [AiException].
  @protected
  AiException networkError(AiProvider provider, DioException e) =>
      aiNetworkError(provider, e);

  /// Decodes a JSON object, returning `null` when the payload is not an object.
  @protected
  Map<String, dynamic>? tryDecodeObject(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Ignore malformed SSE payloads.
    }
    return null;
  }

  /// Collapses consecutive same-role turns and drops empty ones.
  @protected
  List<AiMessage> normalizeTurns(List<AiMessage> messages) {
    final result = <AiMessage>[];
    for (final message in messages) {
      if (message.content.trim().isEmpty) continue;
      if (result.isNotEmpty && result.last.role == message.role) {
        final merged = '${result.last.content}\n\n${message.content}';
        result[result.length - 1] = AiMessage(
          role: message.role,
          content: merged,
        );
        continue;
      }
      result.add(message);
    }
    return result;
  }

  /// Joins [options.system] with any `system` turns in [messages].
  @protected
  String? mergedSystem(List<AiMessage> messages, AiRequestOptions options) {
    final parts = <String>[
      if (options.system != null && options.system!.trim().isNotEmpty)
        options.system!.trim(),
      for (final message in messages)
        if (message.isSystem && message.content.trim().isNotEmpty)
          message.content.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }
}

// =============================================================================
// OpenAI-compatible (OpenAI, OpenRouter, Perplexity, NVIDIA NIM, Ollama)
// =============================================================================

class OpenAiCompatibleAdapter extends BaseAiAdapter {
  OpenAiCompatibleAdapter(super.dio);

  /// API root for [config]'s provider.
  static String baseUrlFor(AiConfig config) {
    switch (config.provider) {
      case AiProvider.openrouter:
        return 'https://openrouter.ai/api/v1';
      case AiProvider.perplexity:
        return 'https://api.perplexity.ai';
      case AiProvider.nvidia:
        return 'https://integrate.api.nvidia.com/v1';
      case AiProvider.ollama:
        return '${normalizeBaseUrl(config.baseUrl ?? kDefaultOllamaBaseUrl)}/v1';
      case AiProvider.openai:
      case AiProvider.claude:
      case AiProvider.gemini:
        return 'https://api.openai.com/v1';
    }
  }

  static Map<String, String> headersFor(AiConfig config) {
    final key = config.provider == AiProvider.ollama && config.apiKey.isEmpty
        ? 'ollama'
        : config.apiKey;
    return {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      if (config.provider == AiProvider.openrouter) ...{
        'HTTP-Referer': kOpenRouterReferer,
        'X-Title': kOpenRouterTitle,
      },
    };
  }

  Map<String, dynamic> buildBody(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    required bool stream,
  }) {
    final system = mergedSystem(messages, options);
    final turns = normalizeTurns([
      for (final message in messages)
        if (!message.isSystem) message,
    ]);
    return {
      'model': config.model,
      'messages': [
        if (system != null) {'role': AiRole.system, 'content': system},
        for (final turn in turns) turn.toJson(),
      ],
      'stream': stream,
    };
  }

  @override
  Stream<String> stream(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  }) async* {
    final url = '${baseUrlFor(config)}/chat/completions';
    final response = await openStream(
      config.provider,
      url,
      headersFor(config),
      buildBody(config, messages, options, stream: true),
      cancelToken,
    );

    final body = response.data;
    if (body == null) {
      throw AiException('Empty response from ${config.provider.label}.');
    }

    if (response.statusCode != 200) {
      final text = await drain(body);
      yield await failOrFallback(
        config,
        messages,
        options,
        cancelToken,
        response.statusCode,
        text,
      );
      return;
    }

    try {
      await for (final payload in sseDataPayloads(body)) {
        if (payload == '[DONE]') return;
        final event = tryDecodeObject(payload);
        if (event == null) continue;
        final error = event['error'];
        if (error != null) {
          throw httpError(config.provider, 200, jsonEncode(event));
        }
        final choices = event['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map) continue;
        final delta = first['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) yield content;
        }
      }
    } on DioException catch (e) {
      throw networkError(config.provider, e);
    }
  }

  @override
  Future<String> complete(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  }) async {
    final url = '${baseUrlFor(config)}/chat/completions';
    final result = await postText(
      config.provider,
      url,
      headersFor(config),
      buildBody(config, messages, options, stream: false),
      cancelToken,
    );
    if (result.status != 200) {
      throw httpError(config.provider, result.status, result.text);
    }
    final decoded = tryDecodeObject(result.text);
    final choices = decoded?['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = (choices.first as Map)['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    }
    throw AiException('Empty response from ${config.provider.label}.');
  }
}

// =============================================================================
// Claude (Anthropic Messages API)
// =============================================================================

class ClaudeAdapter extends BaseAiAdapter {
  ClaudeAdapter(super.dio);

  static Map<String, String> headersFor(AiConfig config) => {
    'x-api-key': config.apiKey,
    'anthropic-version': kAnthropicVersion,
    'content-type': 'application/json',
  };

  /// Body for `POST /v1/messages`. Deliberately omits `thinking`,
  /// `output_config`, `temperature` and assistant prefill.
  Map<String, dynamic> buildBody(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    required bool stream,
  }) {
    final system = mergedSystem(messages, options);
    final turns = normalizeTurns([
      for (final message in messages)
        if (!message.isSystem) message,
    ]);
    return {
      'model': config.model,
      'max_tokens': options.maxTokens,
      if (system != null) 'system': system,
      'messages': [for (final turn in turns) turn.toJson()],
      'stream': stream,
    };
  }

  @override
  Stream<String> stream(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  }) async* {
    final response = await openStream(
      config.provider,
      kAnthropicMessagesUrl,
      headersFor(config),
      buildBody(config, messages, options, stream: true),
      cancelToken,
    );

    final body = response.data;
    if (body == null) {
      throw const AiException('Empty response from Claude.');
    }

    if (response.statusCode != 200) {
      final text = await drain(body);
      yield await failOrFallback(
        config,
        messages,
        options,
        cancelToken,
        response.statusCode,
        text,
      );
      return;
    }

    try {
      await for (final payload in sseDataPayloads(body)) {
        final event = tryDecodeObject(payload);
        if (event == null) continue;
        final type = event['type'];

        if (type == 'content_block_delta') {
          final delta = event['delta'];
          if (delta is Map && delta['type'] == 'text_delta') {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) yield text;
          }
        } else if (type == 'message_delta') {
          final delta = event['delta'];
          if (delta is Map && delta['stop_reason'] == 'refusal') {
            throw refusal();
          }
        } else if (type == 'error') {
          final error = event['error'];
          final message = error is Map ? error['message']?.toString() : null;
          throw AiException(
            'Claude request failed.${message == null ? '' : '\n$message'}',
          );
        } else if (type == 'message_stop') {
          return;
        }
      }
    } on DioException catch (e) {
      throw networkError(config.provider, e);
    }
  }

  @override
  Future<String> complete(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  }) async {
    final result = await postText(
      config.provider,
      kAnthropicMessagesUrl,
      headersFor(config),
      buildBody(config, messages, options, stream: false),
      cancelToken,
    );
    if (result.status != 200) {
      throw httpError(config.provider, result.status, result.text);
    }
    final decoded = tryDecodeObject(result.text);
    if (decoded == null) {
      throw const AiException('Empty response from Claude.');
    }
    if (decoded['stop_reason'] == 'refusal') throw refusal();

    final blocks = decoded['content'];
    if (blocks is List) {
      final buffer = StringBuffer();
      for (final block in blocks) {
        if (block is Map && block['type'] == 'text') {
          buffer.write(block['text']?.toString() ?? '');
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    throw const AiException('Empty response from Claude.');
  }

  /// `stop_reason == "refusal"` - the model declined to answer.
  @protected
  AiException refusal() =>
      const AiException('The model declined this request.', isRefusal: true);
}

// =============================================================================
// Gemini
// =============================================================================

class GeminiAdapter extends BaseAiAdapter {
  GeminiAdapter(super.dio);

  static Map<String, String> headersFor(AiConfig config) => {
    'x-goog-api-key': config.apiKey,
    'Content-Type': 'application/json',
  };

  static String streamUrlFor(AiConfig config) =>
      '$kGeminiBaseUrl/models/${config.model}:streamGenerateContent?alt=sse';

  static String generateUrlFor(AiConfig config) =>
      '$kGeminiBaseUrl/models/${config.model}:generateContent';

  Map<String, dynamic> buildBody(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options,
  ) {
    final system = mergedSystem(messages, options);
    final turns = normalizeTurns([
      for (final message in messages)
        if (!message.isSystem) message,
    ]);
    return {
      if (system != null)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'contents': [
        for (final turn in turns)
          {
            'role': turn.isAssistant ? 'model' : 'user',
            'parts': [
              {'text': turn.content},
            ],
          },
      ],
    };
  }

  static String textFromCandidates(Map<String, dynamic> event) {
    final candidates = event['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final first = candidates.first;
    if (first is! Map) return '';
    final content = first['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    return buffer.toString();
  }

  @override
  Stream<String> stream(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  }) async* {
    final response = await openStream(
      config.provider,
      streamUrlFor(config),
      headersFor(config),
      buildBody(config, messages, options),
      cancelToken,
    );

    final body = response.data;
    if (body == null) {
      throw const AiException('Empty response from Gemini.');
    }

    if (response.statusCode != 200) {
      final text = await drain(body);
      yield await failOrFallback(
        config,
        messages,
        options,
        cancelToken,
        response.statusCode,
        text,
      );
      return;
    }

    try {
      await for (final payload in sseDataPayloads(body)) {
        if (payload == '[DONE]') return;
        final event = tryDecodeObject(payload);
        if (event == null) continue;
        if (event['error'] != null) {
          throw httpError(config.provider, 200, jsonEncode(event));
        }
        final text = textFromCandidates(event);
        if (text.isNotEmpty) yield text;
      }
    } on DioException catch (e) {
      throw networkError(config.provider, e);
    }
  }

  @override
  Future<String> complete(
    AiConfig config,
    List<AiMessage> messages,
    AiRequestOptions options, {
    CancelToken? cancelToken,
  }) async {
    final result = await postText(
      config.provider,
      generateUrlFor(config),
      headersFor(config),
      buildBody(config, messages, options),
      cancelToken,
    );
    if (result.status != 200) {
      throw httpError(config.provider, result.status, result.text);
    }
    final decoded = tryDecodeObject(result.text);
    if (decoded != null) {
      final text = textFromCandidates(decoded).trim();
      if (text.isNotEmpty) return text;
    }
    throw const AiException('Empty response from Gemini.');
  }
}
