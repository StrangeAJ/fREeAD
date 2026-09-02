import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/category.dart';
import 'package:freead/models/rss_feed.dart';
import 'package:freead/services/ai/ai_models.dart';
import 'package:freead/services/ai/ai_service.dart';
import 'package:freead/services/ai/categorization_service.dart';

/// Minimal dio adapter that replays canned bodies.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.bodies);

  /// One body per call, in order. The last one repeats.
  final List<String> bodies;
  final List<String> requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      requests.add(utf8.decode(bytes));
    } else {
      requests.add('');
    }
    final index = requests.length - 1;
    final body = bodies[index >= bodies.length ? bodies.length - 1 : index];
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String openAiReply(String content) => jsonEncode({
  'choices': [
    {
      'message': {'content': content},
    },
  ],
});

AiService aiWith(FakeHttpAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return AiService(
    configSource: const StaticAiConfigSource(
      AiConfig(
        provider: AiProvider.openai,
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
      ),
    ),
    dio: dio,
  );
}

RSSFeed feed({
  required String id,
  required String title,
  required String url,
  String description = '',
  String? categoryId,
}) => RSSFeed(
  id: id,
  title: title,
  url: url,
  description: description,
  categoryId: categoryId,
  dateAdded: DateTime(2026, 1, 1),
);

