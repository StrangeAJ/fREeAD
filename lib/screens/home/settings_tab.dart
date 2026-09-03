import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_settings.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/accent.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ui/ui.dart';
import '../feeds/opml_actions.dart';
import '../settings/ai_settings_screens.dart';

const String kGithubUrl = 'https://github.com/StrangeAJ/fREeAD';

/// The fourth tab: every setting, grouped into cards.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return AppScaffold(
      backgroundColor: Colors.transparent,
      appBar: const GlassAppBar(title: 'Settings', showBack: false),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          t.spaceL,
          t.spaceS,
          t.spaceL,
          t.space3xl * 3,
        ),
        children: const <Widget>[
          _AppearanceSection(),
          _ReadingSection(),
          _FeedsSection(),
          _AiSection(),
          _DataSection(),
          _AboutSection(),
        ],
      ),
    );
  }
}

// =============================================================================
// Shared building blocks
// =============================================================================

/// A titled group of rows on one surface card.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children, this.icon});

  final String label;
  final List<Widget> children;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          label: label,
          icon: icon,
          padding: EdgeInsets.fromLTRB(0, t.spaceL, 0, t.spaceS),
        ),
        SurfaceCard(
          padding: EdgeInsets.symmetric(vertical: t.spaceXs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// A switch row.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: enabled ? t.textPrimary : t.textTertiary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
            ),
      contentPadding: EdgeInsets.symmetric(horizontal: t.spaceL),
    );
  }
}

/// A tappable row that opens a screen or a sheet.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.trailingText,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? trailingText;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color color = destructive ? t.danger : t.textPrimary;

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: t.spaceL),
      leading: icon == null
          ? null
          : Icon(
              icon,
              size: 20,
              color: destructive ? t.danger : t.textSecondary,
            ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (trailingText != null)
            Text(
              trailingText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
            ),
          Icon(Icons.chevron_right_rounded, size: 20, color: t.textTertiary),
        ],
      ),
    );
  }
}

