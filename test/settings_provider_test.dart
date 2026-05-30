import 'package:flutter_test/flutter_test.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider Tests', () {
    late SettingsProvider settingsProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      // Mock flutter_secure_storage
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage')
          .setMockMethodCallHandler((MethodCall methodCall) async {
        if (methodCall.method == 'read') return null;
        if (methodCall.method == 'write') return null;
        if (methodCall.method == 'delete') return null;
        return null;
      });

      settingsProvider = SettingsProvider();
      await settingsProvider.init();
    });

    test('should have default models', () {
      expect(settingsProvider.openaiModel, equals('gpt-4o-mini'));
      expect(settingsProvider.nvidiaModel, equals('nvidia/llama-3.1-405b-instruct'));
    });

    test('should update and save model', () async {
      await settingsProvider.setOpenaiModel('gpt-4o');
      expect(settingsProvider.openaiModel, equals('gpt-4o'));
    });

    test('should return correct model for provider', () {
      expect(settingsProvider.getModelForProvider(SettingsProvider.providerOpenAI), equals('gpt-4o-mini'));
    });
  });
}
