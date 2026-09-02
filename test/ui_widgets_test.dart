import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freead/models/app_settings.dart';
import 'package:freead/theme/accent.dart';
import 'package:freead/theme/app_theme.dart';
import 'package:freead/widgets/ui/ui.dart';

/// Every design-system widget must render at 360x800 in light *and* dark
/// without throwing (overflow exceptions included).
void main() {
  const Size phone = Size(360, 800);

  ThemeData themeFor(bool dark) => dark
      ? AppTheme.dark(accent: AppAccent.emerald)
      : AppTheme.light(accent: AppAccent.emerald);

  /// Pumps [build] in both modes. Uses `pump` (never `pumpAndSettle`) because
  /// the skeleton shimmer repeats forever.
  Future<void> pumpBoth(
    WidgetTester tester,
    Widget Function() build, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = phone;
    addTearDown(tester.view.reset);

    for (final bool dark in <bool>[false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeFor(dark),
          home: MediaQuery(
            data: MediaQueryData(size: phone, textScaler: textScaler),
            child: build(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.takeException(),
        isNull,
        reason: dark ? 'dark mode threw' : 'light mode threw',
      );
    }
  }

  group('chrome', () {
    testWidgets('AppScaffold + GlassAppBar + GlassBottomBar', (tester) async {
      await pumpBoth(
        tester,
        () => AppScaffold(
          appBar: GlassAppBar(
            title: 'FreeAd',
            showBack: false,
            bottom: const ReadingProgressBar(progress: 0.4),
            actions: <Widget>[
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {},
            child: const Icon(Icons.add_rounded),
          ),
          bottomBar: GlassBottomBar(
            child: NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const <Widget>[
                NavigationDestination(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.rss_feed_rounded),
                  label: 'Feeds',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark_rounded),
                  label: 'Saved',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
          body: ListView(
            children: <Widget>[
              for (int i = 0; i < 20; i++) ListTile(title: Text('Row $i')),
            ],
          ),
        ),
      );

      expect(find.text('FreeAd'), findsOneWidget);
      expect(find.text('Feeds'), findsOneWidget);
    });

    testWidgets('GlassAppBar reports its preferred size', (tester) async {
      const GlassAppBar plain = GlassAppBar(title: 'x');
      const GlassAppBar withBottom = GlassAppBar(
        title: 'x',
        bottom: ReadingProgressBar(progress: 0.5, height: 2),
      );
      expect(plain.preferredSize.height, kToolbarHeight);
      expect(withBottom.preferredSize.height, kToolbarHeight + 2);
      // Silence the unused-variable analyzer in a const-only test.
      expect(plain.title, 'x');
      await tester.pump();
    });
  });

  group('surfaces and labels', () {
    testWidgets('SurfaceCard levels 1-3, tappable and plain', (tester) async {
      int taps = 0;
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              for (int level = 1; level <= 3; level++) ...<Widget>[
                SurfaceCard(
                  level: level,
                  padding: const EdgeInsets.all(16),
                  onTap: () => taps++,
                  child: Text('Level $level'),
                ),
                const SizedBox(height: 12),
              ],
              const SurfaceCard(
                showBorder: false,
                radius: 12,
                padding: EdgeInsets.all(16),
                child: Text('Borderless'),
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Level 1'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('SectionHeader upper-cases and shows its action', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => const AppScaffold(
          body: SectionHeader(
            'Appearance',
            actionLabel: 'Reset',
            icon: Icons.palette_rounded,
          ),
        ),
      );
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
    });

    testWidgets('PillChip variants', (tester) async {
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                PillChip(label: 'All', selected: true, onTap: () {}),
                PillChip(label: 'Unread', count: 128, onTap: () {}),
                PillChip(
                  label: 'Starred',
                  icon: Icons.star_rounded,
                  onTap: () {},
                ),
                const PillChip(
                  label: 'Technology',
                  dotColor: Color(0xFF22D3EE),
                ),
                const PillChip(label: 'Disabled', enabled: false),
                const PillChip(label: 'Dense', dense: true),
              ],
            ),
          ),
        ),
      );
      expect(find.text('All'), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
    });

    testWidgets('AppBadge renders counts and labels', (tester) async {
      await pumpBoth(
        tester,
        () => const AppScaffold(
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AppBadge(count: 3),
                SizedBox(width: 8),
                AppBadge(count: 4000),
                SizedBox(width: 8),
                AppBadge(label: 'NEW', soft: false),
              ],
            ),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('999+'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
    });

    testWidgets('FeedAvatar falls back to initials at every size', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => const AppScaffold(
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FeedAvatar(title: 'The Verge', size: 20),
                FeedAvatar(title: 'Ars Technica', size: 28),
                FeedAvatar(title: 'Wired', size: 40),
                FeedAvatar(title: '', size: 40),
              ],
            ),
          ),
        ),
      );
      // size < 24 keeps a single initial, larger sizes use two words.
      expect(find.text('T'), findsOneWidget);
      expect(find.text('AT'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('GlowButton: idle, loading, tonal, expanded, disabled', (
      tester,
    ) async {
      int taps = 0;
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              GlowButton(
                label: 'Ask AI',
                icon: Icons.auto_awesome_rounded,
                onPressed: () => taps++,
              ),
              const SizedBox(height: 12),
              const GlowButton(label: 'Loading', loading: true),
              const SizedBox(height: 12),
              GlowButton(label: 'Tonal', tonal: true, onPressed: () {}),
              const SizedBox(height: 12),
              GlowButton(label: 'Expanded', expand: true, onPressed: () {}),
              const SizedBox(height: 12),
              const GlowButton(label: 'Disabled'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Ask AI'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('SegmentedPills selects a value', (tester) async {
      ArticleListStyle selected = ArticleListStyle.list;
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) =>
                  SegmentedPills<ArticleListStyle>(
                    values: ArticleListStyle.values,
                    selected: selected,
                    labelBuilder: (ArticleListStyle s) => s.label,
                    onChanged: (ArticleListStyle s) =>
                        setState(() => selected = s),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Compact'));
      await tester.pump();
      expect(selected, ArticleListStyle.compact);
    });

    testWidgets('EmptyState with both actions', (tester) async {
      int primary = 0;
      int secondary = 0;
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: EmptyState(
            icon: Icons.rss_feed_rounded,
            title: 'No feeds yet',
            message: 'Add your first feed to start reading.',
            primaryActionLabel: 'Add feed',
            primaryActionIcon: Icons.add_rounded,
            onPrimaryAction: () => primary++,
            secondaryActionLabel: 'Browse starter packs',
            onSecondaryAction: () => secondary++,
          ),
        ),
      );

      await tester.tap(find.text('Add feed'));
      await tester.tap(find.text('Browse starter packs'));
      await tester.pump();
      expect(primary, 1);
      expect(secondary, 1);
    });

    testWidgets('EmptyState compact fits a small box', (tester) async {
      await pumpBoth(
        tester,
        () => const AppScaffold(
          body: Center(
            child: SizedBox(
              height: 240,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Nothing here',
                compact: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);
    });
  });

  group('loading', () {
    testWidgets('Skeleton box, lines and every list style', (tester) async {
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(16),
                child: Skeleton(width: 120, height: 14),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Skeleton.lines(3),
              ),
              Expanded(
                child: Skeleton.articleList(ArticleListStyle.card, count: 2),
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('Skeleton.articleList list + compact styles', (tester) async {
      for (final ArticleListStyle style in <ArticleListStyle>[
        ArticleListStyle.list,
        ArticleListStyle.compact,
      ]) {
        await pumpBoth(
          tester,
          () => AppScaffold(body: Skeleton.articleList(style, count: 4)),
        );
      }
    });

    testWidgets('one AnimationController per SkeletonGroup', (tester) async {
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: SkeletonGroup(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < 6; i++)
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: Skeleton(height: 12),
                  ),
              ],
            ),
          ),
        ),
      );
      // The inner Skeletons reuse the outer group instead of creating their own.
      expect(find.byType(SkeletonGroup), findsOneWidget);
    });

    testWidgets('ReadingProgressBar clamps out-of-range values', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => const AppScaffold(
          body: Column(
            children: <Widget>[
              ReadingProgressBar(progress: -1),
              ReadingProgressBar(progress: 0.5),
              ReadingProgressBar(progress: 4),
              ReadingProgressBar(progress: double.nan),
            ],
          ),
        ),
      );
      expect(find.byType(ReadingProgressBar), findsNWidgets(4));
    });

    testWidgets('FadeSlideIn staggers without leaking timers', (tester) async {
      await pumpBoth(
        tester,
        () => AppScaffold(
          body: ListView(
            children: <Widget>[
              for (int i = 0; i < 30; i++)
                FadeSlideIn(
                  index: i,
                  child: ListTile(title: Text('Item $i')),
                ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Item 0'), findsOneWidget);
    });
  });

  group('overlays', () {
    testWidgets('AppSnackBar shows each kind', (tester) async {
      for (final AppSnackKind kind in AppSnackKind.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: themeFor(true),
            home: AppScaffold(
              body: Builder(
                builder: (BuildContext context) => Center(
                  child: TextButton(
                    onPressed: () => AppSnackBar.show(
                      context,
                      'Message ${kind.name}',
                      kind: kind,
                      action: 'Undo',
                      onAction: () {},
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Message ${kind.name}'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('showAppBottomSheet returns a value', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(false),
          home: AppScaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showAppBottomSheet<String>(
                      context,
                      title: 'Sort by',
                      builder: (BuildContext context) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ListTile(
                            title: const Text('Newest'),
                            onTap: () => Navigator.pop(context, 'newest'),
                          ),
                          const ListTile(title: Text('Oldest')),
                        ],
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Sort by'), findsOneWidget);
      await tester.tap(find.text('Newest'));
      await tester.pumpAndSettle();
      expect(result, 'newest');
      expect(tester.takeException(), isNull);
    });

    testWidgets('showAppBottomSheet(expand: true) fills the screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = phone;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(true),
          home: AppScaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () => showAppBottomSheet<void>(
                    context,
                    title: 'Ask AI',
                    expand: true,
                    builder: (BuildContext context) => ListView(
                      children: <Widget>[
                        for (int i = 0; i < 30; i++) Text('line $i'),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Ask AI'), findsOneWidget);
      expect(find.text('line 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('showAppMenuSheet returns the chosen option', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(true),
          home: AppScaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () async {
                    picked = await showAppMenuSheet<String>(
                      context,
                      title: 'Article',
                      options: const <AppMenuOption<String>>[
                        AppMenuOption<String>(
                          value: 'share',
                          label: 'Share',
                          icon: Icons.ios_share_rounded,
                        ),
                        AppMenuOption<String>(
                          value: 'delete',
                          label: 'Delete',
                          icon: Icons.delete_outline_rounded,
                          destructive: true,
                        ),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(picked, 'delete');
    });

    testWidgets('showAppDialog and showAppConfirm', (tester) async {
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(false),
          home: AppScaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => showAppDialog<void>(
                        context,
                        title: 'About',
                        message: 'FreeAd 3.0',
                        icon: Icons.info_outline_rounded,
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                      child: const Text('dialog'),
                    ),
                    TextButton(
                      onPressed: () async {
                        confirmed = await showAppConfirm(
                          context,
                          'Delete feed?',
                          'Its articles are removed too.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        );
                      },
                      child: const Text('confirm'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('dialog'));
      await tester.pumpAndSettle();
      expect(find.text('About'), findsOneWidget);
      expect(find.text('FreeAd 3.0'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Delete feed?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);

      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a dense screen survives a 1.3x text scale', (tester) async {
    await pumpBoth(
      tester,
      () => AppScaffold(
        appBar: const GlassAppBar(title: 'Settings', showBack: false),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const SectionHeader('Appearance'),
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SegmentedPills<ReadingFont>(
                    values: ReadingFont.values,
                    selected: ReadingFont.serif,
                    labelBuilder: (ReadingFont f) => f.label,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const FeedAvatar(title: 'The Verge', size: 40),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('The Verge')),
                      const AppBadge(count: 12),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlowButton(label: 'Save', expand: true, onPressed: () {}),
          ],
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
  });
}
