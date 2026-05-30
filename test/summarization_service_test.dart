import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/summarization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SummarizationService Tests', () {
    late SummarizationService summarizationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      // Mock flutter_secure_storage if needed (used by SettingsProvider usually, but SummarizationService might depend on it)
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage')
          .setMockMethodCallHandler((MethodCall methodCall) async {
        return null;
      });

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
      expect(result, contains('AI summarization logic has been simplified'));
    });
  });
}
