import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_logger.dart';
import 'ai_adapters.dart';
import 'ai_models.dart';

/// Where [AiService] gets its provider / key / model from.
abstract class AiConfigSource {
  /// Config for the provider the user selected.
  Future<AiConfig> currentConfig();

  /// Config for a specific provider (used by the settings screens).
  Future<AiConfig> configFor(AiProvider provider);
}

/// Reads from a live [SettingsProvider] (used by the UI layer).
class SettingsAiConfigSource implements AiConfigSource {
  SettingsAiConfigSource(this.settings);

  final SettingsProvider settings;

  @override
  Future<AiConfig> currentConfig() =>
      configFor(AiProvider.fromId(settings.summarizationProvider));

  @override
  Future<AiConfig> configFor(AiProvider provider) async {
    final model = settings.getModelForProvider(provider.id);
    return AiConfig(
      provider: provider,
      apiKey: settings.apiKeyFor(provider.id),
      model: model.isEmpty || model == 'default'
          ? AiService.defaultModelFor(provider)
          : model,
      baseUrl: provider == AiProvider.ollama ? settings.ollamaBaseUrl : null,
    );
  }
}

/// Reads SharedPreferences + secure storage directly.
///
/// Used by `SummarizationService` so it keeps working without a widget tree
/// (and so the existing tests, which mock both channels, keep passing).
class PrefsAiConfigSource implements AiConfigSource {
  PrefsAiConfigSource({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<AiConfig> currentConfig() async {
    final prefs = await _prefs();
    final id =
        prefs?.getString(SettingsProvider.summarizationProviderKey) ??
        SettingsProvider.providerGemini;
    return _build(AiProvider.fromId(id), prefs);
  }

  @override
  Future<AiConfig> configFor(AiProvider provider) async =>
      _build(provider, await _prefs());

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      AppLog.w('Could not open shared preferences for AI config', e);
      return null;
    }
  }

  Future<AiConfig> _build(AiProvider provider, SharedPreferences? prefs) async {
    return AiConfig(
      provider: provider,
      apiKey: await _readKey(provider),
      model:
          prefs?.getString(_modelPrefKey(provider)) ??
          AiService.defaultModelFor(provider),
      baseUrl: provider == AiProvider.ollama
          ? (prefs?.getString(SettingsProvider.ollamaBaseUrlKey) ??
                SettingsProvider.defaultOllamaBaseUrl)
          : null,
    );
  }

  Future<String> _readKey(AiProvider provider) async {
    final storageKey = _secureKeyName(provider);
    if (storageKey == null) return '';
    try {
      return await _secureStorage.read(key: storageKey) ?? '';
    } catch (e) {
      AppLog.w('Could not read secure key $storageKey', e);
      return '';
    }
  }

  static String? _secureKeyName(AiProvider provider) {
    switch (provider) {
      case AiProvider.openai:
        return SettingsProvider.openaiKey;
      case AiProvider.claude:
        return SettingsProvider.claudeKey;
      case AiProvider.gemini:
        return SettingsProvider.geminiKey;
      case AiProvider.openrouter:
        return SettingsProvider.openrouterKey;
      case AiProvider.perplexity:
        return SettingsProvider.perplexityKey;
      case AiProvider.nvidia:
        return SettingsProvider.nvidiaKey;
      case AiProvider.ollama:
        return null;
    }
  }

  static String _modelPrefKey(AiProvider provider) {
    switch (provider) {
      case AiProvider.openai:
        return SettingsProvider.openaiModelKey;
      case AiProvider.claude:
        return SettingsProvider.claudeModelKey;
      case AiProvider.gemini:
        return SettingsProvider.geminiModelKey;
      case AiProvider.openrouter:
        return SettingsProvider.openrouterModelKey;
      case AiProvider.perplexity:
        return SettingsProvider.perplexityModelKey;
      case AiProvider.nvidia:
        return SettingsProvider.nvidiaModelKey;
      case AiProvider.ollama:
        return SettingsProvider.ollamaModelKey;
    }
  }
}

/// A fixed config, handy for tests and one-off calls.
class StaticAiConfigSource implements AiConfigSource {
  const StaticAiConfigSource(this.config);

  final AiConfig config;

  @override
  Future<AiConfig> currentConfig() async => config;

  @override
  Future<AiConfig> configFor(AiProvider provider) async =>
      config.provider == provider
      ? config
      : config.copyWith(provider: provider);
}

/// The single entry point for every model call in the app.
///
/// Failures surface as [AiException]s with a user-safe `userMessage`.
class AiService {
  AiService({required AiConfigSource configSource, Dio? dio})
    : _configSource = configSource,
      _dio = dio ?? buildDefaultDio() {
    _claude = ClaudeAdapter(_dio);
    _gemini = GeminiAdapter(_dio);
    _openAi = OpenAiCompatibleAdapter(_dio);
  }

