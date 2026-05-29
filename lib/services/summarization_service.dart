import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freead/services/on_device_ai_service.dart';
import '../providers/settings_provider.dart';
import '../models/article.dart';
import 'database_service.dart';

abstract class Summarizer {
  Future<String> summarize(String text);
}

class SummarizationService implements Summarizer {
  static final SummarizationService _instance = SummarizationService._internal();
  factory SummarizationService() => _instance;
  SummarizationService._internal();

  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)));
  final DatabaseService _databaseService = DatabaseService();
  static DateTime? _lastRequest;
  static const Duration _requestDelay = Duration(seconds: 2);

  Future<String> summarize(String text) async {
    // Add throttling to prevent rapid requests
    if (_lastRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequest!);
      if (timeSinceLastRequest < _requestDelay) {
        await Future.delayed(_requestDelay - timeSinceLastRequest);
      }
    }
    _lastRequest = DateTime.now();

    final prefs = await SharedPreferences.getInstance();

    // Use preferred provider or fall back to current provider
    final preferredProvider = prefs.getString(SettingsProvider.preferredProviderKey) ?? SettingsProvider.providerNone;
    final currentProvider = prefs.getString(SettingsProvider.aiProviderKey) ?? SettingsProvider.providerNone;

    // Try preferred provider first if it's configured
    final settingsProvider = SettingsProvider();
    await settingsProvider.init();

    // Check for on-device AI preference first
    if (settingsProvider.preferOnDeviceAi) {
      final onDeviceAI = OnDeviceAIService();
      if (await onDeviceAI.isAvailable()) {
        try {
          return await onDeviceAI.summarize(text);
        } catch (e) {
          print('On-device AI failed, falling back to cloud: $e');
        }
      }
    }

    String providerToUse = preferredProvider;
    if (preferredProvider == SettingsProvider.providerNone || !settingsProvider.isProviderConfigured(preferredProvider)) {
      providerToUse = currentProvider;
    }

    if (providerToUse == SettingsProvider.providerNone) {
      // If no cloud provider configured, try on-device AI as last resort
      final onDeviceAI = OnDeviceAIService();
      if (await onDeviceAI.isAvailable()) {
        return await onDeviceAI.summarize(text);
      }
      throw Exception('Please configure at least one AI provider in Settings → AI Models');
    }

    final apiKey = prefs.getString(_getKeyForProvider(providerToUse)) ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Please add your API key for $providerToUse in Settings → AI Models');
    }

    // Try with retry logic and fallback
    return await _retryWithFallback(providerToUse, text, settingsProvider);
  }

  // New method to summarize an article with caching
  Future<String> summarizeArticle(Article article) async {
    // Check if article already has a summary
    if (article.summary != null && article.summary!.isNotEmpty) {
      return article.summary!;
    }

    // Get the text to summarize (prefer fullContent, fallback to description)
    final textToSummarize = article.fullContent?.isNotEmpty == true
        ? article.fullContent!
        : article.description;

    if (textToSummarize.isEmpty) {
      throw Exception('No content available to summarize');
    }

    // Generate new summary
    final summary = await summarize(textToSummarize);

    // Check settings to see if we should auto-save summaries
    final prefs = await SharedPreferences.getInstance();
    final autoSave = prefs.getBool(SettingsProvider.autoSaveSummariesKey) ?? true;

    // Save summary to database if auto-save is enabled
    if (autoSave) {
      try {
        await _databaseService.updateArticleSummary(article.id, summary);
        print('Summary automatically saved for article: ${article.id}');
      } catch (e) {
        print('Failed to save summary to database: $e');
        // Continue even if saving fails
      }
    }

    return summary;
  }

  // Method to manually save a summary (for when auto-save is disabled)
  Future<void> saveSummary(String articleId, String summary) async {
    try {
      await _databaseService.updateArticleSummary(articleId, summary);
    } catch (e) {
      throw Exception('Failed to save summary: $e');
    }
  }

  // Method for basic content summarization (used by tests)
  Future<String> summarizeContent(String? content) async {
    if (content == null || content.trim().isEmpty) {
      return '';
    }

    // If content is too short (less than 100 characters), return as-is
    if (content.trim().length < 100) {
      return content.trim();
    }

    try {
      return await summarize(content);
    } catch (e) {
      // On error, return original content (graceful degradation for tests)
      print('Summarization failed: $e');
      return content;
    }
  }

  Future<String> _retryWithFallback(String provider, String text, SettingsProvider settingsProvider) async {
    int retries = 0;
    const maxRetries = 2;
    String currentProvider = provider;

    while (retries < maxRetries) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final apiKey = prefs.getString(_getKeyForProvider(currentProvider)) ?? '';

        final model = settingsProvider.getModelForProvider(currentProvider);
        switch (currentProvider) {
          case SettingsProvider.providerOpenAI:
            return await _summarizeOpenAI(text, apiKey, model);
          case SettingsProvider.providerOpenRouter:
            return await _summarizeOpenRouter(text, apiKey, model);
          case SettingsProvider.providerClaude:
            return await _summarizeClaude(text, apiKey, model);
          case SettingsProvider.providerGemini:
            return await _summarizeGemini(text, apiKey, model);
          case SettingsProvider.providerPerplexity:
            return await _summarizePerplexity(text, apiKey, model);
          case SettingsProvider.providerNvidia:
            return await _summarizeNvidia(text, apiKey, model);
          default:
            throw Exception('Provider $currentProvider not supported');
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 || e.response?.statusCode == 503) {
          // Try fallback provider on rate limit or service unavailable
          final nextProvider = settingsProvider.getNextAvailableProvider(currentProvider);
          if (nextProvider != null && retries < maxRetries - 1) {
            retries++;
            currentProvider = nextProvider;
            await Future.delayed(Duration(seconds: 2));
            continue;
          } else {
            throw Exception('Rate limit exceeded on all configured providers. Please wait and try again.');
          }
        } else if (e.response?.statusCode == 401) {
          throw Exception('Invalid API key for $currentProvider. Please check your API key in Settings.');
        } else if (e.response?.statusCode == 403) {
          throw Exception('Access forbidden for $currentProvider. Please check your API key permissions or billing status.');
        } else if (e.response?.statusCode == 400) {
          throw Exception('Invalid request for $currentProvider. The text might be too long or contain unsupported content. \n message:  ${e.message}');
        } else {
          throw Exception('Network error with $currentProvider: ${e.message}');
        }
      } catch (e) {
        throw Exception('Summarization failed with $currentProvider: $e');
      }
    }
    throw Exception('Max retries exceeded on all available providers');
  }

  String _getKeyForProvider(String provider) {
    switch (provider) {
      case SettingsProvider.providerOpenAI:
        return SettingsProvider.openaiKey;
      case SettingsProvider.providerOpenRouter:
        return SettingsProvider.openrouterKey;
      case SettingsProvider.providerGemini:
        return SettingsProvider.geminiKey;
      case SettingsProvider.providerClaude:
        return SettingsProvider.claudeKey;
      case SettingsProvider.providerPerplexity:
        return SettingsProvider.perplexityKey;
      case SettingsProvider.providerNvidia:
        return SettingsProvider.nvidiaKey;
      default:
        return SettingsProvider.openaiKey;
    }
  }

  Future<String> _summarizeOpenAI(String text, String apiKey, String model) async {
    const url = 'https://api.openai.com/v1/chat/completions';
    final response = await _dio.post(url,
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
      ),
      data: {
        'model': model.isNotEmpty ? model : 'gpt-4o-mini',
        'messages': [
          {'role': 'system', 'content': 'Summarize the following text in a concise, clear manner.'},
          {'role': 'user', 'content': text},
        ],
        'max_tokens': 300,
        'temperature': 0.3,
      },
    );
    final content = response.data['choices'][0]['message']['content'];
    return content as String;
  }

  Future<String> _summarizeOpenRouter(String text, String apiKey, String model) async {
    const url = 'https://openrouter.ai/api/v1/chat/completions';
    final response = await _dio.post(url,
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'https://github.com/freead/freead',
        'X-Title': 'FreeAd RSS Reader',
      }),
      data: {
        'model': model.isNotEmpty ? model : 'google/gemini-flash-1.5-8b',
        'messages': [
          {'role': 'system', 'content': 'Summarize the following text.'},
          {'role': 'user', 'content': text},
        ],
      },
    );
    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<String> _summarizeClaude(String text, String apiKey, String model) async {
    const url = 'https://api.anthropic.com/v1/messages';

    try {
      final response = await _dio.post(url,
        options: Options(headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        }),
        data: {
          'model': model.isNotEmpty ? model : 'claude-3-5-haiku-20241022',
          'max_tokens': 1000,
          'messages': [
            {
              'role': 'user',
              'content': 'Please summarize the following text:\n\n$text'
            }
          ],
        },
      );

      // Claude Messages API response structure
      if (response.data['content'] != null && response.data['content'].isNotEmpty) {
        return response.data['content'][0]['text'] as String;
      } else {
        throw Exception('Empty response from Claude API');
      }
    } on DioException catch (e) {
      // Log the full error response for debugging
      print('Claude API Error - Status: ${e.response?.statusCode}');
      print('Claude API Error - Response: ${e.response?.data}');

      if (e.response?.statusCode == 400) {
        final errorMessage = e.response?.data['error']?['message'] ?? 'Invalid request';
        throw Exception('Claude API: $errorMessage (Status: ${e.response?.statusCode})');
      } else if (e.response?.statusCode == 401) {
        throw Exception('Claude API: Invalid API key. Please check your Claude API key in settings.');
      } else if (e.response?.statusCode == 403) {
        throw Exception('Claude API: Access forbidden. Check API key permissions or billing status.');
      } else if (e.response?.statusCode == 429) {
        throw Exception('Claude API: Rate limit exceeded. Please try again later.');
      } else {
        throw Exception('Claude API error: ${e.message} (Status: ${e.response?.statusCode})');
      }
    } catch (e) {
      throw Exception('Claude summarization failed: $e');
    }
  }

  // Fix Gemini summarization to use proper Google AI API
  Future<String> _summarizeGemini(String text, String apiKey, String model) async {
    final modelName = model.isNotEmpty ? model : 'gemini-1.5-flash';
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey';
    final response = await _dio.post(url,
      options: Options(headers: {
        'Content-Type': 'application/json'
      }),
      data: {
        'contents': [{
          'parts': [{
            'text': 'Please summarize the following text:\n\n$text'
          }]
        }]
      },
    );
    return response.data['candidates'][0]['content']['parts'][0]['text'] as String;
  }

  Future<String> _summarizePerplexity(String text, String apiKey, String model) async {
    const url = 'https://api.perplexity.ai/chat/completions';
    final response = await _dio.post(url,
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': model.isNotEmpty ? model : 'llama-3.1-8b-instruct',
        'messages': [
          {'role': 'user', 'content': 'Please provide a concise summary of the following text:\n\n$text'}
        ],
        'max_tokens': 300,
        'temperature': 0.3,
      },
    );
    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<String> _summarizeNvidia(String text, String apiKey, String model) async {
    const url = 'https://integrate.api.nvidia.com/v1/chat/completions';
    final response = await _dio.post(url,
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': model.isNotEmpty ? model : 'nvidia/llama-3.1-405b-instruct',
        'messages': [
          {'role': 'user', 'content': 'Please provide a concise summary of the following text:\n\n$text'}
        ],
        'max_tokens': 300,
        'temperature': 0.3,
      },
    );
    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<List<String>> fetchAvailableModels(String provider, String apiKey) async {
    try {
      String url = '';
      Map<String, dynamic> headers = {};

      switch (provider) {
        case SettingsProvider.providerOpenAI:
          url = 'https://api.openai.com/v1/models';
          headers = {'Authorization': 'Bearer $apiKey'};
          break;
        case SettingsProvider.providerOpenRouter:
          url = 'https://openrouter.ai/api/v1/models';
          headers = {'Authorization': 'Bearer $apiKey'};
          break;
        case SettingsProvider.providerNvidia:
          url = 'https://integrate.api.nvidia.com/v1/models';
          headers = {'Authorization': 'Bearer $apiKey'};
          break;
        default:
          return [];
      }

      final response = await _dio.get(url, options: Options(headers: headers));
      final List<dynamic> data = response.data['data'];

      if (provider == SettingsProvider.providerOpenRouter) {
        return data.map((m) => m['id'] as String).toList();
      } else {
        // Filter for chat models if possible, otherwise return all
        return data.map((m) => m['id'] as String).toList();
      }
    } catch (e) {
      print('Error fetching models for $provider: $e');
      return [];
    }
  }
}
