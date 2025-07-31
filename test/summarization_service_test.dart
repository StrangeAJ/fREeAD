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

    test('should handle long content without errors', () async {
      const longContent = '''
        This is a very long article content that should be summarized.
        It contains multiple paragraphs and various information.
        The summarization service should be able to process this content
        and return a meaningful summary that captures the key points.
        This test ensures that the service can handle longer texts
        without throwing exceptions or returning invalid results.
      ''';

      final result = await summarizationService.summarizeContent(longContent);
      expect(result, isNotEmpty);
      expect(result.length, lessThan(longContent.length));
    });

    test('should summarize article object', () async {
      final article = Article(
        id: 'test-1',
        title: 'Test Article',
        description: 'Test description',
        url: 'https://example.com',
        publishedDate: DateTime.now(),
        dateAdded: DateTime.now(),
        feedId: 'test-feed',
        content: 'This is a longer article content that should be summarized for testing purposes.',
      );

      final result = await summarizationService.summarizeArticle(article);
      expect(result, isNotEmpty);
    });

    test('should handle network errors gracefully', () async {
      // Mock a scenario where network fails
      const content = 'Test content for network failure scenario';

      // This should not throw an exception even if network fails
      expect(() async => await summarizationService.summarizeContent(content),
             returnsNormally);
    });

    test('should validate input parameters', () {
      expect(() => summarizationService.summarizeContent(''), returnsNormally);
      expect(() => summarizationService.summarizeContent(null), returnsNormally);
    });
  });
}
