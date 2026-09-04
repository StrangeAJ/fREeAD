import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:freead/models/app_settings.dart';
import 'package:freead/models/article.dart';
import 'package:freead/models/article_highlight.dart';
import 'package:freead/models/chat_message.dart';
import 'package:freead/providers/ai_chat_provider.dart';
import 'package:freead/providers/article_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/screens/reader/article_reading_screen.dart';
import 'package:freead/screens/reader/ask_ai_sheet.dart';
import 'package:freead/screens/reader/reader_content_view.dart';
import 'package:freead/services/ai/ai_models.dart';
import 'package:freead/services/ai/ai_service.dart';
import 'package:freead/services/ai/article_chat_repository.dart';
import 'package:freead/theme/accent.dart';
import 'package:freead/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RSS body with the markup the old regex-based reader used to destroy:
/// headings, a list, a link and - the visible one - an image.
const String kRichHtml = '''
<p>Opening paragraph with a <a href="https://example.com/more">link</a>.</p>
<h2>A real heading</h2>
<p>Second paragraph that is long enough to wrap onto more than one line in a
narrow phone layout, which is exactly what the reader has to handle.</p>
<figure>
  <img src="https://example.com/photo.jpg" alt="An inline photo">
  <figcaption>The caption below the photo</figcaption>
</figure>
<ul><li>First bullet</li><li>Second bullet</li></ul>
<blockquote>A pulled quote.</blockquote>
''';

Article buildArticle({
  String? content = kRichHtml,
  String? fullContent,
  String? imageUrl,
  double scrollProgress = 0,
}) {
  return Article(
    id: 'article-1',
    title: 'A headline that is long enough to wrap onto two lines on a phone',
    description: 'A short RSS description.',
    content: content,
    fullContent: fullContent,
    imageUrl: imageUrl,
    url: 'https://example.com/story',
    author: 'Ada Lovelace',
    publishedDate: DateTime(2026, 8, 30, 9, 30),
    feedId: 'feed-1',
    dateAdded: DateTime(2026, 8, 30, 10),
    scrollProgress: scrollProgress,
  );
}

/// In-memory [ArticleProvider]: no database, no network, no timers.
class FakeArticleProvider extends ArticleProvider {
  FakeArticleProvider(this.article);

  Article article;
  int markedRead = 0;
  int fullArticleRequests = 0;
  bool loadingFull = false;
  String? extractionError;

  @override
  List<Article> get articles => <Article>[article];

  @override
  Article? getArticleById(String id) => id == article.id ? article : null;

  @override
  Future<void> markAsRead(String articleId) async => markedRead++;

  @override
  void saveScrollProgress(String articleId, double progress) {}

  @override
  bool isLoadingFullArticle(String id) => loadingFull;

  @override
  String? lastExtractionError(String id) => extractionError;

  @override
  Future<bool> loadFullArticle(
    String articleId, {
    ExtractionEngine engine = ExtractionEngine.auto,
    bool force = false,
  }) async {
    fullArticleRequests++;
    return false;
  }

  @override
  Future<void> toggleSaved(String articleId) async {}

  @override
  Future<void> toggleStarred(String articleId) async {}
}

/// Chat repository that never touches sqflite.
class FakeChatRepository extends ArticleChatRepository {
  @override
  Future<List<ChatMessage>> load(String articleId) async =>
      const <ChatMessage>[];

  @override
  Future<bool> appendMessage(ChatMessage message) async => true;

  @override
  Future<void> replaceAll(String articleId, List<ChatMessage> messages) async {}

  @override
  Future<void> clear(String articleId) async {}
}

