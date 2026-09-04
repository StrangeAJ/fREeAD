import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'providers/article_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/feeds/feed_articles_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reader/article_reading_screen.dart';
import 'services/ai/ai_service.dart';
import 'services/database_service.dart';
import 'services/notifications/feed_refresh_task.dart';
import 'services/notifications/notification_payload.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/refresh_scheduler.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'utils/app_logger.dart';

/// Lets notification taps navigate without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Routes a notification tap to the right screen. Safe to call before the
/// first frame (no-op until the navigator exists).
Future<void> routeNotificationTap(NotificationPayload payload) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  try {
    if (payload.isArticle && payload.id != null) {
      final article = await DatabaseService().getArticleById(payload.id!);
      if (article == null) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ArticleReadingScreen(article: article),
        ),
      );
    } else if (payload.isFeed && payload.id != null) {
      final feed = await DatabaseService().getFeedById(payload.id!);
      if (feed == null) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              FeedArticlesScreen(feedId: feed.id, feedTitle: feed.title),
        ),
      );
    }
    // Home payloads need no navigation: the app already opens there.
  } catch (e, st) {
    AppLog.w('Could not route notification tap', e, st);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and gesture bars; the glass bars blur what is under
  // them.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Periodic background refresh for new-article alerts (Android only).
  try {
    if (!kIsWeb && Platform.isAndroid) {
      await Workmanager().initialize(feedRefreshDispatcher);
    }
  } catch (e, st) {
    AppLog.w('WorkManager init failed; background alerts disabled', e, st);
  }
  runApp(const FreeAdApp());
}

class FreeAdApp extends StatelessWidget {
  const FreeAdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
        ChangeNotifierProvider(create: (_) => ArticleProvider()),
        // Not a ChangeNotifier: the AI provider/model/key selection lives on
        // SettingsProvider, which SettingsAiConfigSource reads fresh on every
        // call, so AiService itself never needs to be rebuilt or notify.
        Provider<AiService>(
          create: (context) => AiService(
            configSource: SettingsAiConfigSource(
              context.read<SettingsProvider>(),
            ),
          ),
        ),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer<SettingsProvider>(
            builder: (context, settings, child) {
              final useDynamic = settings.useDynamicColor;
              return MaterialApp(
                title: 'FreeAd',
                navigatorKey: appNavigatorKey,
                theme: AppTheme.light(
                  accent: settings.accent,
                  dynamicScheme: useDynamic ? lightDynamic : null,
                  pureBlack: false,
                ),
                darkTheme: AppTheme.dark(
                  accent: settings.accent,
                  dynamicScheme: useDynamic ? darkDynamic : null,
                  pureBlack: settings.pureBlack,
                ),
                themeMode: settings.themeMode,
                themeAnimationDuration: const Duration(milliseconds: 250),
                themeAnimationCurve: Curves.easeOutCubic,
                home: const AppInitializer(),
                debugShowCheckedModeBanner: false,
                builder: (context, child) =>
                    _SystemUiStyler(child: child ?? const SizedBox.shrink()),
              );
            },
          );
        },
      ),
    );
  }
}

/// Keeps the status and navigation bars transparent and their icons legible
/// against the current theme.
class _SystemUiStyler extends StatelessWidget {
  const _SystemUiStyler({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;

    final style = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: child);
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final settingsProvider = context.read<SettingsProvider>();
    final feedProvider = context.read<FeedProvider>();
    final articleProvider = context.read<ArticleProvider>();

    final notifications = NotificationService();
    try {
      await settingsProvider.init();
      await notifications.init(onTap: routeNotificationTap);
      await notifications.ensureChannel(
        sound: settingsProvider.notificationSound,
        vibrate: settingsProvider.notificationVibrate,
      );
      await syncNotificationSchedule(settingsProvider);
      await feedProvider.loadFeeds();
      await articleProvider.loadArticles();
    } catch (e, st) {
      AppLog.e('App initialization failed', e, st);
    }

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));

    // A notification tap that cold-started the app.
    try {
      final launch = await notifications.consumeLaunchPayload();
      if (launch != null && mounted) await routeNotificationTap(launch);
    } catch (e, st) {
      AppLog.w('Could not route launch notification', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 96,
              height: 96,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.rss_feed_rounded, size: 56, color: t.accent),
            ),
            SizedBox(height: t.spaceXl),
            Text(
              'FreeAd',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: t.textPrimary,
              ),
            ),
            SizedBox(height: t.space3xl),
            SizedBox(
              width: 132,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: t.accent,
                  backgroundColor: t.surface2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
