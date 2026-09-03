import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ui/ui.dart';
import '../feeds/add_feed_sheet.dart';
import 'feeds_tab.dart';
import 'home_tab.dart';
import 'saved_tab.dart';
import 'settings_tab.dart';

/// Lets any descendant switch tabs, e.g. an AI error banner that offers to
/// open Settings.
class HomeShellScope extends InheritedWidget {
  const HomeShellScope({
    super.key,
    required this.goToTab,
    required this.currentIndex,
    required super.child,
  });

  final ValueChanged<int> goToTab;
  final int currentIndex;

  static const int homeIndex = 0;
  static const int feedsIndex = 1;
  static const int savedIndex = 2;
  static const int settingsIndex = 3;

  static HomeShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeShellScope>();

  /// Switches the shell to [index]; a no-op outside the shell.
  static void go(BuildContext context, int index) =>
      maybeOf(context)?.goToTab(index);

  @override
  bool updateShouldNotify(HomeShellScope oldWidget) =>
      oldWidget.currentIndex != currentIndex;
}

/// The app shell: four tabs behind a Material 3 [NavigationBar].
///
/// **Do not swap this for `BottomNavigationBar`.** `AppTheme` only styles
/// `navigationBarTheme` (accent icon/label when selected, `textSecondary` when
/// not, an `accentSoft` pill indicator, transparent background so
/// [GlassBottomBar] supplies the blur). The Material 2 `BottomNavigationBar`
/// reads `bottomNavigationBarTheme`, which the theme deliberately does not
/// define - that is why the v2 shell rendered near-invisible icons on the dark
/// background.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfStale());
  }

  Future<void> _refreshIfStale() async {
    if (!mounted) return;
    final ArticleProvider articles = context.read<ArticleProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    try {
      await articles.refreshIfStale(settings);
    } catch (e) {
      AppLog.w('Startup refresh failed', e);
    }
  }

  void _goToTab(int index) {
    if (!mounted || index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int unread = context.select<FeedProvider, int>(
      (FeedProvider p) => p.totalUnread,
    );
    final bool showFab =
        _index == HomeShellScope.homeIndex ||
        _index == HomeShellScope.feedsIndex;

    return HomeShellScope(
      goToTab: _goToTab,
      currentIndex: _index,
      child: AppScaffold(
        body: IndexedStack(
          index: _index,
          children: const <Widget>[
            HomeTab(),
            FeedsTab(),
            SavedTab(),
            SettingsTab(),
          ],
        ),
        floatingActionButton: AnimatedScale(
          scale: showFab ? 1 : 0,
          duration: AppTokens.motionFast,
          curve: AppTokens.motionCurve,
          child: FloatingActionButton(
            onPressed: showFab ? () => showAddFeedSheet(context) : null,
            tooltip: 'Add feed',
            child: const Icon(Icons.add_rounded),
          ),
        ),
        bottomBar: GlassBottomBar(
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _goToTab,
            backgroundColor: Colors.transparent,
            elevation: 0,
            destinations: <Widget>[
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  backgroundColor: t.accent,
                  textColor: t.onAccent,
                  label: Text(unread > 999 ? '999+' : '$unread'),
                  child: const Icon(Icons.home_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  backgroundColor: t.accent,
                  textColor: t.onAccent,
                  label: Text(unread > 999 ? '999+' : '$unread'),
                  child: const Icon(Icons.home_rounded),
                ),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.rss_feed_outlined),
                selectedIcon: Icon(Icons.rss_feed_rounded),
                label: 'Feeds',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bookmark_border_rounded),
                selectedIcon: Icon(Icons.bookmark_rounded),
                label: 'Saved',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
