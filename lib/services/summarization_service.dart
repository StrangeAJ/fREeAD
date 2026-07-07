import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/article.dart';
import '../providers/settings_provider.dart';

class SummarizationService {
  final Dio _dio = Dio();
  // Keys are stored in secure storage by SettingsProvider, not SharedPreferences.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const int _maxInputChars = 12000;
  static const String _systemPrompt =
      'You are a helpful assistant that summarizes articles. '
      'Summarize the following text concisely in a few short paragraphs or bullet points.';

  SummarizationService() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    // Local models (Ollama) and large cloud models can take a while to respond.
    _dio.options.receiveTimeout = const Duration(seconds: 120);
    _dio.options.validateStatus = (status) => status != null && status < 500;
  }

  Future<String> summarizeArticle(Article article) async {
    final text = article.content ?? article.description;
    if (text.isEmpty) return 'No content to summarize.';
    return summarize(text);
  }

  Future<String> summarizeContent(String? content) async {
    if (content == null || content.isEmpty) return '';
    if (content.length < 50) return content;
    return summarize(content);
  }

  Future<String> summarize(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final provider =
        prefs.getString('summarization_provider') ??
        SettingsProvider.providerGemini;

    final input = text.length > _maxInputChars
        ? text.substring(0, _maxInputChars)
        : text;

    final apiKey = await _getApiKey(provider);
    if (apiKey.isEmpty && provider != SettingsProvider.providerOllama) {
      return 'No API key configured for ${_providerLabel(provider)}. '
          'Add one in Settings > AI Summarization > API Keys.';
    }

    try {
      switch (provider) {
        case SettingsProvider.providerOpenAI:
          return await _openAiCompatible(
            url: 'https://api.openai.com/v1/chat/completions',
            apiKey: apiKey,
            model: prefs.getString(SettingsProvider.openaiModelKey) ??
                'gpt-4o-mini',
            text: input,
            provider: provider,
          );
        case SettingsProvider.providerClaude:
          return await _summarizeClaude(input, apiKey);
        case SettingsProvider.providerGemini:
          return await _summarizeGemini(input, apiKey);
        case SettingsProvider.providerOpenRouter:
          return await _openAiCompatible(
            url: 'https://openrouter.ai/api/v1/chat/completions',
            apiKey: apiKey,
            model: 'openai/gpt-4o-mini',
            text: input,
            provider: provider,
          );
        case SettingsProvider.providerPerplexity:
          return await _openAiCompatible(
            url: 'https://api.perplexity.ai/chat/completions',
            apiKey: apiKey,
            model: 'sonar',
            text: input,
            provider: provider,
          );
        case SettingsProvider.providerNvidia:
          return await _openAiCompatible(
            url: 'https://integrate.api.nvidia.com/v1/chat/completions',
            apiKey: apiKey,
            model: prefs.getString(SettingsProvider.nvidiaModelKey) ??
                'meta/llama-3.1-8b-instruct',
            text: input,
            provider: provider,
          );
        case SettingsProvider.providerOllama:
          final baseUrl = _normalizeBaseUrl(
            prefs.getString(SettingsProvider.ollamaBaseUrlKey) ??
                'http://localhost:11434',
          );
          return await _openAiCompatible(
            url: '$baseUrl/v1/chat/completions',
            apiKey: apiKey.isEmpty ? 'ollama' : apiKey,
            model:
                prefs.getString(SettingsProvider.ollamaModelKey) ?? 'llama3.2',
            text: input,
            provider: provider,
          );
        default:
          return 'Provider "$provider" is not supported.';
      }
    } on DioException catch (e) {
      return _friendlyDioError(provider, e);
    } catch (e) {
      return 'Summarization with ${_providerLabel(provider)} failed: $e';
    }
  }

  Future<String> _getApiKey(String provider) async {
    switch (provider) {
      case SettingsProvider.providerOpenAI:
        return await _secureStorage.read(key: SettingsProvider.openaiKey) ?? '';
      case SettingsProvider.providerClaude:
        return await _secureStorage.read(key: SettingsProvider.claudeKey) ?? '';
      case SettingsProvider.providerGemini:
        return await _secureStorage.read(key: SettingsProvider.geminiKey) ?? '';
      case SettingsProvider.providerOpenRouter:
        return await _secureStorage.read(key: SettingsProvider.openrouterKey) ??
            '';
      case SettingsProvider.providerPerplexity:
        return await _secureStorage.read(key: SettingsProvider.perplexityKey) ??
            '';
      case SettingsProvider.providerNvidia:
        return await _secureStorage.read(key: SettingsProvider.nvidiaKey) ?? '';
      default:
        return '';
    }
  }

  /// OpenAI-compatible chat completions — used by OpenAI, OpenRouter,
  /// Perplexity, NVIDIA NIM, and Ollama.
  Future<String> _openAiCompatible({
    required String url,
    required String apiKey,
    required String model,
    required String text,
    required String provider,
  }) async {
    final response = await _dio.post(
      url,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      data: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': text},
        ],
        'stream': false,
      },
    );

    if (response.statusCode != 200) {
      return _friendlyHttpError(provider, response);
    }

    final content = response.data?['choices']?[0]?['message']?['content'];
    if (content is! String || content.isEmpty) {
      return 'Empty response from ${_providerLabel(provider)}.';
    }
    return content.trim();
  }

  Future<String> _summarizeClaude(String text, String apiKey) async {
    final response = await _dio.post(
      'https://api.anthropic.com/v1/messages',
      options: Options(
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
      ),
      data: {
        'model': 'claude-opus-4-8',
        'max_tokens': 1024,
        'system': _systemPrompt,
        'messages': [
          {'role': 'user', 'content': text},
        ],
      },
    );

    if (response.statusCode != 200) {
      return _friendlyHttpError(SettingsProvider.providerClaude, response);
    }

    final blocks = response.data?['content'];
    if (blocks is List) {
      for (final block in blocks) {
        if (block is Map && block['type'] == 'text') {
          return (block['text'] as String).trim();
        }
      }
    }
    return 'Empty response from Claude.';
  }

  Future<String> _summarizeGemini(String text, String apiKey) async {
    final response = await _dio.post(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
      options: Options(headers: {'x-goog-api-key': apiKey}),
      data: {
        'contents': [
          {
            'parts': [
              {'text': '$_systemPrompt\n\n$text'},
            ],
          },
        ],
      },
    );

    if (response.statusCode != 200) {
      return _friendlyHttpError(SettingsProvider.providerGemini, response);
    }

    final content =
        response.data?['candidates']?[0]?['content']?['parts']?[0]?['text'];
    if (content is! String || content.isEmpty) {
      return 'Empty response from Gemini.';
    }
    return content.trim();
  }

  Future<List<String>> fetchAvailableModels(
    String provider,
    String apiKey,
  ) async {
    try {
      switch (provider) {
        case SettingsProvider.providerNvidia:
          final response = await _dio.get(
            'https://integrate.api.nvidia.com/v1/models',
            options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
          );
          if (response.statusCode == 200 && response.data?['data'] is List) {
            return (response.data['data'] as List)
                .map((m) => m['id'].toString())
                .toList();
          }
          break;
        case SettingsProvider.providerOllama:
          final prefs = await SharedPreferences.getInstance();
          final baseUrl = _normalizeBaseUrl(
            prefs.getString(SettingsProvider.ollamaBaseUrlKey) ??
                'http://localhost:11434',
          );
          final response = await _dio.get('$baseUrl/api/tags');
          if (response.statusCode == 200 && response.data?['models'] is List) {
            return (response.data['models'] as List)
                .map((m) => m['name'].toString())
                .toList();
          }
          break;
        case SettingsProvider.providerOpenAI:
          final response = await _dio.get(
            'https://api.openai.com/v1/models',
            options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
          );
          if (response.statusCode == 200 && response.data?['data'] is List) {
            return (response.data['data'] as List)
                .map((m) => m['id'].toString())
                .toList();
          }
          break;
      }
    } catch (_) {
      // Fall through to defaults below.
    }

    switch (provider) {
      case SettingsProvider.providerNvidia:
        return ['meta/llama-3.1-8b-instruct', 'nvidia/llama-3.1-405b-instruct'];
      case SettingsProvider.providerOllama:
        return ['llama3.2', 'mistral', 'gemma3'];
      case SettingsProvider.providerOpenAI:
        return ['gpt-4o-mini', 'gpt-4o'];
      default:
        return ['default-model'];
    }
  }

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    return normalized;
  }

  String _providerLabel(String provider) {
    switch (provider) {
      case SettingsProvider.providerOpenAI:
        return 'OpenAI';
      case SettingsProvider.providerClaude:
        return 'Claude';
      case SettingsProvider.providerGemini:
        return 'Gemini';
      case SettingsProvider.providerOpenRouter:
        return 'OpenRouter';
      case SettingsProvider.providerPerplexity:
        return 'Perplexity';
      case SettingsProvider.providerNvidia:
        return 'NVIDIA NIM';
      case SettingsProvider.providerOllama:
        return 'Ollama';
      default:
        return provider;
    }
  }

  String _friendlyHttpError(String provider, Response response) {
    final label = _providerLabel(provider);
    final status = response.statusCode;
    String detail = '';
    try {
      final data = response.data;
      if (data is Map) {
        final error = data['error'];
        if (error is Map && error['message'] != null) {
          detail = error['message'].toString();
        } else if (error is String) {
          detail = error;
        } else if (data['message'] != null) {
          detail = data['message'].toString();
        }
      }
    } catch (_) {}

    switch (status) {
      case 401:
      case 403:
        return '$label rejected the API key (HTTP $status). '
            'Check the key in Settings > AI Summarization > API Keys.'
            '${detail.isNotEmpty ? '\n$detail' : ''}';
      case 404:
        return '$label endpoint or model not found (HTTP 404). '
            'The configured model may be unavailable.'
            '${detail.isNotEmpty ? '\n$detail' : ''}';
      case 429:
        return '$label rate limit or quota exceeded (HTTP 429). '
            'Try again later.${detail.isNotEmpty ? '\n$detail' : ''}';
      default:
        return '$label request failed (HTTP $status).'
            '${detail.isNotEmpty ? '\n$detail' : ''}';
    }
  }

  String _friendlyDioError(String provider, DioException e) {
    final label = _providerLabel(provider);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Request to $label timed out. '
            '${provider == SettingsProvider.providerOllama ? 'Make sure the Ollama server is running and reachable.' : 'Check your internet connection and try again.'}';
      case DioExceptionType.connectionError:
        return 'Could not connect to $label. '
            '${provider == SettingsProvider.providerOllama ? 'Make sure the Ollama server is running at the configured URL (Settings > AI Summarization > Model Settings). On an Android device use your computer\'s LAN IP, not localhost.' : 'Check your internet connection.'}';
      default:
        return 'Network error with $label: ${e.message}';
    }
  }
}
