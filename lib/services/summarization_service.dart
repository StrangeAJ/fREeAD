import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/article.dart';
import '../providers/settings_provider.dart';

class SummarizationService {
  final Dio _dio = Dio();

  SummarizationService() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    // Add validateStatus to avoid Dio throwing exception on 404 (and let us handle it)
    _dio.options.validateStatus = (status) {
      return status != null && status < 500;
    };
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
    final apiKey = await _getApiKey(provider);

    if (apiKey.isEmpty) {
      return 'AI summarization logic has been simplified for this update. Please check your API keys.';
    }

    try {
      switch (provider) {
        case SettingsProvider.providerOpenAI:
          return await _summarizeOpenAI(text, apiKey);
        case SettingsProvider.providerGemini:
          return await _summarizeGemini(text, apiKey);
        case SettingsProvider.providerNvidia:
          return await _summarizeNvidia(text, apiKey);
        default:
          return 'Provider $provider not fully implemented in this update.';
      }
    } on DioException catch (e) {
      if (e.response != null) {
        return 'Network error with $provider: This exception was thrown because the response has a status code of ${e.response?.statusCode} and RequestOptions.validateStatus was configured to throw for this status code.\n\nThe status code of ${e.response?.statusCode} has the following meaning: "Client error - the request contains bad syntax or cannot be fulfilled"\n\nRead more about status codes at https://developer.mozilla.org/en-US/docs/Web/HTTP/Status\n\nIn order to resolve this exception you typically have either to verify and fix your request code or you have to fix the server code.';
      }
      return 'Network error with $provider: ${e.message}';
    } catch (e) {
      return 'Summarization failed: $e';
    }
  }

  Future<String> _getApiKey(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    switch (provider) {
      case SettingsProvider.providerOpenAI:
        return prefs.getString(SettingsProvider.openaiKey) ?? '';
      case SettingsProvider.providerGemini:
        return prefs.getString(SettingsProvider.geminiKey) ?? '';
      case SettingsProvider.providerNvidia:
        return prefs.getString(SettingsProvider.nvidiaKey) ?? '';
      default:
        return '';
    }
  }

  Future<String> _summarizeOpenAI(String text, String apiKey) async {
    const url = 'https://api.openai.com/v1/chat/completions';
    final response = await _dio.post(
      url,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      data: {
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content': 'Summarize the following text concisely.',
          },
          {'role': 'user', 'content': text},
        ],
      },
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<String> _summarizeGemini(String text, String apiKey) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey';
    final response = await _dio.post(
      url,
      data: {
        'contents': [
          {
            'parts': [
              {'text': 'Summarize this: $text'},
            ],
          },
        ],
      },
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    return response.data['candidates'][0]['content']['parts'][0]['text']
        as String;
  }

  Future<String> _summarizeNvidia(String text, String apiKey) async {
    const url = 'https://integrate.api.nvidia.com/v1/chat/completions';
    final prefs = await SharedPreferences.getInstance();
    final model =
        prefs.getString(SettingsProvider.nvidiaModelKey) ??
        'nvidia/llama-3.1-405b-instruct';

    final response = await _dio.post(
      url,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      data: {
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': 'Summarize the following text concisely.',
          },
          {'role': 'user', 'content': text},
        ],
      },
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<List<String>> fetchAvailableModels(
    String provider,
    String apiKey,
  ) async {
    if (provider == SettingsProvider.providerNvidia) {
      return ['nvidia/llama-3.1-405b-instruct'];
    }
    return ['default-model'];
  }
}
