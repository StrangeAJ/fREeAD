import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/categorization_service.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ui/ui.dart';

/// Suggests a category for every feed - offline by keyword, or with the
/// configured model - and applies the ones the user keeps.
class AutoCategorizeScreen extends StatefulWidget {
  const AutoCategorizeScreen({super.key});

  @override
  State<AutoCategorizeScreen> createState() => _AutoCategorizeScreenState();
}

class _AutoCategorizeScreenState extends State<AutoCategorizeScreen> {
  bool _running = false;
  String? _error;

  /// Suggestions, in feed order. Empty until a run finishes.
  List<CategorySuggestion> _suggestions = const <CategorySuggestion>[];

  /// Feed ids the user unticked.
  final Set<String> _rejected = <String>{};

  /// Per-feed overrides picked from the dropdown.
  final Map<String, String> _overrides = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final bool aiReady = settings.hasKeyFor(settings.summarizationProvider);
    final int changeCount = _pendingChanges().length;

    return AppScaffold(
      appBar: const GlassAppBar(title: 'Auto-categorize'),
      bottomBar: _suggestions.isEmpty
          ? null
          : GlassBottomBar(
              opaque: true,
              padding: EdgeInsets.all(t.spaceM),
              child: GlowButton(
                label: changeCount == 0
                    ? 'No changes selected'
                    : 'Apply $changeCount change'
                          '${changeCount == 1 ? '' : 's'}',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: changeCount == 0 ? null : _apply,
              ),
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          t.spaceL,
          t.spaceS,
          t.spaceL,
          t.space3xl * 3,
        ),
        children: <Widget>[
          Text(
            'Sort ${feeds.feeds.length} feed'
            '${feeds.feeds.length == 1 ? '' : 's'} into categories. '
            'Review every suggestion before applying.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: t.textSecondary),
          ),
          SizedBox(height: t.spaceL),
          Row(
            children: <Widget>[
              Expanded(
                child: _ModeCard(
                  icon: Icons.bolt_rounded,
                  title: 'Quick',
                  subtitle: 'Offline keyword matching. Instant.',
                  enabled: !_running && feeds.feeds.isNotEmpty,
                  onTap: () => _run(ai: false),
                ),
              ),
              SizedBox(width: t.spaceM),
              Expanded(
                child: _ModeCard(
                  icon: Icons.auto_awesome_outlined,
                  title: 'AI',
                  subtitle: aiReady
                      ? 'Ask ${settings.labelForProvider(settings.summarizationProvider)}.'
                      : 'Add an API key in Settings > AI first.',
                  enabled: !_running && aiReady && feeds.feeds.isNotEmpty,
                  onTap: () => _run(ai: true),
                ),
              ),
            ],
          ),
          if (_running) ...<Widget>[
            SizedBox(height: t.spaceXl),
            LinearProgressIndicator(
              minHeight: 2,
              color: t.accent,
              backgroundColor: t.surface2,
            ),
            SizedBox(height: t.spaceS),
            Text(
              'Categorizing...',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
            ),
          ],
          if (_error != null) ...<Widget>[
            SizedBox(height: t.spaceL),
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.danger),
            ),
          ],
          if (_suggestions.isNotEmpty) ...<Widget>[
            SizedBox(height: t.spaceL),
            SectionHeader(
              label: 'Suggestions',
              actionLabel: 'Reset',
              onAction: () => setState(() {
                _rejected.clear();
                _overrides.clear();
              }),
              padding: EdgeInsets.only(bottom: t.spaceS),
            ),
            for (final CategorySuggestion suggestion in _suggestions)
              _SuggestionRow(
                key: ValueKey<String>('suggest-${suggestion.feedId}'),
                suggestion: suggestion,
                feed: feeds.getFeedById(suggestion.feedId),
                categories: feeds.categories,
                current: feeds.getCategoryById(suggestion.currentCategoryId),
                selectedId:
                    _overrides[suggestion.feedId] ??
                    suggestion.suggestedCategoryId,
                newCategoryName: _overrides.containsKey(suggestion.feedId)
                    ? null
                    : suggestion.newCategoryName,
                accepted: !_rejected.contains(suggestion.feedId),
                onToggle: (bool value) => setState(() {
                  if (value) {
                    _rejected.remove(suggestion.feedId);
                  } else {
                    _rejected.add(suggestion.feedId);
                  }
                }),
                onCategoryChanged: (String id) =>
                    setState(() => _overrides[suggestion.feedId] = id),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Running
  // ---------------------------------------------------------------------------

  Future<void> _run({required bool ai}) async {
    final FeedProvider feeds = context.read<FeedProvider>();
    final List<RSSFeed> allFeeds = feeds.feeds;
    final List<Category> categories = feeds.categories.isEmpty
        ? Category.defaultCategories
        : feeds.categories;

    setState(() {
      _running = true;
      _error = null;
      _suggestions = const <CategorySuggestion>[];
      _rejected.clear();
      _overrides.clear();
    });

    try {
      List<CategorySuggestion> result;
      if (ai) {
        final AiService service = AiService(
          configSource: SettingsAiConfigSource(
            context.read<SettingsProvider>(),
          ),
        );
        result = await aiCategorize(allFeeds, categories, ai: service);
      } else {
        final Map<String, String> quick = quickCategorize(allFeeds, categories);
        result = <CategorySuggestion>[
          for (final RSSFeed feed in allFeeds)
            CategorySuggestion(
              feedId: feed.id,
              currentCategoryId: feed.categoryId,
              suggestedCategoryId:
                  quick[feed.id] ?? FeedProvider.defaultCategoryId,
            ),
        ];
      }
      if (!mounted) return;
      // Only show rows that would actually change something.
      setState(() {
        _suggestions = result
            .where((CategorySuggestion s) => s.isChange)
            .toList();
        _running = false;
        if (_suggestions.isEmpty) {
          _error = 'Every feed is already in the right category.';
        }
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.userMessage;
      });
    } catch (e) {
      AppLog.e('Auto-categorize failed', e);
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'Categorization failed. Try the Quick mode.';
      });
    }
  }

