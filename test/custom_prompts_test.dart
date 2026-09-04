import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/app_settings.dart';
import 'package:freead/models/article.dart';
import 'package:freead/models/chat_message.dart';
import 'package:freead/models/saved_prompt.dart';
import 'package:freead/providers/ai_chat_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/services/ai/ai_models.dart';
import 'package:freead/services/ai/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A dio adapter that never touches the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var body = '';
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      body = utf8.decode(bytes);
    }
    bodies.add(body);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _completion(String text) => ResponseBody.fromString(
  jsonEncode({
    'choices': [
      {
        'message': {'content': text},
      },
    ],
  }),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

const _openAiConfig = AiConfig(
  provider: AiProvider.openai,
  apiKey: 'sk-test',
  model: 'gpt-4o-mini',
);

AiService _service(_FakeAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return AiService(configSource: StaticAiConfigSource(_openAiConfig), dio: dio);
}

Article _article() => Article(
  id: 'article-1',
  title: 'Test headline',
  description: 'A short description.',
  content: '<p>Some body text for the article.</p>',
  url: 'https://example.com/story',
  publishedDate: DateTime(2026, 8, 30, 9, 30),
  feedId: 'feed-1',
  dateAdded: DateTime(2026, 8, 30, 10),
);

Future<SettingsProvider> _settings() async {
  final provider = SettingsProvider();
  await provider.init();
  return provider;
}

void _mockChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async => null,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('withCustomInstructions', () {
    const base = 'Base system prompt.';

    test('returns the base prompt unchanged without instructions', () {
      expect(withCustomInstructions(base, null), base);
      expect(withCustomInstructions(base, ''), base);
      expect(withCustomInstructions(base, '   '), base);
    });

    test('appends non-blank instructions after the base prompt', () {
      final result = withCustomInstructions(base, 'Reply in French.');
      expect(result, startsWith(base));
      expect(result, contains('Reply in French.'));
    });

    test('the default summary prompt carries no custom marker', () {
      expect(
        summaryStyleInstruction(SummaryStyle.brief),
        isNot(contains('user instructions')),
      );
    });
  });

  group('SavedPrompt model', () {
    test('json round trip preserves every field', () {
      final prompt = SavedPrompt(
        id: '123',
        title: 'Explain simply',
        prompt: 'Explain like I am 12.',
        createdAt: DateTime(2026, 1, 2, 3, 4, 5),
      );
      final restored = SavedPrompt.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(prompt.toJson()))),
      );
      expect(restored.id, '123');
      expect(restored.title, 'Explain simply');
      expect(restored.prompt, 'Explain like I am 12.');
      expect(restored.createdAt, DateTime(2026, 1, 2, 3, 4, 5));
      expect(restored, prompt);
    });
  });

  group('SettingsProvider custom prompts', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _mockChannels();
    });

    test('defaults are empty', () async {
      final settings = await _settings();
      expect(settings.customInstructions, '');
      expect(settings.savedPrompts, isEmpty);
      settings.dispose();
    });

    test('custom instructions round trip and trim', () async {
      final settings = await _settings();
      await settings.setCustomInstructions('  Reply in French.  ');
      expect(settings.customInstructions, 'Reply in French.');

      final reloaded = await _settings();
      expect(reloaded.customInstructions, 'Reply in French.');
      settings.dispose();
      reloaded.dispose();
    });

    test('clearing instructions persists the empty value', () async {
      final settings = await _settings();
      await settings.setCustomInstructions('something');
      await settings.setCustomInstructions('   ');
      expect(settings.customInstructions, '');

      final reloaded = await _settings();
      expect(reloaded.customInstructions, '');
      settings.dispose();
      reloaded.dispose();
    });

    test('saved prompt CRUD round trip', () async {
      final settings = await _settings();

      final created = await settings.addSavedPrompt(
        title: 'Explain simply',
        prompt: 'Explain like I am 12.',
      );
      expect(created, isNotNull);
      expect(settings.savedPrompts, hasLength(1));

      await settings.updateSavedPrompt(created!.copyWith(title: 'ELI12'));
      expect(settings.savedPrompts.single.title, 'ELI12');
      expect(settings.savedPrompts.single.prompt, 'Explain like I am 12.');

      final reloaded = await _settings();
      expect(reloaded.savedPrompts.single.title, 'ELI12');

      await settings.deleteSavedPrompt(created.id);
      expect(settings.savedPrompts, isEmpty);
      settings.dispose();
      reloaded.dispose();
    });

    test('blank prompts are rejected and unknown ids are no-ops', () async {
      final settings = await _settings();
      expect(
        await settings.addSavedPrompt(title: '  ', prompt: 'Hello'),
        isNull,
      );
      expect(await settings.addSavedPrompt(title: 'Hi', prompt: '   '), isNull);
      expect(settings.savedPrompts, isEmpty);

      await settings.updateSavedPrompt(
        SavedPrompt(
          id: 'missing',
          title: 'x',
          prompt: 'y',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await settings.deleteSavedPrompt('missing');
      expect(settings.savedPrompts, isEmpty);
      settings.dispose();
    });

    test('library is capped', () async {
      final settings = await _settings();
      for (var i = 0; i < SettingsProvider.maxSavedPrompts; i++) {
        final created = await settings.addSavedPrompt(
          title: 'Prompt $i',
          prompt: 'Do thing $i.',
        );
        expect(created, isNotNull);
      }
      expect(
        await settings.addSavedPrompt(title: 'One more', prompt: 'Nope.'),
        isNull,
      );
      expect(
        settings.savedPrompts,
        hasLength(SettingsProvider.maxSavedPrompts),
      );
      settings.dispose();
    });

    test('malformed stored json loads as empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsProvider.savedPromptsKey: 'not-json{{{',
      });
      final settings = await _settings();
      expect(settings.savedPrompts, isEmpty);
      settings.dispose();
    });
  });

  group('AiChatProvider custom instructions', () {
    test('default system prompt is unchanged', () {
      final provider = AiChatProvider(
        article: _article(),
        ai: _service(_FakeAdapter((_) => _completion('hi'))),
      );
      expect(provider.systemPrompt, isNot(contains('user instructions')));
      expect(provider.systemPrompt, contains('Test headline'));
      provider.dispose();
    });

    test('custom instructions are appended to the system prompt', () {
      final provider = AiChatProvider(
        article: _article(),
        ai: _service(_FakeAdapter((_) => _completion('hi'))),
        customInstructions: 'Reply in French.',
      );
      expect(provider.systemPrompt, contains('Reply in French.'));
      expect(provider.systemPrompt, contains('Test headline'));
      provider.dispose();
    });
  });

  group('AiService.summarize custom instructions', () {
    test('custom instructions reach the request system prompt', () async {
      final adapter = _FakeAdapter((_) => _completion('summary'));
      final service = _service(adapter);

      final result = await service.summarize(
        'Some long article text. ' * 20,
        customInstructions: 'Reply in French.',
      );
      expect(result, 'summary');
      expect(adapter.bodies, hasLength(1));
      final body = jsonDecode(adapter.bodies.single) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final system = (messages.first as Map)['content'] as String;
      expect(system, contains('Reply in French.'));
    });

    test('default summarize sends the plain style prompt', () async {
      final adapter = _FakeAdapter((_) => _completion('summary'));
      final service = _service(adapter);

      await service.summarize('Some long article text. ' * 20);
      final body = jsonDecode(adapter.bodies.single) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final system = (messages.first as Map)['content'] as String;
      expect(system, summaryStyleInstruction(SummaryStyle.brief));
    });
  });

  group('ChatMessage roles', () {
    test('assistant role helper exists for bubbles', () {
      final message = ChatMessage(
        id: 'm1',
        articleId: 'article-1',
        role: ChatRole.assistant,
        content: 'Hello',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(message.isAssistant, isTrue);
    });
  });
}
