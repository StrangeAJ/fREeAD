import 'package:flutter_test/flutter_test.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider Tests', () {
    late SettingsProvider settingsProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
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

      // Verify it persists (re-init)
      final newProvider = SettingsProvider();
      await newProvider.init();
      expect(newProvider.openaiModel, equals('gpt-4o'));
    });

    test('should return correct model for provider', () {
      expect(settingsProvider.getModelForProvider(SettingsProvider.providerOpenAI), equals('gpt-4o-mini'));
      expect(settingsProvider.getModelForProvider(SettingsProvider.providerNvidia), equals('nvidia/llama-3.1-405b-instruct'));
    });

    test('should add Nvidia NIM to available providers', () {
      final providers = settingsProvider.availableAiProviders.map((e) => e.key).toList();
      expect(providers, contains(SettingsProvider.providerNvidia));
    });
  });
}
