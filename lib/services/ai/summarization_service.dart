import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_settings.dart';
import '../../models/article.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_logger.dart';
import 'ai_models.dart';
import 'ai_service.dart';

/// Article summaries.
///
/// Keeps the pre-v3 surface (string results instead of exceptions, provider and
/// model read straight from SharedPreferences + secure storage) while all the
/// HTTP work is delegated to [AiService] and the provider adapters.
class SummarizationService {
  SummarizationService({AiService? aiService, Dio? dio})
    : _ai =
          aiService ?? AiService(configSource: PrefsAiConfigSource(), dio: dio);

  final AiService _ai;

  /// Shortest content worth sending to a model.
  static const int minContentChars = 50;

  /// Summarises [article]'s body, or a friendly message when there is none.
  Future<String> summarizeArticle(Article article) async {
    final text = article.content ?? article.description;
    if (text.isEmpty) return 'No content to summarize.';
    return summarize(text);
  }

  /// Summarises [content]; returns it unchanged when it is too short to bother.
  Future<String> summarizeContent(String? content) async {
    if (content == null || content.isEmpty) return '';
    if (content.length < minContentChars) return content;
    return summarize(content);
  }

  /// Summarises [text], returning an error string rather than throwing.
  Future<String> summarize(String text) async {
    try {
      final style = await _summaryStyle();
      return await _ai.summarize(text, style: style);
    } on AiException catch (e) {
      return e.userMessage;
    } catch (e, st) {
      AppLog.e('Summarization failed', e, st);
      final label = await _providerLabel();
      return 'Summarization with $label failed: $e';
    }
  }

  /// Models offered by [provider] (id string, e.g. `openai`).
  Future<List<String>> fetchAvailableModels(
    String provider,
    String apiKey,
  ) async {
    final resolved = AiProvider.tryFromId(provider);
    if (resolved == null) return const ['default-model'];
    return _ai.fetchAvailableModels(resolved, apiKey: apiKey);
  }

  Future<SummaryStyle> _summaryStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return enumFromName(
        SummaryStyle.values,
        prefs.getString(SettingsProvider.summaryStyleKey),
        SummaryStyle.brief,
      );
    } catch (e) {
      AppLog.w('Could not read summary style', e);
      return SummaryStyle.brief;
    }
  }

  Future<String> _providerLabel() async {
    try {
      return (await _ai.currentConfig()).provider.label;
    } catch (_) {
      return 'the AI provider';
    }
  }
}