void main() {
  final categories = Category.defaultCategories;

  group('quickCategorizeOne - known domains', () {
    final cases = <String, List<String>>{
      // feed url -> [title, expected category]
      'https://techcrunch.com/feed/': ['TechCrunch', 'technology'],
      'https://www.theverge.com/rss/index.xml': ['The Verge', 'technology'],
      'https://feeds.arstechnica.com/arstechnica/index': [
        'Ars Technica',
        'technology',
      ],
      'https://hnrss.org/frontpage': ['Hacker News', 'programming'],
      'https://dev.to/feed': ['DEV Community', 'programming'],
      'https://css-tricks.com/feed/': ['CSS-Tricks', 'programming'],
      'http://feeds.bbci.co.uk/news/rss.xml': ['BBC News', 'news'],
      'http://feeds.bbci.co.uk/sport/rss.xml': ['BBC Sport', 'sports'],
      'https://feeds.npr.org/1001/rss.xml': ['NPR Topics', 'news'],
      'https://www.theguardian.com/world/rss': ['The Guardian', 'news'],
      'https://www.cnbc.com/id/100003114/device/rss/rss.html': [
        'CNBC',
        'business',
      ],
      'https://www.espn.com/espn/rss/news': ['ESPN', 'sports'],
      'https://www.espncricinfo.com/rss/content/story/feeds/0.xml': [
        'ESPNcricinfo',
        'sports',
      ],
      'https://variety.com/feed/': ['Variety', 'entertainment'],
      'https://www.polygon.com/rss/index.xml': ['Polygon', 'gaming'],
      'https://feeds.feedburner.com/ign/all': ['IGN', 'gaming'],
      'https://www.nasa.gov/news-release/feed/': ['NASA', 'science'],
      'https://www.quantamagazine.org/feed/': ['Quanta Magazine', 'science'],
      'https://www.healthline.com/rss': ['Healthline', 'health'],
      'https://www.dezeen.com/feed/': ['Dezeen', 'culture'],
      'https://lifehacker.com/rss': ['Lifehacker', 'lifestyle'],
    };

    cases.forEach((url, expectation) {
      test('${expectation[0]} -> ${expectation[1]}', () {
        final result = quickCategorizeOne(
          feed(id: url, title: expectation[0], url: url),
          categories,
        );
        expect(result, expectation[1]);
      });
    });
  });

  group('quickCategorizeOne - keywords', () {
    test('title keywords win when the domain is unknown', () {
      expect(
        quickCategorizeOne(
          feed(
            id: '1',
            title: 'Indie Game Dev Weekly',
            url: 'https://example.com/rss',
            description: 'Esports, playstation and console news',
          ),
          categories,
        ),
        'gaming',
      );
    });

    test('description keywords are used', () {
      expect(
        quickCategorizeOne(
          feed(
            id: '2',
            title: 'Zephyr Weekly',
            url: 'https://zephyr.example/feed',
            description:
                'Recipes, cooking and travel notes from a working kitchen',
          ),
          categories,
        ),
        'lifestyle',
      );
    });

    test('URL path keywords are used', () {
      expect(
        quickCategorizeOne(
          feed(
            id: '3',
            title: 'Daily Digest',
            url: 'https://example.org/science/research/feed.xml',
          ),
          categories,
        ),
        'science',
      );
    });

    test('unknown feeds fall back to general', () {
      expect(
        quickCategorizeOne(
          feed(id: '4', title: 'Zzz', url: 'https://zzz.example/atom.xml'),
          categories,
        ),
        'general',
      );
    });

    test('never returns an id outside the supplied categories', () {
      final limited = [
        categories.firstWhere((c) => c.id == 'general'),
        categories.firstWhere((c) => c.id == 'news'),
      ];
      expect(
        quickCategorizeOne(
          feed(
            id: '5',
            title: 'TechCrunch',
            url: 'https://techcrunch.com/feed/',
          ),
          limited,
        ),
        anyOf('general', 'news'),
      );
    });

    test('quickCategorize maps every feed', () {
      final feeds = [
        feed(
          id: 'a',
          title: 'The Verge',
          url: 'https://www.theverge.com/rss/index.xml',
        ),
        feed(id: 'b', title: 'NASA', url: 'https://www.nasa.gov/feed/'),
      ];
      expect(quickCategorize(feeds, categories), {
        'a': 'technology',
        'b': 'science',
      });
    });
  });

  group('aiCategorize', () {
    final feeds = [
      feed(
        id: 'f1',
        title: 'Zephyr Daily',
        url: 'https://zephyr.example/feed',
        categoryId: 'general',
      ),
      feed(
        id: 'f2',
        title: 'Orbit Weekly',
        url: 'https://orbit.example/feed',
        categoryId: 'general',
      ),
    ];

    test('parses a fenced JSON array', () async {
      final adapter = FakeHttpAdapter([
        openAiReply('''
Sure, here you go:
```json
[
  {"id": "f1", "category": "technology", "newCategory": null, "confidence": 0.9},
  {"id": "f2", "category": "science", "newCategory": null, "confidence": 0.7}
]
```
'''),
      ]);

      final result = await aiCategorize(feeds, categories, ai: aiWith(adapter));

      expect(result, hasLength(2));
      expect(result[0].suggestedCategoryId, 'technology');
      expect(result[0].source, CategorySource.ai);
      expect(result[0].confidence, closeTo(0.9, 0.001));
      expect(result[0].isChange, isTrue);
      expect(result[1].suggestedCategoryId, 'science');

      // The prompt lists the category ids and the feeds.
      final sent = jsonDecode(adapter.requests.single) as Map<String, dynamic>;
      final userContent = (sent['messages'] as List).last['content'] as String;
      expect(userContent, contains('- technology: Technology'));
      expect(userContent, contains('id: f1'));
      expect(
        (sent['messages'] as List).first['content'],
        kCategorizationSystemPrompt,
      );
    });

    test('unknown category ids fall back to the quick result', () async {
      final adapter = FakeHttpAdapter([
        openAiReply(
          '[{"id":"f1","category":"astrology","confidence":0.5},'
          '{"id":"f2","category":"science","confidence":0.5}]',
        ),
      ]);

      final result = await aiCategorize(feeds, categories, ai: aiWith(adapter));

      expect(result[0].suggestedCategoryId, 'general');
      expect(result[1].suggestedCategoryId, 'science');
    });

    test('newCategory is preserved and pinned to general', () async {
      final adapter = FakeHttpAdapter([
        openAiReply(
          '[{"id":"f1","category":"nope","newCategory":"Aviation",'
          '"confidence":0.8}]',
        ),
      ]);

      final result = await aiCategorize(feeds, categories, ai: aiWith(adapter));

      expect(result[0].newCategoryName, 'Aviation');
      expect(result[0].suggestedCategoryId, kFallbackCategoryId);
      expect(result[0].isChange, isTrue);
      // f2 was not mentioned - quick result, quick source.
      expect(result[1].source, CategorySource.quick);
    });

    test('garbage replies fall back to quick results for every feed', () async {
      final adapter = FakeHttpAdapter([
        openAiReply('I am sorry, I cannot help with that.'),
      ]);

      final result = await aiCategorize(feeds, categories, ai: aiWith(adapter));

      expect(result, hasLength(2));
      expect(result.every((r) => r.source == CategorySource.quick), isTrue);
      expect(result.every((r) => r.suggestedCategoryId == 'general'), isTrue);
    });

    test('batches large feed lists', () async {
      final many = [
        for (var i = 0; i < 5; i++)
          feed(id: 'f$i', title: 'Feed $i', url: 'https://f$i.example/rss'),
      ];
      final adapter = FakeHttpAdapter([openAiReply('[]')]);

      await aiCategorize(many, categories, ai: aiWith(adapter), batchSize: 2);

      expect(adapter.requests, hasLength(3));
    });

    test('propagates AiException so the UI can show it', () async {
      final dio = Dio();
      dio.httpClientAdapter = FakeHttpAdapter([openAiReply('[]')]);
      final ai = AiService(
        configSource: const StaticAiConfigSource(
          AiConfig(
            provider: AiProvider.openai,
            apiKey: '',
            model: 'gpt-4o-mini',
          ),
        ),
        dio: dio,
      );

      await expectLater(
        aiCategorize(feeds, categories, ai: ai),
        throwsA(isA<AiException>()),
      );
    });

    test('empty input short-circuits', () async {
      final adapter = FakeHttpAdapter([openAiReply('[]')]);
      expect(
        await aiCategorize(const [], categories, ai: aiWith(adapter)),
        isEmpty,
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('CategorizationService facade', () {
    test('delegates to the top-level functions', () {
      const service = CategorizationService();
      final f = feed(
        id: 'x',
        title: 'Ars Technica',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
      );
      expect(service.categorizeOne(f, categories), 'technology');
      expect(service.categorizeAll([f], categories), {'x': 'technology'});
    });
  });
}