void main() {
  const Size phone = Size(360, 800);
  const EdgeInsets deviceInsets = EdgeInsets.only(top: 24, bottom: 16);

  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );

    settings = SettingsProvider();
    await settings.init();
    // Keep the widget tests free of network images and background fetches.
    await settings.setShowImages(false);
    await settings.setAutoLoadFullArticle(false);
  });

  tearDown(() => settings.dispose());

  ThemeData themeFor(bool dark) => dark
      ? AppTheme.dark(accent: AppAccent.emerald)
      : AppTheme.light(accent: AppAccent.emerald);

  Widget wrap(Widget child, {required bool dark, ArticleProvider? articles}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        if (articles != null)
          ChangeNotifierProvider<ArticleProvider>.value(value: articles),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeFor(dark),
        home: MediaQuery(
          data: const MediaQueryData(size: phone, padding: deviceInsets),
          child: child,
        ),
      ),
    );
  }

  Future<FakeArticleProvider> pumpReader(
    WidgetTester tester, {
    required bool dark,
    Article? article,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = phone;
    addTearDown(tester.view.reset);

    final FakeArticleProvider provider = FakeArticleProvider(
      article ?? buildArticle(),
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      wrap(
        ArticleReadingScreen(article: provider.article),
        dark: dark,
        articles: provider,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return provider;
  }

  group('ArticleReadingScreen', () {
    testWidgets('renders in light and dark without overflowing', (
      WidgetTester tester,
    ) async {
      for (final bool dark in <bool>[false, true]) {
        await pumpReader(tester, dark: dark);
        expect(
          tester.takeException(),
          isNull,
          reason: dark ? 'dark mode threw' : 'light mode threw',
        );
      }
    });

    testWidgets('the title never renders behind the app bar (no hero image)', (
      WidgetTester tester,
    ) async {
      final FakeArticleProvider provider = await pumpReader(
        tester,
        dark: true,
        article: buildArticle(),
      );

      final Finder title = find.text(provider.article.title);
      expect(title, findsOneWidget);

      // The scaffold extends the body behind the glass app bar, so the first
      // content sliver has to clear: status bar + toolbar + progress bar.
      const double minimumTop = 24 + kToolbarHeight + 2;
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(minimumTop));
    });

    testWidgets('the title clears the app bar with a hero image too', (
      WidgetTester tester,
    ) async {
      await settings.setShowImages(true);
      final FakeArticleProvider provider = await pumpReader(
        tester,
        dark: false,
        article: buildArticle(imageUrl: 'https://example.com/hero.jpg'),
      );

      final Finder title = find.text(provider.article.title);
      expect(title, findsOneWidget);
      const double minimumTop = 24 + kToolbarHeight + 2;
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(minimumTop));
    });

    testWidgets('the hero image starts below the app bar at rest', (
      WidgetTester tester,
    ) async {
      await settings.setShowImages(true);
      await pumpReader(
        tester,
        dark: true,
        article: buildArticle(imageUrl: 'https://example.com/hero.jpg'),
      );

      // The hero may slide under the glass bar while scrolling, but at rest
      // the bar must sit over plain background - never over the image.
      final Finder hero = find.byType(Hero);
      expect(hero, findsOneWidget);
      const double barBottom = 24 + kToolbarHeight + 2;
      expect(tester.getTopLeft(hero).dy, greaterThanOrEqualTo(barBottom));
    });

    testWidgets('renders headings, list items and quotes from the RSS HTML', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester, dark: true);

      // fwfh renders body text as standalone RichText widgets.
      expect(
        find.textContaining('A real heading', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('First bullet', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('A pulled quote.', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('shows the reader chips and the Ask AI action', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester, dark: false);

      expect(find.text('RSS excerpt'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      // Chip + bottom bar button.
      expect(find.text('Ask AI'), findsNWidgets(2));
      expect(find.byType(ReaderContentView), findsOneWidget);
    });

    testWidgets('marks the article read on open when the setting is on', (
      WidgetTester tester,
    ) async {
      final FakeArticleProvider provider = await pumpReader(
        tester,
        dark: false,
      );
      expect(provider.markedRead, greaterThan(0));
    });

    testWidgets('shows "Full article" once a body is cached', (
      WidgetTester tester,
    ) async {
      await pumpReader(
        tester,
        dark: false,
        article: buildArticle(fullContent: '<p>The extracted body.</p>'),
      );

      expect(find.text('Full article'), findsOneWidget);
      expect(
        find.textContaining('The extracted body.', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('auto-loads the full article when the RSS body is thin', (
      WidgetTester tester,
    ) async {
      await settings.setAutoLoadFullArticle(true);
      final FakeArticleProvider provider = await pumpReader(
        tester,
        dark: false,
        article: buildArticle(
          content: '<p>Two short sentences. That is all.</p>',
        ),
      );
      expect(provider.fullArticleRequests, equals(1));
      // The failure is silent on the automatic attempt - the RSS body stays.
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not auto-load when the feed already ships the body', (
      WidgetTester tester,
    ) async {
      await settings.setAutoLoadFullArticle(true);
      final FakeArticleProvider provider = await pumpReader(
        tester,
        dark: false,
        article: buildArticle(content: '<p>${'word ' * 400}</p>'),
      );
      expect(provider.fullArticleRequests, equals(0));
    });

    testWidgets('survives a 1.3 text scale without overflowing', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = phone;
      addTearDown(tester.view.reset);

      final FakeArticleProvider provider = FakeArticleProvider(buildArticle());
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<ArticleProvider>.value(value: provider),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeFor(true),
            home: MediaQuery(
              data: const MediaQueryData(
                size: phone,
                padding: deviceInsets,
                textScaler: TextScaler.linear(1.3),
              ),
              child: ArticleReadingScreen(article: provider.article),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });

  group('ReaderContentView', () {
    testWidgets('an <img> survives into the rendered HtmlWidget', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = phone;
      addTearDown(tester.view.reset);

      final Article article = buildArticle();

      // The HTML handed to HtmlWidget still carries the tag - the v2 reader
      // stripped it with a regex before rendering.
      expect(ReaderContentView.htmlFor(article), contains('<img '));

      final List<String> renderedImages = <String>[];
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: SingleChildScrollView(
              child: ReaderContentView(
                article: article,
                readingFont: ReadingFont.serif,
                fontSize: 17,
                lineHeight: 1.6,
                imageBuilder: (BuildContext context, String url, String? alt) {
                  renderedImages.add(url);
                  return const SizedBox(
                    key: Key('reader-image'),
                    height: 120,
                    width: double.infinity,
                  );
                },
              ),
            ),
          ),
          dark: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('reader-image')), findsOneWidget);
      expect(renderedImages, <String>['https://example.com/photo.jpg']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides images when "Show images" is off', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = phone;
      addTearDown(tester.view.reset);

      var built = 0;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: SingleChildScrollView(
              child: ReaderContentView(
                article: buildArticle(),
                readingFont: ReadingFont.sans,
                fontSize: 17,
                lineHeight: 1.6,
                showImages: false,
                imageBuilder: (BuildContext context, String url, String? alt) {
                  built++;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          dark: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(built, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a stored highlight as an inline <mark>', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = phone;
      addTearDown(tester.view.reset);

      String? tapped;
      final DateTime now = DateTime(2026, 1, 1);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: SingleChildScrollView(
              child: ReaderContentView(
                article: buildArticle(
                  content: '<p>The quick brown fox jumps.</p>',
                ),
                readingFont: ReadingFont.serif,
                fontSize: 17,
                lineHeight: 1.6,
                onHighlightTap: (String id) => tapped = id,
                highlights: <ArticleHighlight>[
                  ArticleHighlight(
                    id: 'hl-1',
                    articleId: 'article-1',
                    selectedText: 'quick brown',
                    startIndex: 4,
                    endIndex: 15,
                    color: '#4CAF50',
                    createdAt: now,
                    updatedAt: now,
                  ),
                ],
              ),
            ),
          ),
          dark: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(InlineCustomWidget), findsOneWidget);
      expect(find.text('quick brown'), findsOneWidget);

      await tester.tap(find.text('quick brown'));
      await tester.pump();
      expect(tapped, equals('hl-1'));
      expect(tester.takeException(), isNull);
    });

    test('htmlFor prefers fullContent, then content, then description', () {
      expect(
        ReaderContentView.htmlFor(buildArticle(fullContent: '<p>full</p>')),
        equals('<p>full</p>'),
      );
      expect(
        ReaderContentView.htmlFor(buildArticle(content: '<p>rss</p>')),
        equals('<p>rss</p>'),
      );
      expect(
        ReaderContentView.htmlFor(buildArticle(content: null)),
        equals('<p>A short RSS description.</p>'),
      );
    });
  });

  group('AskAiSheet', () {
    testWidgets('offers the suggested prompts when the chat is empty', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = phone;
      addTearDown(tester.view.reset);

      final AiService ai = AiService(
        configSource: const StaticAiConfigSource(
          AiConfig(
            provider: AiProvider.openai,
            apiKey: 'test-key',
            model: 'gpt-4o-mini',
          ),
        ),
      );
      final AiChatProvider chat = AiChatProvider(
        article: buildArticle(),
        ai: ai,
        repo: FakeChatRepository(),
      );
      addTearDown(chat.dispose);

      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: ChangeNotifierProvider<AiChatProvider>.value(
              value: chat,
              child: const AskAiSheet(),
            ),
          ),
          dark: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      for (final String prompt in AiChatProvider.suggestedPrompts) {
        expect(find.text(prompt), findsOneWidget);
      }
      expect(find.textContaining('OpenAI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
