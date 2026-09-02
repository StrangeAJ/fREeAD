import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/app_settings.dart';
import 'package:freead/models/article.dart';
import 'package:freead/models/chat_message.dart';
import 'package:freead/providers/ai_chat_provider.dart';
import 'package:freead/services/ai/ai_adapters.dart';
import 'package:freead/services/ai/ai_models.dart';
import 'package:freead/services/ai/ai_service.dart';
import 'package:freead/services/ai/article_chat_repository.dart';

/// One captured outgoing request.
class RecordedCall {
  RecordedCall(this.options, this.body);

  final RequestOptions options;
  final String body;

  Map<String, dynamic> get json => body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(body) as Map<String, dynamic>;
}

/// A dio adapter that never touches the network.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options, int callIndex)
  handler;

  final List<RecordedCall> calls = <RecordedCall>[];

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
    final index = calls.length;
    calls.add(RecordedCall(options, body));
    return handler(options, index);
  }

  @override
  void close({bool force = false}) {}
}

/// Splits [payload] into small chunks so parsing has to survive boundaries
/// that fall in the middle of a line (and of a JSON token).
Stream<Uint8List> chunked(String payload, {int chunkSize = 7}) async* {
  final bytes = utf8.encode(payload);
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = i + chunkSize > bytes.length ? bytes.length : i + chunkSize;
    yield Uint8List.fromList(bytes.sublist(i, end));
  }
}

ResponseBody sseBody(String payload, {int status = 200, int chunkSize = 7}) =>
    ResponseBody(
      chunked(payload, chunkSize: chunkSize),
      status,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );

ResponseBody jsonBody(Object json, {int status = 200}) =>
    ResponseBody.fromString(
      json is String ? json : jsonEncode(json),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

AiService serviceFor(AiConfig config, FakeHttpAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return AiService(configSource: StaticAiConfigSource(config), dio: dio);
}

const claudeConfig = AiConfig(
  provider: AiProvider.claude,
  apiKey: 'sk-ant-test',
  model: 'claude-opus-5',
);

const openAiConfig = AiConfig(
  provider: AiProvider.openai,
  apiKey: 'sk-test',
  model: 'gpt-4o-mini',
);

const geminiConfig = AiConfig(
  provider: AiProvider.gemini,
  apiKey: 'gm-test',
  model: 'gemini-2.5-flash',
);

void main() {
  group('Claude adapter', () {
    const sse = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message"}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", world"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}
''';

    test('streams text deltas across chunk boundaries', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(sse, chunkSize: 5));
      final service = serviceFor(claudeConfig, adapter);

      final chunks = await service.chatStream(const [
        AiMessage.user('Hi'),
      ], system: 'Be nice').toList();

      expect(chunks.join(), 'Hello, world');
      expect(chunks.length, 2);
    });

    test('sends the documented request shape and headers', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(sse));
      final service = serviceFor(claudeConfig, adapter);

      await service.chatStream(const [
        AiMessage.user('Hi'),
      ], system: 'Be nice').toList();

      final call = adapter.calls.single;
      expect(call.options.uri.toString(), kAnthropicMessagesUrl);
      expect(call.options.headers['x-api-key'], 'sk-ant-test');
      expect(call.options.headers['anthropic-version'], kAnthropicVersion);
      expect(call.options.headers['content-type'], 'application/json');

      final body = call.json;
      expect(body['model'], 'claude-opus-5');
      expect(body['max_tokens'], AiLimits.chatMaxTokens);
      expect(body['stream'], true);
      expect(body['system'], 'Be nice');
      expect(body['messages'], [
        {'role': 'user', 'content': 'Hi'},
      ]);
      // Forbidden by the v3 spec.
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('output_config'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
    });

    test('never appends a date suffix to the default model', () {
      expect(AiService.defaultModelFor(AiProvider.claude), 'claude-opus-5');
      for (final model in AiService.fallbackModelsFor(AiProvider.claude)) {
        expect(RegExp(r'-\d{8}$').hasMatch(model), isFalse, reason: model);
      }
      expect(
        AiService.fallbackModelsFor(AiProvider.claude),
        containsAll(<String>[
          'claude-opus-5',
          'claude-sonnet-5',
          'claude-haiku-4-5',
          'claude-opus-4-8',
        ]),
      );
    });

    test('surfaces stop_reason == refusal', () async {
      const refusalSse = '''
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}
''';
      final adapter = FakeHttpAdapter((_, __) => sseBody(refusalSse));
      final service = serviceFor(claudeConfig, adapter);

      await expectLater(
        service.chatStream(const [AiMessage.user('Hi')]).toList(),
        throwsA(
          isA<AiException>()
              .having((e) => e.isRefusal, 'isRefusal', isTrue)
              .having(
                (e) => e.userMessage,
                'userMessage',
                contains('declined this request'),
              ),
        ),
      );
    });

    test('non-streaming completion joins text blocks', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => jsonBody({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': 'Part one. '},
            {'type': 'text', 'text': 'Part two.'},
          ],
        }),
      );
      final service = serviceFor(claudeConfig, adapter);

      expect(
        await service.chat(const [AiMessage.user('Hi')]),
        'Part one. Part two.',
      );
      expect(adapter.calls.single.json['stream'], false);
    });
  });

  group('OpenAI-compatible adapter', () {
    const sse = '''
data: {"choices":[{"delta":{"role":"assistant","content":""}}]}

data: {"choices":[{"delta":{"content":"Streamed "}}]}

data: {"choices":[{"delta":{"content":"answer"}}]}

data: [DONE]
''';

    test('streams delta content and stops at [DONE]', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(sse, chunkSize: 3));
      final service = serviceFor(openAiConfig, adapter);

      final text = (await service.chatStream(const [
        AiMessage.user('Hi'),
      ], system: 'sys').toList()).join();

      expect(text, 'Streamed answer');
      final body = adapter.calls.single.json;
      expect(
        adapter.calls.single.options.uri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(body['stream'], true);
      expect(body['messages'], [
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': 'Hi'},
      ]);
      expect(
        adapter.calls.single.options.headers['Authorization'],
        'Bearer sk-test',
      );
    });

    test('OpenRouter adds the attribution headers', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(sse));
      final service = serviceFor(
        const AiConfig(
          provider: AiProvider.openrouter,
          apiKey: 'or-key',
          model: 'openai/gpt-4o-mini',
        ),
        adapter,
      );

      await service.chatStream(const [AiMessage.user('Hi')]).toList();

      final headers = adapter.calls.single.options.headers;
      expect(headers['HTTP-Referer'], kOpenRouterReferer);
      expect(headers['X-Title'], kOpenRouterTitle);
      expect(
        adapter.calls.single.options.uri.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
    });

    test('Ollama posts to <base>/v1 and needs no key', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(sse));
      final service = serviceFor(
        const AiConfig(
          provider: AiProvider.ollama,
          apiKey: '',
          model: 'llama3.2',
          baseUrl: 'http://192.168.1.5:11434/',
        ),
        adapter,
      );

      await service.chatStream(const [AiMessage.user('Hi')]).toList();

      expect(
        adapter.calls.single.options.uri.toString(),
        'http://192.168.1.5:11434/v1/chat/completions',
      );
      expect(
        adapter.calls.single.options.headers['Authorization'],
        'Bearer ollama',
      );
    });

    test(
      'retries without streaming on a 400 that mentions streaming',
      () async {
        final adapter = FakeHttpAdapter((options, index) {
          if (index == 0) {
            return sseBody(
              jsonEncode({
                'error': {'message': 'stream is not supported for this model'},
              }),
              status: 400,
            );
          }
          return jsonBody({
            'choices': [
              {
                'message': {'content': 'Whole answer'},
              },
            ],
          });
        });
        final service = serviceFor(openAiConfig, adapter);

        final text = (await service.chatStream(const [
          AiMessage.user('Hi'),
        ]).toList()).join();

        expect(text, 'Whole answer');
        expect(adapter.calls, hasLength(2));
        expect(adapter.calls[0].json['stream'], true);
        expect(adapter.calls[1].json['stream'], false);
      },
    );
  });

  group('Gemini adapter', () {
    const sse = '''
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Gemini "}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":"says hi"}]}}]}
''';

    test('streams candidate parts and builds the documented body', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(sse, chunkSize: 9));
      final service = serviceFor(geminiConfig, adapter);

      final text = (await service.chatStream(const [
        AiMessage.user('Hi'),
        AiMessage.assistant('Hello'),
        AiMessage.user('More'),
      ], system: 'Be brief').toList()).join();

      expect(text, 'Gemini says hi');

      final call = adapter.calls.single;
      expect(
        call.options.uri.toString(),
        '$kGeminiBaseUrl/models/gemini-2.5-flash:streamGenerateContent?alt=sse',
      );
      expect(call.options.headers['x-goog-api-key'], 'gm-test');

      final body = call.json;
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'Be brief'},
        ],
      });
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'Hi'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'Hello'},
          ],
        },
        {
          'role': 'user',
          'parts': [
            {'text': 'More'},
          ],
        },
      ]);
    });
  });

  group('error mapping', () {
    test('401 becomes an auth error', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => sseBody(
          jsonEncode({
            'error': {'message': 'invalid x-api-key'},
          }),
          status: 401,
        ),
      );
      final service = serviceFor(claudeConfig, adapter);

      await expectLater(
        service.chatStream(const [AiMessage.user('Hi')]).toList(),
        throwsA(
          isA<AiException>()
              .having((e) => e.isAuth, 'isAuth', isTrue)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having(
                (e) => e.userMessage,
                'userMessage',
                allOf(contains('Claude'), contains('invalid x-api-key')),
              ),
        ),
      );
    });

    test('429 becomes a rate limit error', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => sseBody(
          jsonEncode({
            'error': {'message': 'slow down'},
          }),
          status: 429,
        ),
      );
      final service = serviceFor(openAiConfig, adapter);

      await expectLater(
        service.chatStream(const [AiMessage.user('Hi')]).toList(),
        throwsA(
          isA<AiException>()
              .having((e) => e.isRateLimit, 'isRateLimit', isTrue)
              .having((e) => e.statusCode, 'statusCode', 429),
        ),
      );
    });

    test(
      'timeouts become network errors, never raw DioException text',
      () async {
        final adapter = FakeHttpAdapter(
          (options, _) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          ),
        );
        final service = serviceFor(geminiConfig, adapter);

        await expectLater(
          service.chatStream(const [AiMessage.user('Hi')]).toList(),
          throwsA(
            isA<AiException>()
                .having((e) => e.isNetwork, 'isNetwork', isTrue)
                .having(
                  (e) => e.userMessage,
                  'userMessage',
                  allOf(contains('timed out'), isNot(contains('DioException'))),
                ),
          ),
        );
      },
    );

    test('a missing API key never reaches the network', () async {
      final adapter = FakeHttpAdapter((_, __) => jsonBody({}));
      final service = serviceFor(
        const AiConfig(
          provider: AiProvider.openai,
          apiKey: '',
          model: 'gpt-4o-mini',
        ),
        adapter,
      );

      await expectLater(
        service.chatStream(const [AiMessage.user('Hi')]).toList(),
        throwsA(
          isA<AiException>().having(
            (e) => e.userMessage,
            'userMessage',
            allOf(contains('No API key configured'), contains('OpenAI')),
          ),
        ),
      );
      expect(adapter.calls, isEmpty);
    });
  });

  group('summarize', () {
    test('uses the style prompt and truncates long input', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => jsonBody({
          'choices': [
            {
              'message': {'content': '- one\n- two'},
            },
          ],
        }),
      );
      final service = serviceFor(openAiConfig, adapter);

      final result = await service.summarize(
        'x' * (AiLimits.maxInputChars + 500),
        style: SummaryStyle.bullets,
      );

      expect(result, '- one\n- two');
      final messages = adapter.calls.single.json['messages'] as List;
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('bullet points'));
      expect(
        messages.last['content'].toString().endsWith(AiLimits.truncationNote),
        isTrue,
      );
      expect(adapter.calls.single.json['model'], 'gpt-4o-mini');
    });
  });

  group('fetchAvailableModels', () {
    test('reads data[].id for OpenAI', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => jsonBody({
          'data': [
            {'id': 'gpt-4o'},
            {'id': 'gpt-4o-mini'},
          ],
        }),
      );
      final service = serviceFor(openAiConfig, adapter);

      expect(await service.fetchAvailableModels(AiProvider.openai), [
        'gpt-4o',
        'gpt-4o-mini',
      ]);
      expect(
        adapter.calls.single.options.uri.toString(),
        'https://api.openai.com/v1/models',
      );
    });

    test('keeps only Gemini models that support generateContent', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => jsonBody({
          'models': [
            {
              'name': 'models/gemini-2.5-flash',
              'supportedGenerationMethods': ['generateContent'],
            },
            {
              'name': 'models/text-embedding-004',
              'supportedGenerationMethods': ['embedContent'],
            },
          ],
        }),
      );
      final service = serviceFor(geminiConfig, adapter);

      expect(await service.fetchAvailableModels(AiProvider.gemini), [
        'gemini-2.5-flash',
      ]);
    });

    test('falls back to the static list when the request fails', () async {
      final adapter = FakeHttpAdapter(
        (options, _) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      final service = serviceFor(claudeConfig, adapter);

      expect(
        await service.fetchAvailableModels(AiProvider.claude),
        AiService.fallbackModelsFor(AiProvider.claude),
      );
    });
  });

  group('testConnection', () {
    test('reports success', () async {
      final adapter = FakeHttpAdapter(
        (_, __) => jsonBody({
          'content': [
            {'type': 'text', 'text': 'OK'},
          ],
        }),
      );
      final service = serviceFor(claudeConfig, adapter);

      final result = await service.testConnection(AiProvider.claude);
      expect(result.ok, isTrue);
      expect(result.message, contains('claude-opus-5'));
    });

    test('reports a friendly failure', () async {
      final adapter = FakeHttpAdapter((_, __) => jsonBody({}, status: 403));
      final service = serviceFor(claudeConfig, adapter);

      final result = await service.testConnection(AiProvider.claude);
      expect(result.ok, isFalse);
      expect(result.message, contains('rejected the API key'));
    });
  });

  group('AiProvider', () {
    test('ids stay in sync with the settings strings', () {
      expect(AiProvider.values.map((p) => p.id).toList(), [
        'openai',
        'claude',
        'gemini',
        'openrouter',
        'perplexity',
        'nvidia',
        'ollama',
      ]);
      expect(AiProvider.fromId('nvidia'), AiProvider.nvidia);
      expect(AiProvider.fromId('nope'), AiProvider.gemini);
      expect(AiProvider.tryFromId('nope'), isNull);
      expect(AiProvider.ollama.requiresApiKey, isFalse);
    });

    test('normalizeBaseUrl adds a scheme and trims slashes', () {
      expect(normalizeBaseUrl('localhost:11434/'), 'http://localhost:11434');
      expect(normalizeBaseUrl('https://ai.local//'), 'https://ai.local');
      expect(normalizeBaseUrl('  '), kDefaultOllamaBaseUrl);
    });
  });

  group('AiChatProvider', () {
    const chatSse = '''
