import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:freead/models/app_settings.dart';
import 'package:freead/models/article.dart';
import 'package:freead/providers/article_provider.dart';
import 'package:freead/providers/feed_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/theme/accent.dart';
import 'package:freead/theme/app_theme.dart';
import 'package:freead/widgets/article/article_list.dart';

// Also proves the old import path still resolves the class.
import 'package:freead/widgets/article_list_widget.dart' as legacy;

/// An [ArticleProvider] that never touches the database but reproduces the
/// production mutation semantics exactly: `toggleStarred` and friends replace
/// the entry **in place** (`list[i] = ...`), so the `List` object identity
/// never changes. That is what made the v2 list widget's
/// `oldWidget.articles != widget.articles` check permanently false.
class _FakeArticleProvider extends ArticleProvider {
  _FakeArticleProvider(List<Article> seed) : _items = List<Article>.of(seed);

  final List<Article> _items;

  int toggleStarCalls = 0;

  @override
  List<Article> get articles => _items;

  @override
  List<Article> get savedArticles =>
      _items.where((Article a) => a.isSaved).toList();

  @override
  List<Article> get starredArticles =>
      _items.where((Article a) => a.isStarred).toList();

  @override
  bool get isLoading => false;

  @override
  Article? getArticleById(String id) {
    for (final Article article in _items) {
      if (article.id == id) return article;
    }
    return null;
  }