  List<CategorySuggestion> _pendingChanges() => _suggestions
      .where((CategorySuggestion s) => !_rejected.contains(s.feedId))
      .toList();

  // ---------------------------------------------------------------------------
  // Applying
  // ---------------------------------------------------------------------------

  Future<void> _apply() async {
    final FeedProvider feeds = context.read<FeedProvider>();
    final ArticleProvider articles = context.read<ArticleProvider>();
    final List<CategorySuggestion> pending = _pendingChanges();

    setState(() => _running = true);

    // Remember what to roll back to.
    final Map<String, String?> previous = <String, String?>{
      for (final CategorySuggestion s in pending)
        s.feedId: feeds.getFeedById(s.feedId)?.categoryId,
    };

    // Create any brand new categories the model proposed (unless overridden).
    final Map<String, String> createdByName = <String, String>{};
    for (final CategorySuggestion suggestion in pending) {
      final String? newName = suggestion.newCategoryName;
      if (newName == null || _overrides.containsKey(suggestion.feedId)) {
        continue;
      }
      if (createdByName.containsKey(newName)) continue;
      final Category? created = await feeds.addCategory(newName);
      if (created != null) createdByName[newName] = created.id;
    }

    var applied = 0;
    for (final CategorySuggestion suggestion in pending) {
      final String? override = _overrides[suggestion.feedId];
      final String? created = suggestion.newCategoryName == null
          ? null
          : createdByName[suggestion.newCategoryName!];
      final String target =
          override ?? created ?? suggestion.suggestedCategoryId;

      final RSSFeed? feed = feeds.getFeedById(suggestion.feedId);
      if (feed == null || feed.categoryId == target) continue;
      final bool ok = await feeds.updateFeed(feed.copyWith(categoryId: target));
      if (ok) applied++;
    }

    await feeds.loadFeeds();
    await articles.loadArticles();
    if (!mounted) return;

    setState(() {
      _running = false;
      _suggestions = const <CategorySuggestion>[];
      _rejected.clear();
      _overrides.clear();
    });

    AppSnackBar.show(
      context,
      applied == 0
          ? 'Nothing changed'
          : 'Recategorized $applied feed${applied == 1 ? '' : 's'}',
      kind: AppSnackKind.success,
      action: applied == 0 ? null : 'Undo',
      onAction: applied == 0 ? null : () => _undo(previous),
    );
  }