/// A label + segmented control row.
class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.title,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelBuilder;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.spaceL, t.spaceM, t.spaceL, t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (subtitle != null)
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
              ),
            ),
          SizedBox(height: t.spaceS),
          SegmentedPills<T>(
            values: values,
            selected: selected,
            onChanged: onChanged,
            labelBuilder: labelBuilder,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// A label + slider row with a live value readout.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.readout,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String readout;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.spaceL, t.spaceS, t.spaceL, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                readout,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: t.accent),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Appearance
// =============================================================================

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final bool dynamicSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return _Group(
      label: 'Appearance',
      icon: Icons.palette_outlined,
      children: <Widget>[
        _SegmentRow<ThemeMode>(
          title: 'Theme',
          values: const <ThemeMode>[
            ThemeMode.system,
            ThemeMode.light,
            ThemeMode.dark,
          ],
          selected: settings.themeMode,
          onChanged: settings.setThemeMode,
          labelBuilder: (ThemeMode mode) => switch (mode) {
            ThemeMode.system => 'System',
            ThemeMode.light => 'Light',
            ThemeMode.dark => 'Dark',
          },
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(t.spaceL, t.spaceM, t.spaceL, t.spaceM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Accent', style: Theme.of(context).textTheme.bodyLarge),
              SizedBox(height: t.spaceM),
              Row(
                children: <Widget>[
                  for (final AppAccent accent in AppAccent.values)
                    Padding(
                      padding: EdgeInsets.only(right: t.spaceM),
                      child: _AccentSwatch(
                        accent: accent,
                        selected: settings.accent == accent,
                        onTap: () => settings.setAccent(accent),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _SwitchRow(
          title: 'Dynamic colour',
          subtitle: dynamicSupported
              ? 'Follow the Android wallpaper palette'
              : 'Android 12+ only',
          value: settings.useDynamicColor,
          enabled: dynamicSupported,
          onChanged: settings.setUseDynamicColor,
        ),
        _SwitchRow(
          title: 'Pure black',
          subtitle: 'True black backgrounds in dark mode (AMOLED)',
          value: settings.pureBlack,
          onChanged: settings.setPureBlack,
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _SegmentRow<ArticleListStyle>(
          title: 'Article list style',
          values: ArticleListStyle.values,
          selected: settings.articleListStyle,
          onChanged: settings.setArticleListStyle,
          labelBuilder: (ArticleListStyle s) => s.label,
        ),
        _SwitchRow(
          title: 'Show images',
          subtitle: 'Thumbnails in lists and images in articles',
          value: settings.showImages,
          onChanged: settings.setShowImages,
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color color = isDark ? accent.darkPrimary : accent.lightPrimary;

    return Semantics(
      label: accent.label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? t.textPrimary : t.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: color.computeLuminance() > 0.45
                      ? const Color(0xFF000000)
                      : const Color(0xFFFFFFFF),
                )
              : null,
        ),
      ),
    );
  }
}

// =============================================================================
// Reading
// =============================================================================

class _ReadingSection extends StatelessWidget {
  const _ReadingSection();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return _Group(
      label: 'Reading',
      icon: Icons.chrome_reader_mode_outlined,
      children: <Widget>[
        _SegmentRow<ReadingFont>(
          title: 'Reading font',
          values: ReadingFont.values,
          selected: settings.readingFont,
          onChanged: settings.setReadingFont,
          labelBuilder: (ReadingFont f) => f.label,
        ),
        _SliderRow(
          title: 'Font size',
          value: settings.fontSize,
          min: 14,
          max: 26,
          divisions: 12,
          readout: '${settings.fontSize.round()} pt',
          onChanged: settings.setFontSize,
        ),
        _SliderRow(
          title: 'Line height',
          value: settings.lineHeight,
          min: 1.3,
          max: 2.0,
          divisions: 14,
          readout: settings.lineHeight.toStringAsFixed(2),
          onChanged: settings.setLineHeight,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(t.spaceL, t.spaceS, t.spaceL, t.spaceL),
          child: Container(
            padding: EdgeInsets.all(t.spaceM),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: t.borderRadiusS,
              border: Border.all(color: t.hairline),
            ),
            child: Text(
              'The quick brown fox reads the news. This is how article body '
              'text will look with your current font, size and spacing.',
              style: AppTypography.readingBody(
                settings.readingFont,
                settings.fontSize,
                settings.lineHeight,
              ).copyWith(color: t.textPrimary),
            ),
          ),
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _SwitchRow(
          title: 'Auto-load full article',
          subtitle: 'Fetch the whole page when the feed only ships a summary',
          value: settings.autoLoadFullArticle,
          onChanged: settings.setAutoLoadFullArticle,
        ),
        _SegmentRow<ExtractionEngine>(
          title: 'Extraction engine',
          subtitle: settings.extractionEngine.description,
          values: ExtractionEngine.values,
          selected: settings.extractionEngine,
          onChanged: settings.setExtractionEngine,
          labelBuilder: (ExtractionEngine e) => e.label,
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _SwitchRow(
          title: 'Mark read on open',
          value: settings.markReadOnOpen,
          onChanged: settings.setMarkReadOnOpen,
        ),
        _SwitchRow(
          title: 'Remember position',
          subtitle: 'Reopen an article where you left off',
          value: settings.rememberScrollPosition,
          onChanged: settings.setRememberScrollPosition,
        ),
      ],
    );
  }
}

// =============================================================================
// Feeds & sync
// =============================================================================

class _FeedsSection extends StatefulWidget {
  const _FeedsSection();

  @override
  State<_FeedsSection> createState() => _FeedsSectionState();
}

class _FeedsSectionState extends State<_FeedsSection> {
  bool _cleaning = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return _Group(
      label: 'Feeds & sync',
      icon: Icons.sync_rounded,
      children: <Widget>[
        _SwitchRow(
          title: 'Refresh on launch',
          subtitle: 'When the last refresh is older than the interval',
          value: settings.refreshOnLaunch,
          onChanged: settings.setRefreshOnLaunch,
        ),
        _NavRow(
          title: 'Refresh interval',
          trailingText: _intervalLabel(settings.refreshIntervalMinutes),
          onTap: () => _pickInterval(settings),
        ),
        _SwitchRow(
          title: 'Prefetch full articles',
          subtitle: 'Cache article text after a refresh, for offline reading',
          value: settings.prefetchFullArticles,
          onChanged: settings.setPrefetchFullArticles,
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _NavRow(
          title: 'Keep articles for',
          trailingText: _retentionLabel(settings.articleRetentionDays),
          onTap: () => _pickRetention(settings),
        ),
        ListTile(
          onTap: _cleaning ? null : () => _cleanUp(settings),
          contentPadding: EdgeInsets.symmetric(horizontal: t.spaceL),
          leading: Icon(
            Icons.cleaning_services_outlined,
            size: 20,
            color: t.textSecondary,
          ),
          title: Text(
            'Clean up now',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          subtitle: Text(
            'Deletes old articles, keeping saved and starred ones',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
          ),
          trailing: _cleaning
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  static String _intervalLabel(int minutes) => switch (minutes) {
    0 => 'Never',
    15 => 'Every 15 min',
    30 => 'Every 30 min',
    60 => 'Hourly',
    180 => 'Every 3 hours',
    _ => 'Every $minutes min',
  };

  static String _retentionLabel(int days) =>
      days <= 0 ? 'Forever' : '$days days';

  Future<void> _pickInterval(SettingsProvider settings) async {
    final int? picked = await showAppMenuSheet<int>(
      context,
      title: 'Refresh interval',
      options: <AppMenuOption<int>>[
        for (final int minutes in SettingsProvider.refreshIntervalOptions)
          AppMenuOption<int>(
            value: minutes,
            label: _intervalLabel(minutes),
            icon: settings.refreshIntervalMinutes == minutes
                ? Icons.check_rounded
                : null,
          ),
      ],
    );
    if (picked != null) await settings.setRefreshIntervalMinutes(picked);
  }

  Future<void> _pickRetention(SettingsProvider settings) async {
    final int? picked = await showAppMenuSheet<int>(
      context,
      title: 'Keep articles for',
      options: <AppMenuOption<int>>[
        for (final int days in SettingsProvider.retentionOptions)
          AppMenuOption<int>(
            value: days,
            label: _retentionLabel(days),
            icon: settings.articleRetentionDays == days
                ? Icons.check_rounded
                : null,
          ),
      ],
    );
    if (picked != null) await settings.setArticleRetentionDays(picked);
  }

  Future<void> _cleanUp(SettingsProvider settings) async {
    final int days = settings.articleRetentionDays;
    if (days <= 0) {
      AppSnackBar.show(
        context,
        'Retention is set to Forever - nothing to clean up.',
      );
      return;
    }

    setState(() => _cleaning = true);
    final int deleted = await context
        .read<ArticleProvider>()
        .cleanupOldArticles(days);
    if (!mounted) return;
    setState(() => _cleaning = false);
    AppSnackBar.success(
      context,
      deleted == 0
          ? 'Nothing to clean up'
          : 'Deleted $deleted old article${deleted == 1 ? '' : 's'}',
    );
  }
}

// =============================================================================
// AI
// =============================================================================

class _AiSection extends StatelessWidget {
  const _AiSection();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final String provider = settings.summarizationProvider;

    return _Group(
      label: 'AI',
      icon: Icons.auto_awesome_outlined,
      children: <Widget>[
        _NavRow(
          title: 'Provider',
          subtitle: settings.hasKeyFor(provider)
              ? settings.getModelForProvider(provider)
              : 'No API key configured',
          trailingText: settings.labelForProvider(provider),
          onTap: () => _pickProvider(context, settings),
        ),
        _NavRow(
          title: 'API keys',
          icon: Icons.key_outlined,
          subtitle: 'Stored in the device keystore',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AiApiKeysScreen()),
          ),
        ),
        _NavRow(
          title: 'Models',
          icon: Icons.memory_rounded,
          subtitle: 'Fetch the live list from each provider',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AiModelsScreen()),
          ),
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _SwitchRow(
          title: 'Auto-save summaries',
          subtitle: 'Keep generated summaries with the article',
          value: settings.autoSaveSummaries,
          onChanged: settings.setAutoSaveSummaries,
        ),
        _SegmentRow<SummaryStyle>(
          title: 'Summary style',
          values: SummaryStyle.values,
          selected: settings.summaryStyle,
          onChanged: settings.setSummaryStyle,
          labelBuilder: (SummaryStyle s) => s.label,
        ),
      ],
    );
  }

  static Future<void> _pickProvider(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final String? picked = await showAppMenuSheet<String>(
      context,
      title: 'AI provider',
      options: <AppMenuOption<String>>[
        for (final MapEntry<String, String> entry
            in settings.availableAiProviders)
          AppMenuOption<String>(
            value: entry.key,
            label: entry.value,
            subtitle: settings.hasKeyFor(entry.key)
                ? settings.getModelForProvider(entry.key)
                : 'No API key',
            icon: settings.summarizationProvider == entry.key
                ? Icons.check_rounded
                : null,
          ),
      ],
    );
    if (picked == null || !context.mounted) return;
    await settings.setSummarizationProvider(picked);
    if (!context.mounted) return;
    if (!settings.hasKeyFor(picked)) {
      AppSnackBar.show(
        context,
        'Add an API key for ${settings.labelForProvider(picked)}.',
        action: 'API keys',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AiApiKeysScreen()),
        ),
      );
    }
  }
}

// =============================================================================
// Data
// =============================================================================

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return _Group(
      label: 'Data',
      icon: Icons.storage_outlined,
      children: <Widget>[
        _NavRow(
          title: 'Import OPML',
          icon: Icons.file_download_outlined,
          onTap: () => OpmlActions.import(context),
        ),
        _NavRow(
          title: 'Export OPML',
          icon: Icons.file_upload_outlined,
          onTap: () => OpmlActions.export(context),
        ),
        Divider(
          height: 1,
          color: t.hairline,
          indent: t.spaceL,
          endIndent: t.spaceL,
        ),
        _NavRow(
          title: 'Clear cached full articles',
          icon: Icons.delete_sweep_outlined,
          subtitle: 'Frees space; articles reload on demand',
          onTap: () => _clearFullContent(context),
        ),
        _NavRow(
          title: 'Reset all settings',
          icon: Icons.restart_alt_rounded,
          destructive: true,
          onTap: () => _resetSettings(context),
        ),
      ],
    );
  }

  static Future<void> _clearFullContent(BuildContext context) async {
    final bool confirmed = await showAppConfirm(
      context,
      'Clear cached articles?',
      'Extracted article text is deleted. Feeds, saved and starred articles '
          'are untouched.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final int cleared = await context
        .read<ArticleProvider>()
        .clearFullContent();
    if (!context.mounted) return;
    AppSnackBar.success(
      context,
      cleared == 0
          ? 'Nothing was cached'
          : 'Cleared $cleared cached article${cleared == 1 ? '' : 's'}',
    );
  }

  static Future<void> _resetSettings(BuildContext context) async {
    final bool confirmed = await showAppConfirm(
      context,
      'Reset all settings?',
      'Every preference returns to its default. Your feeds, articles and API '
          'keys stay.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await context.read<SettingsProvider>().resetAllSettings();
    if (!context.mounted) return;
    AppSnackBar.success(context, 'Settings reset');
  }
}

// =============================================================================
// About
// =============================================================================

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (e) {
      AppLog.w('Could not read package info', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();

    return _Group(
      label: 'About',
      icon: Icons.info_outline_rounded,
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: t.spaceL),
          leading: Icon(Icons.rss_feed_rounded, color: t.accent),
          title: Text('FreeAd', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _version.isEmpty ? 'Loading version...' : 'Version $_version',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
          ),
          trailing: Text(
            '${feeds.feeds.length} feeds',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
          ),
        ),
        _NavRow(
          title: "What's new in 3.0",
          icon: Icons.auto_awesome_mosaic_outlined,
          onTap: () => _showWhatsNew(context),
        ),
        _NavRow(
          title: 'Open-source licenses',
          icon: Icons.gavel_rounded,
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'FreeAd',
            applicationVersion: _version,
          ),
        ),
        _NavRow(
          title: 'GitHub',
          icon: Icons.code_rounded,
          subtitle: 'StrangeAJ/fREeAD',
          onTap: () async {
            final Uri uri = Uri.parse(kGithubUrl);
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (e) {
              AppLog.w('Could not open GitHub', e);
              if (context.mounted) {
                AppSnackBar.error(context, 'Could not open the link.');
              }
            }
          },
        ),
      ],
    );
  }

  static const List<String> _whatsNew = <String>[
    'Rebuilt article extraction - readability, AMP and a headless browser '
        'fallback for JavaScript-heavy sites.',
    'The reader renders real HTML again: headings, images, lists, quotes '
        'and code.',
    'Ask AI about any article, with streaming answers and a saved '
        'conversation.',
    'Feed discovery from any site URL, favicons and starter packs.',
    'Real categories: auto-categorize offline or with AI, grouped Feeds tab, '
        'unread counts everywhere.',
    'RSS dates parse correctly, so sorting finally means something.',
    'New design system with light/dark, six accents and a pure-black mode.',
  ];

  static Future<void> _showWhatsNew(BuildContext context) {
    return showAppBottomSheet<void>(
      context,
      title: "What's new in 3.0",
      builder: (BuildContext context) {
        final AppTokens t = context.tokens;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final String item in _whatsNew)
              Padding(
                padding: EdgeInsets.only(bottom: t.spaceM),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.only(top: 6, right: t.spaceM),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
