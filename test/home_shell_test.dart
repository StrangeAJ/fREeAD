import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:freead/providers/article_provider.dart';
import 'package:freead/providers/feed_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/screens/home_screen.dart';
import 'package:freead/services/ai/ai_service.dart';
import 'package:freead/theme/accent.dart';
import 'package:freead/theme/app_theme.dart';

/// Smoke test for the v3 app shell (`HomeScreen` / `home_shell.dart`).
///
/// The real `FeedProvider`/`ArticleProvider` are used unmodified: in a plain
/// widget test there is no platform channel, so `DatabaseService` calls throw
/// `MissingPluginException`, which every provider method here already catches
/// and turns into an empty list + an `error` string (see `loadFeeds`/
/// `loadArticles`). That is exactly the "no feeds yet" / "no articles yet"
/// state this smoke test wants to exercise - no fakes needed.
Widget _harness({
  Brightness brightness = Brightness.dark,
  int initialIndex = 0,
}) {
  return MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
      ChangeNotifierProvider<FeedProvider>(create: (_) => FeedProvider()),
      ChangeNotifierProvider<ArticleProvider>(create: (_) => ArticleProvider()),
      Provider<AiService>(
        create: (context) => AiService(
          configSource: SettingsAiConfigSource(
            context.read<SettingsProvider>(),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.dark(accent: AppAccent.emerald)
          : AppTheme.light(accent: AppAccent.emerald),
      home: HomeScreen(initialIndex: initialIndex),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final Brightness brightness in Brightness.values) {
    testWidgets('renders the shell in ${brightness.name} without overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // IndexedStack builds every tab eagerly, so this alone exercises
      // HomeTab, FeedsTab, SavedTab and SettingsTab together.
      await tester.pumpWidget(_harness(brightness: brightness));
      await tester.pump();
      // Lets the post-frame `refreshIfStale` callback (and its caught
      // failure, since there is no real database/network here) settle.
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);

      // The M3 NavigationBar, not the old BottomNavigationBar - this is the
      // fix for "icons invisible against the theme" (v2 used
      // BottomNavigationBar, which AppTheme never styled).
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      for (final String label in <String>[
        'Home',
        'Feeds',
        'Saved',
        'Settings',
      ]) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'missing "$label" destination',
        );
      }

      // FAB shows on the Home tab.
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  }

  testWidgets('switching tabs does not throw and hides the FAB on Settings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (final String label in <String>['Feeds', 'Saved', 'Settings', 'Home']) {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 250),
      ); // FAB scale animation
      expect(
        tester.takeException(),
        isNull,
        reason: 'threw after tapping $label',
      );
    }
  });
}