  final AiConfigSource _configSource;
  final Dio _dio;

  late final ClaudeAdapter _claude;
  late final GeminiAdapter _gemini;
  late final OpenAiCompatibleAdapter _openAi;

  /// Dio with timeouts tuned for local (Ollama) and cloud models.
  static Dio buildDefaultDio() {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 20);
    dio.options.receiveTimeout = const Duration(seconds: 180);
    return dio;
  }

  AiConfigSource get configSource => _configSource;

  /// Config for the provider the user picked.
  Future<AiConfig> currentConfig() => _configSource.currentConfig();

  /// Config for a specific provider.
  Future<AiConfig> configFor(AiProvider provider) =>
      _configSource.configFor(provider);

  /// Adapter that speaks [provider]'s dialect.
  AiAdapter adapterFor(AiProvider provider) {
    switch (provider) {
      case AiProvider.claude:
        return _claude;
      case AiProvider.gemini:
        return _gemini;
      case AiProvider.openai:
      case AiProvider.openrouter:
      case AiProvider.perplexity:
      case AiProvider.nvidia:
      case AiProvider.ollama:
        return _openAi;
    }
  }

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------

  /// Streams the assistant reply chunk by chunk.
  Stream<String> chatStream(
    List<AiMessage> messages, {
    String? system,
    int maxTokens = AiLimits.chatMaxTokens,
    CancelToken? cancelToken,
  }) async* {
    final config = await currentConfig();
    _ensureUsable(config);
    yield* adapterFor(config.provider).stream(
      config,
      messages,
      AiRequestOptions(maxTokens: maxTokens, system: system),
      cancelToken: cancelToken,
    );
  }

  /// One-shot (non-streaming) completion.
  Future<String> chat(
    List<AiMessage> messages, {
    String? system,
    int maxTokens = AiLimits.chatMaxTokens,
    CancelToken? cancelToken,
    AiProvider? provider,
  }) async {
    final config = provider == null
        ? await currentConfig()
        : await configFor(provider);
    _ensureUsable(config);
    return adapterFor(config.provider).complete(
      config,
      messages,
      AiRequestOptions(maxTokens: maxTokens, system: system),
      cancelToken: cancelToken,
    );
  }

  /// Summarises [text] in the requested [style].
  ///
  /// [customInstructions] is the user's free-text addition, appended to the
  /// style prompt (see [withCustomInstructions]).
  Future<String> summarize(
    String text, {
    SummaryStyle style = SummaryStyle.brief,
    String? customInstructions,
    CancelToken? cancelToken,
  }) async {
    final input = truncateForModel(text);
    return chat(
      [AiMessage.user(input)],
      system: withCustomInstructions(
        summaryStyleInstruction(style),
        customInstructions,
      ),
      maxTokens: AiLimits.taskMaxTokens,
      cancelToken: cancelToken,
    );
  }

  // ---------------------------------------------------------------------------
  // Models
  // ---------------------------------------------------------------------------

  /// Lists the models [provider] exposes, falling back to a static list.
  Future<List<String>> fetchAvailableModels(
    AiProvider provider, {
    String? apiKey,
  }) async {
    AiConfig? config;
    try {
      config = await configFor(provider);
    } catch (e) {
      AppLog.w('Could not read config for ${provider.id}', e);
    }
    final key = apiKey ?? config?.apiKey ?? '';
    final baseUrl = config?.baseUrl;

    try {
      final models = await _fetchModels(provider, key, baseUrl);
      if (models.isNotEmpty) {
        models.sort();
        return models;
      }
    } catch (e) {
      AppLog.w('Could not list models for ${provider.id}', e);
    }
    return fallbackModelsFor(provider);
  }

  Future<List<String>> _fetchModels(
    AiProvider provider,
    String apiKey,
    String? baseUrl,
  ) async {
    switch (provider) {
      case AiProvider.openai:
        return _idsFromDataList(
          await _getJson('https://api.openai.com/v1/models', {
            'Authorization': 'Bearer $apiKey',
          }),
        );
      case AiProvider.openrouter:
        return _idsFromDataList(
          await _getJson('https://openrouter.ai/api/v1/models', {
            'Authorization': 'Bearer $apiKey',
            'HTTP-Referer': kOpenRouterReferer,
            'X-Title': kOpenRouterTitle,
          }),
        );
      case AiProvider.nvidia:
        return _idsFromDataList(
          await _getJson('https://integrate.api.nvidia.com/v1/models', {
            'Authorization': 'Bearer $apiKey',
          }),
        );
      case AiProvider.claude:
        return _idsFromDataList(
          await _getJson('https://api.anthropic.com/v1/models', {
            'x-api-key': apiKey,
            'anthropic-version': kAnthropicVersion,
          }),
        );
      case AiProvider.gemini:
        final json = await _getJson('$kGeminiBaseUrl/models', {
          'x-goog-api-key': apiKey,
        });
        final models = json?['models'];
        if (models is! List) return const [];
        final result = <String>[];
        for (final entry in models) {
          if (entry is! Map) continue;
          final methods = entry['supportedGenerationMethods'];
          if (methods is List && !methods.contains('generateContent')) continue;
          final name = entry['name']?.toString();
          if (name == null || name.isEmpty) continue;
          result.add(
            name.startsWith('models/')
                ? name.substring('models/'.length)
                : name,
          );
        }
        return result;
      case AiProvider.ollama:
        final root = normalizeBaseUrl(baseUrl ?? kDefaultOllamaBaseUrl);
        final json = await _getJson('$root/api/tags', const {});
        final models = json?['models'];
        if (models is! List) return const [];
        return [
          for (final entry in models)
            if (entry is Map && entry['name'] != null) entry['name'].toString(),
        ];
      case AiProvider.perplexity:
        // Perplexity has no public model listing endpoint.
        return const [];
    }
  }

  static List<String> _idsFromDataList(Map<String, dynamic>? json) {
    final data = json?['data'];
    if (data is! List) return const [];
    return [
      for (final entry in data)
        if (entry is Map && entry['id'] != null) entry['id'].toString(),
    ];
  }

  Future<Map<String, dynamic>?> _getJson(
    String url,
    Map<String, String> headers,
  ) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) return null;
    final body = response.data;
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Not JSON.
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Sends a tiny prompt to verify the key/model/endpoint combination.
  Future<AiTestResult> testConnection(AiProvider provider) async {
    final stopwatch = Stopwatch()..start();
    try {
      final config = await configFor(provider);
      _ensureUsable(config);
      final reply = await adapterFor(provider).complete(config, const [
        AiMessage.user('Say OK'),
      ], const AiRequestOptions(maxTokens: 16));
      stopwatch.stop();
      return AiTestResult(
        ok: true,
        message:
            'Connected to ${provider.label} (${config.model}).'
            '${reply.trim().isEmpty ? '' : ' Reply: ${reply.trim()}'}',
        latency: stopwatch.elapsed,
      );
    } on AiException catch (e) {
      stopwatch.stop();
      return AiTestResult(ok: false, message: e.userMessage);
    } catch (e) {
      stopwatch.stop();
      return AiTestResult(
        ok: false,
        message: '${provider.label} test failed: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _ensureUsable(AiConfig config) {
    if (!config.isUsable) {
      throw AiException(missingKeyMessage(config.provider), isAuth: true);
    }
  }

  /// Message shown when a provider has no key configured.
  static String missingKeyMessage(AiProvider provider) =>
      'No API key configured for ${provider.label}. Add one in Settings > AI.';

  /// Default model id for [provider].
  static String defaultModelFor(AiProvider provider) {
    switch (provider) {
      case AiProvider.openai:
        return SettingsProvider.defaultOpenaiModel;
      case AiProvider.claude:
        return SettingsProvider.defaultClaudeModel;
      case AiProvider.gemini:
        return SettingsProvider.defaultGeminiModel;
      case AiProvider.openrouter:
        return SettingsProvider.defaultOpenrouterModel;
      case AiProvider.perplexity:
        return SettingsProvider.defaultPerplexityModel;
      case AiProvider.nvidia:
        return SettingsProvider.defaultNvidiaModel;
      case AiProvider.ollama:
        return SettingsProvider.defaultOllamaModel;
    }
  }

  /// Offline model list used when the provider cannot be reached.
  static List<String> fallbackModelsFor(AiProvider provider) {
    switch (provider) {
      case AiProvider.openai:
        return const ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini', 'o4-mini'];
      case AiProvider.claude:
        return const [
          'claude-opus-5',
          'claude-sonnet-5',
          'claude-haiku-4-5',
          'claude-opus-4-8',
        ];
      case AiProvider.gemini:
        return const ['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash'];
      case AiProvider.openrouter:
        return const [
          'openai/gpt-4o-mini',
          'anthropic/claude-sonnet-4.5',
          'google/gemini-2.5-flash',
          'meta-llama/llama-3.1-8b-instruct',
        ];
      case AiProvider.perplexity:
        return const ['sonar', 'sonar-pro', 'sonar-reasoning'];
      case AiProvider.nvidia:
        return const [
          'meta/llama-3.1-8b-instruct',
          'nvidia/llama-3.1-405b-instruct',
        ];
      case AiProvider.ollama:
        return const ['llama3.2', 'mistral', 'gemma3'];
    }
  }
}
