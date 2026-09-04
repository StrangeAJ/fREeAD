import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:freead/models/app_settings.dart';
import 'package:freead/providers/article_provider.dart';
import 'package:freead/providers/feed_provider.dart';
import 'package:freead/providers/settings_provider.dart';
import 'package:freead/screens/home/settings_tab.dart';
import 'package:freead/services/ai/ai_service.dart';
import 'package:freead/theme/accent.dart';
import 'package:freead/theme/app_theme.dart';

/// `SettingsTab` is a plain `ListView` with `children:` (not `.builder`), so
/// every section is built eagerly - no lazy-loading/scrolling concerns like
/// the article list. `FeedProvider`/`ArticleProvider` are real instances; in
/// a widget test there is no platform channel, so their database calls throw
/// and are caught, leaving them in a harmless empty/error state.
Widget _harness({
  Brightness brightness = Brightness.dark,
  SettingsProvider? settings,
}) {
  return MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => settings ?? SettingsProvider(),
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
      home: const SettingsTab(),
    ),
  );
}

const List<String> _sectionHeaders = <String>[
  'APPEARANCE',
  'READING',
  'FEEDS & SYNC',
  'NOTIFICATIONS',
  'AI',
  'DATA',
  'ABOUT',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'renders every section in ${brightness.name} without overflow',
      (WidgetTester tester) async {
        // ListView(children: ...) still lazily *mounts* elements by viewport +
        // cacheExtent even though the Widget objects are all constructed
        // upfront - tall enough that all seven sections are actually built,
        // not just instantiated, so find.text can see every header.
        tester.view.physicalSize = const Size(360, 5200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_harness(brightness: brightness));
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final String label in _sectionHeaders) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: 'missing "$label" section',
          );
        }
        expect(find.text('Settings'), findsOneWidget); // GlassAppBar title
      },
    );
  }

  testWidgets('picking an accent updates SettingsProvider immediately', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final SettingsProvider settings = SettingsProvider();
    expect(settings.accent, AppAccent.emerald);

    await tester.pumpWidget(_harness(settings: settings));
    await tester.pump();

    // Accent swatches are unlabeled color discs; find one by the Semantics
    // widget's `label`, which each swatch sets to its AppAccent.label.
    final Finder cyanSwatch = find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == 'Cyan',
    );
    expect(cyanSwatch, findsOneWidget);

    await tester.tap(cyanSwatch);
    await tester.pump();

    expect(settings.accent, AppAccent.cyan);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching the article list style updates SettingsProvider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final SettingsProvider settings = SettingsProvider();
    expect(settings.articleListStyle, ArticleListStyle.list);

    await tester.pumpWidget(_harness(settings: settings));
    await tester.pump();

    await tester.tap(find.text('Compact'));
    await tester.pump();

    expect(settings.articleListStyle, ArticleListStyle.compact);
    expect(tester.takeException(), isNull);
  });
}