data: {"choices":[{"delta":{"content":"The article "}}]}

data: {"choices":[{"delta":{"content":"says hello."}}]}

data: [DONE]
''';

    Article buildArticle({String? fullContent}) => Article(
      id: 'article-1',
      title: 'Quiet instruments',
      description: 'A short RSS excerpt about calm software.',
      content: '<p>A short RSS excerpt about calm software.</p>',
      fullContent: fullContent,
      url: 'https://example.com/quiet',
      siteName: 'Example',
      publishedDate: DateTime(2026, 1, 2),
      feedId: 'feed-1',
      dateAdded: DateTime(2026, 1, 2),
    );

    test('load restores stored messages and the provider label', () async {
      final repo = InMemoryChatRepository()
        ..seed('article-1', ChatRole.user, 'Earlier question')
        ..seed('article-1', ChatRole.assistant, 'Earlier answer');
      final adapter = FakeHttpAdapter((_, __) => sseBody(chatSse));
      final provider = AiChatProvider(
        article: buildArticle(),
        ai: serviceFor(claudeConfig, adapter),
        repo: repo,
      );

      await provider.load();

      expect(provider.isLoaded, isTrue);
      expect(provider.messages.map((m) => m.content), [
        'Earlier question',
        'Earlier answer',
      ]);
      expect(provider.providerLabel, 'Claude');
      expect(provider.model, 'claude-opus-5');
      provider.dispose();
    });

    test(
      'send streams, persists both turns and builds the system prompt',
      () async {
        final repo = InMemoryChatRepository();
        final adapter = FakeHttpAdapter(
          (_, __) => sseBody(chatSse, chunkSize: 4),
        );
        final provider = AiChatProvider(
          article: buildArticle(),
          ai: serviceFor(openAiConfig, adapter),
          repo: repo,
        );
        await provider.load();

        final partials = <String>[];
        provider.addListener(() {
          if (provider.isStreaming) partials.add(provider.partialResponse);
        });

        await provider.send('  What does it say?  ');

        expect(provider.isStreaming, isFalse);
        expect(provider.error, isNull);
        expect(provider.partialResponse, isEmpty);
        expect(provider.messages.map((m) => m.role), [
          ChatRole.user,
          ChatRole.assistant,
        ]);
        expect(provider.messages.first.content, 'What does it say?');
        expect(provider.messages.last.content, 'The article says hello.');
        expect(partials, contains('The article '));
        expect(repo.stored['article-1']!.map((m) => m.content).toList(), [
          'What does it say?',
          'The article says hello.',
        ]);

        final body = adapter.calls.single.json;
        final messages = body['messages'] as List;
        final system = messages.first['content'] as String;
        expect(
          system,
          contains('You are a reading assistant inside an RSS reader'),
        );
        expect(system, contains('Title: Quiet instruments'));
        expect(system, contains('Site: Example'));
        expect(system, contains('URL: https://example.com/quiet'));
        expect(system, contains('A short RSS excerpt about calm software.'));
        expect(system, isNot(contains('<p>')));
        expect(messages.last, {'role': 'user', 'content': 'What does it say?'});
        provider.dispose();
      },
    );

    test(
      'errors surface as a user-safe message with nothing persisted',
      () async {
        final repo = InMemoryChatRepository();
        final adapter = FakeHttpAdapter(
          (_, __) => sseBody(
            jsonEncode({
              'error': {'message': 'bad key'},
            }),
            status: 401,
          ),
        );
        final provider = AiChatProvider(
          article: buildArticle(),
          ai: serviceFor(openAiConfig, adapter),
          repo: repo,
        );
        await provider.load();

        await provider.send('Hello?');

        expect(provider.error, contains('rejected the API key'));
        expect(provider.messages, hasLength(1));
        expect(provider.messages.single.role, ChatRole.user);
        expect(repo.stored['article-1'], hasLength(1));
        provider.dispose();
      },
    );

    test('clear wipes memory and storage', () async {
      final repo = InMemoryChatRepository()
        ..seed('article-1', ChatRole.user, 'Hi');
      final adapter = FakeHttpAdapter((_, __) => sseBody(chatSse));
      final provider = AiChatProvider(
        article: buildArticle(),
        ai: serviceFor(openAiConfig, adapter),
        repo: repo,
      );
      await provider.load();
      expect(provider.messages, hasLength(1));

      await provider.clear();

      expect(provider.messages, isEmpty);
      expect(provider.isEmpty, isTrue);
      expect(repo.stored['article-1'], anyOf(isNull, isEmpty));
      provider.dispose();
    });

    test('contextInfo distinguishes full articles from RSS excerpts', () async {
      final adapter = FakeHttpAdapter((_, __) => sseBody(chatSse));
      final service = serviceFor(openAiConfig, adapter);

      final excerpt = AiChatProvider(
        article: buildArticle(),
        ai: service,
        repo: InMemoryChatRepository(),
      );
      expect(excerpt.contextInfo, 'RSS excerpt - 7 words');
      excerpt.dispose();

      final full = AiChatProvider(
        article: buildArticle(
          fullContent: '<p>${List.filled(2340, 'word').join(' ')}</p>',
        ),
        ai: service,
        repo: InMemoryChatRepository(),
      );
      expect(full.contextInfo, 'Full article - 2,340 words');
      full.dispose();
    });

    test('offers the documented suggested prompts', () {
      expect(AiChatProvider.suggestedPrompts, hasLength(6));
      expect(AiChatProvider.suggestedPrompts.first, 'Summarize in 3 bullets');
    });
  });
}

/// [ArticleChatRepository] backed by a map instead of sqflite.
class InMemoryChatRepository extends ArticleChatRepository {
  final Map<String, List<ChatMessage>> stored = <String, List<ChatMessage>>{};

  void seed(String articleId, String role, String content) {
    stored
        .putIfAbsent(articleId, () => <ChatMessage>[])
        .add(ArticleChatRepository.newMessage(articleId, role, content));
  }

  @override
  Future<List<ChatMessage>> load(String articleId) async =>
      List<ChatMessage>.from(stored[articleId] ?? const <ChatMessage>[]);

  @override
  Future<bool> appendMessage(ChatMessage message) async {
    stored.putIfAbsent(message.articleId, () => <ChatMessage>[]).add(message);
    return true;
  }

  @override
  Future<void> replaceAll(String articleId, List<ChatMessage> messages) async {
    stored[articleId] = List<ChatMessage>.from(messages);
  }

  @override
  Future<void> clear(String articleId) async {
    stored.remove(articleId);
  }
}
