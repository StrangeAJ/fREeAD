import '../models/article.dart';

class SummarizationService {
  Future<String> summarizeArticle(Article article) async {
    return 'This is a placeholder summary for "${article.title}". AI summarization logic has been simplified for this update.';
  }

  Future<String> summarizeContent(String? content) async {
    if (content == null || content.isEmpty) return '';
    if (content.length < 50) return content;
    return 'Placeholder content summary.';
  }

  Future<String> summarize(String text) async {
    return 'Placeholder text summary.';
  }

  Future<List<String>> fetchAvailableModels(String provider, String apiKey) async {
    return ['default-model'];
  }
}
