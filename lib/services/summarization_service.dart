import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/article.dart';
import '../providers/settings_provider.dart';

class SummarizationService {
  final Dio _dio = Dio();

  SummarizationService() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
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
    final provider = prefs.getString('summarization_provider') ?? SettingsProvider.providerGemini;
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
        default:
          return 'Provider $provider not fully implemented in this update.';
      }
    } catch (e) {
      return 'Summarization failed: $e';
    }
  }

  Future<String> _getApiKey(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    switch (provider) {
      case SettingsProvider.providerOpenAI: return prefs.getString(SettingsProvider.openaiKey) ?? '';
      case SettingsProvider.providerGemini: return prefs.getString(SettingsProvider.geminiKey) ?? '';
      default: return '';
    }
  }

  Future<String> _summarizeOpenAI(String text, String apiKey) async {
    const url = 'https://api.openai.com/v1/chat/completions';
    final response = await _dio.post(url,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      data: {
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'system', 'content': 'Summarize the following text concisely.'},
          {'role': 'user', 'content': text},
        ],
      },
    );
    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<String> _summarizeGemini(String text, String apiKey) async {
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey';
    final response = await _dio.post(url,
      data: {
        'contents': [{'parts': [{'text': 'Summarize this: $text'}]}]
      },
    );
    return response.data['candidates'][0]['content']['parts'][0]['text'] as String;
  }

  Future<List<String>> fetchAvailableModels(String provider, String apiKey) async {
    return ['default-model'];
  }
}
