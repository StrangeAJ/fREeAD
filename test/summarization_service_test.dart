import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/summarization_service.dart';
import 'package:freead/models/article.dart';

void main() {
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

    test('should return placeholder summary for long content', () async {
      final longContent = 'A' * 100;
      final result = await summarizationService.summarizeContent(longContent);
      expect(result, equals('Placeholder content summary.'));
    });
  });
}