  Future<void> _undo(Map<String, String?> previous) async {
    final FeedProvider feeds = context.read<FeedProvider>();
    for (final MapEntry<String, String?> entry in previous.entries) {
      final RSSFeed? feed = feeds.getFeedById(entry.key);
      if (feed == null) continue;
      await feeds.updateFeed(
        feed.copyWith(
          categoryId: entry.value ?? FeedProvider.defaultCategoryId,
        ),
      );
    }
    await feeds.loadFeeds();
    if (!mounted) return;
    AppSnackBar.show(context, 'Reverted');
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      level: 2,
      padding: EdgeInsets.all(t.spaceM),
      onTap: enabled ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 22, color: enabled ? t.accent : t.textTertiary),
          SizedBox(height: t.spaceS),
          Text(
            title,
            style: text.titleSmall?.copyWith(
              color: enabled ? t.textPrimary : t.textTertiary,
            ),
          ),
          SizedBox(height: 2),
          Text(
            subtitle,
            style: text.bodySmall?.copyWith(color: t.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    super.key,
    required this.suggestion,
    required this.feed,
    required this.categories,
    required this.current,
    required this.selectedId,
    required this.newCategoryName,
    required this.accepted,
    required this.onToggle,
    required this.onCategoryChanged,
  });

  final CategorySuggestion suggestion;
  final RSSFeed? feed;
  final List<Category> categories;
  final Category? current;
  final String selectedId;
  final String? newCategoryName;
  final bool accepted;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final Color confidenceColor = suggestion.confidence >= 0.75
        ? t.success
        : suggestion.confidence >= 0.5
        ? t.warning
        : t.danger;

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.all(t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              FeedAvatar(
                title: feed?.title ?? suggestion.feedId,
                feedId: suggestion.feedId,
                imageUrl: feed?.iconUrl,
                size: 24,
              ),
              SizedBox(width: t.spaceM),
              Expanded(
                child: Text(
                  feed?.title ?? suggestion.feedId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(color: t.textPrimary),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(right: t.spaceS),
                decoration: BoxDecoration(
                  color: confidenceColor,
                  shape: BoxShape.circle,
                ),
              ),
              Switch(value: accepted, onChanged: onToggle),
            ],
          ),
          SizedBox(height: t.spaceS),
          Row(
            children: <Widget>[
              Text(
                current?.name ?? 'General',
                style: text.bodySmall?.copyWith(color: t.textTertiary),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.spaceS),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: t.textTertiary,
                ),
              ),
              Expanded(
                child: newCategoryName != null
                    ? PillChip(
                        label: 'New: $newCategoryName',
                        icon: Icons.add_rounded,
                        selected: true,
                        dense: true,
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value:
                              categories.any((Category c) => c.id == selectedId)
                              ? selectedId
                              : null,
                          isExpanded: true,
                          isDense: true,
                          borderRadius: t.borderRadiusS,
                          style: text.bodyMedium?.copyWith(color: t.accent),
                          onChanged: (String? id) {
                            if (id != null) onCategoryChanged(id);
                          },
                          items: <DropdownMenuItem<String>>[
                            for (final Category category in categories)
                              DropdownMenuItem<String>(
                                value: category.id,
                                child: Text(
                                  category.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