  void _replaceInPlace(Article updated) {
    final int index = _items.indexWhere((Article a) => a.id == updated.id);
    if (index == -1) return;
    // Deliberately in place - the exact shape of the real provider.
    _items[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> toggleStarred(String articleId) async {
    toggleStarCalls++;
    final Article? article = getArticleById(articleId);
    if (article == null) return;
    _replaceInPlace(article.copyWith(isStarred: !article.isStarred));
  }

  @override
  Future<void> toggleStar(String articleId) => toggleStarred(articleId);

  @override
  Future<void> toggleSaved(String articleId) async {
    final Article? article = getArticleById(articleId);
    if (article == null) return;
    _replaceInPlace(article.copyWith(isSaved: !article.isSaved));
  }

  @override
  Future<void> markAsRead(String articleId) async {
    final Article? article = getArticleById(articleId);
    if (article == null || article.isRead) return;
    _replaceInPlace(article.copyWith(isRead: true));
  }

  @override
  Future<void> markAsUnread(String articleId) async {
    final Article? article = getArticleById(articleId);
    if (article == null || !article.isRead) return;
    _replaceInPlace(article.copyWith(isRead: false));
  }

  @override
  Future<void> loadArticles() async {}
}

Article _article({
  required String id,
  required String title,
  String? imageUrl,
  bool isRead = false,
  bool isStarred = false,
  bool isSaved = false,
  int agoDays = 0,
}) {
  return Article(
    id: id,
    title: title,
    description:
        'A short excerpt for $title that wraps onto a second line '
        'so the layout is exercised properly.',
    url: 'https://example.com/$id',
    feedId: 'feed-1',
    imageUrl: imageUrl,
    isRead: isRead,
    isStarred: isStarred,
    isSaved: isSaved,
    publishedDate: DateTime(2026, 9, 1).subtract(Duration(days: agoDays)),
    dateAdded: DateTime(2026, 9, 1),
  );
}

/// Three articles: two with images, one without.
List<Article> _seed() => <Article>[
  _article(
    id: 'a1',
    title: 'A headline long enough to wrap across two lines in every style',
    imageUrl: 'https://example.com/one.jpg',
  ),
  _article(
    id: 'a2',
    title: 'Second article, already read',
    imageUrl: 'https://example.com/two.jpg',
    isRead: true,
    agoDays: 1,
  ),
  _article(id: 'a3', title: 'Third article, no image', agoDays: 9),
];

Widget _harness({
  required Widget child,
  required _FakeArticleProvider articles,
  required SettingsProvider settings,
  Brightness brightness = Brightness.dark,
}) {
  return MultiProvider(
    providers: <ChangeNotifierProvider<dynamic>>[
      ChangeNotifierProvider<ArticleProvider>.value(value: articles),
      ChangeNotifierProvider<FeedProvider>(create: (_) => FeedProvider()),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.dark(accent: AppAccent.emerald)
          : AppTheme.light(accent: AppAccent.emerald),
      home: Scaffold(body: child),
    ),
  );
}

/// Fails every request instantly instead of hitting real DNS/network for the
/// fixtures' `https://example.com/*.jpg` image URLs. Without this, image
/// widgets resolve at unpredictable times relative to `pumpAndSettle`,
/// making the "without overflow" tests flaky depending on network
/// reachability and timing in the environment running the suite.
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FailingHttpClient();
}

class _FailingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) => Future<HttpClientRequest>.error(
    const SocketException('Network disabled in tests'),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final HttpOverrides? previousHttpOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = _NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = previousHttpOverrides);

  late SettingsProvider settings;

  setUp(() {
    settings = SettingsProvider();
  });

  group('ArticleListWidget rendering', () {
    for (final ArticleListStyle style in ArticleListStyle.values) {
      for (final Brightness brightness in Brightness.values) {
        testWidgets('renders ${style.name} in ${brightness.name} without '
            'overflow', (WidgetTester tester) async {
          // Tall enough that all three fixture rows - including the two
          // image-bearing ones in card/list style - are laid out within
          // ListView.builder's default cacheExtent. This test checks for
          // RenderFlex overflow within a row, not real-device scrolling, so
          // a generous height (rather than scrolling to find each row) keeps
          // it independent of exact row heights.
          tester.view.physicalSize = const Size(360, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final _FakeArticleProvider articles = _FakeArticleProvider(_seed());
          await tester.pumpWidget(
            _harness(
              articles: articles,
              settings: settings,
              brightness: brightness,
              child: ArticleListWidget(
                articles: articles.articles,
                style: style,
                showFilter: true,
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            // Exact match: the fixture's excerpt text is generated from the
            // title ("A short excerpt for $title that wraps..."), so it also
            // *contains* the title string - textContaining matches both.
            find.text('Third article, no image'),
            findsOneWidget,
          );
        });
      }
    }

    testWidgets('groups by date when asked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final _FakeArticleProvider articles = _FakeArticleProvider(_seed());
      await tester.pumpWidget(
        _harness(
          articles: articles,
          settings: settings,
          child: ArticleListWidget(
            articles: articles.articles,
            style: ArticleListStyle.compact,
            showFilter: false,
            groupByDate: true,
          ),
        ),
      );
      await tester.pump();

      // SectionHeader renders its label upper-cased.
      expect(find.text('EARLIER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an empty state when nothing matches', (
      WidgetTester tester,
    ) async {
      final _FakeArticleProvider articles = _FakeArticleProvider(
        const <Article>[],
      );
      await tester.pumpWidget(
        _harness(
          articles: articles,
          settings: settings,
          child: ArticleListWidget(
            articles: articles.articles,
            showFilter: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No articles yet'), findsOneWidget);
    });

    testWidgets('the legacy import path still resolves the class', (
      WidgetTester tester,
    ) async {
      expect(legacy.ArticleListWidget, ArticleListWidget);
    });
  });

  group('star/save stays live after filtering (v2 regression)', () {
    testWidgets(
      'toggling a filter then starring updates the icon in the same tree',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final _FakeArticleProvider articles = _FakeArticleProvider(_seed());

        // The parent re-reads `articles` from the provider on every build,
        // exactly as HomeTab/SavedTab do.
        await tester.pumpWidget(
          _harness(
            articles: articles,
            settings: settings,
            child: Consumer<ArticleProvider>(
              builder: (BuildContext context, ArticleProvider provider, _) =>
                  ArticleListWidget(
                    articles: provider.articles,
                    style: ArticleListStyle.card,
                    showFilter: true,
                  ),
            ),
          ),
        );
        await tester.pump();

        // 1. Run a filter. In v2 this cached a filtered copy of the list and
        //    every later provider update was ignored.
        await tester.tap(find.text('Unread'));
        await tester.pumpAndSettle();
        expect(find.textContaining('already read'), findsNothing);

        // 2. Then run a sort, the other operation that poisoned the cache.
        await tester.tap(find.byIcon(Icons.swap_vert_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Oldest first'));
        await tester.pumpAndSettle();

        // 3. Star the first visible article.
        expect(find.byIcon(Icons.star_border_rounded), findsWidgets);
        expect(find.byIcon(Icons.star_rounded), findsNothing);

        await tester.tap(find.byIcon(Icons.star_border_rounded).first);
        await tester.pumpAndSettle();

        expect(articles.toggleStarCalls, 1);
        // The filled star must be on screen now. With the v2 caching bug this
        // assertion fails: the provider updated but the list never re-read it.
        expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      },
    );

    testWidgets('saving after a filter updates the bookmark icon', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final _FakeArticleProvider articles = _FakeArticleProvider(_seed());
      await tester.pumpWidget(
        _harness(
          articles: articles,
          settings: settings,
          child: Consumer<ArticleProvider>(
            builder: (BuildContext context, ArticleProvider provider, _) =>
                ArticleListWidget(
                  articles: provider.articles,
                  style: ArticleListStyle.card,
                  showFilter: true,
                ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    });

    testWidgets('a list handed a stale copy still tracks the provider', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final _FakeArticleProvider articles = _FakeArticleProvider(_seed());
      // Simulates a screen that loaded its rows from a one-shot Future and
      // holds them in its own State field (FeedArticlesScreen does this).
      final List<Article> snapshot = List<Article>.of(articles.articles);

      await tester.pumpWidget(
        _harness(
          articles: articles,
          settings: settings,
          child: ArticleListWidget(
            articles: snapshot,
            style: ArticleListStyle.card,
            showFilter: false,
          ),
        ),
      );
      await tester.pump();

      // Star it through the provider, not the UI.
      await articles.toggleStarred('a1');
      await tester.pumpAndSettle();

      // resolveAgainstProvider re-reads by id, so the row reflects it.
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });
  });
}
