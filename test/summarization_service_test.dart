import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/summarization_service.dart';
import 'package:freead/models/article.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('SummarizationService Tests', () {
    late SummarizationService summarizationService;

    setUp(() {
      summarizationService = SummarizationService();
    });

    test('should handle empty content gracefully', () async {
      final result = await summarizationService.summarizeContent('');
      expect(result, isEmpty);
    });

    test('should handle null content gracefully', () async {
      final result = await summarizationService.summarizeContent(null);
      expect(result, isEmpty);
    });

    test('should return original content if too short', () async {
      const shortContent = 'This is short.';
      final result = await summarizationService.summarizeContent(shortContent);
      expect(result, equals(shortContent));
    });

    test('should return content on error (graceful degradation)', () async {
      final longContent = 'This is a long content.' * 10;

      final result = await summarizationService.summarizeContent(longContent);
      expect(result, equals(longContent.trim()));
    });

    test('should fetch available models for OpenAI', () async {
       final models = await summarizationService.fetchAvailableModels('openai', 'fake-key');
       expect(models, isA<List<String>>());
    });
  });
}
