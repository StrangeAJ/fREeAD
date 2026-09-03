import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../services/rss/feed_discovery_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ui/ui.dart';
import 'starter_packs.dart';

/// Opens the "Add feed" sheet. Resolves after the sheet closes; the result is
/// true when at least one feed was subscribed.
Future<bool> showAddFeedSheet(
  BuildContext context, {
  String? initialCategoryId,
  bool startOnPacks = false,
}) async {
  final bool? added = await showAppBottomSheet<bool>(
    context,
    title: 'Add feed',
    expand: true,
    builder: (BuildContext context) => AddFeedSheet(
      initialCategoryId: initialCategoryId,
      startOnPacks: startOnPacks,
    ),
  );
  return added ?? false;
}

/// Paste a site or feed URL, discover the feeds behind it, pick one, choose a
/// category - or subscribe to a whole curated pack.
class AddFeedSheet extends StatefulWidget {
  const AddFeedSheet({
    super.key,
    this.initialCategoryId,
    this.startOnPacks = false,
  });

  final String? initialCategoryId;
  final bool startOnPacks;

  @override
  State<AddFeedSheet> createState() => _AddFeedSheetState();
}

class _AddFeedSheetState extends State<AddFeedSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  String? _categoryId;
  bool _busy = false;
  String? _error;
  List<DiscoveredFeed> _candidates = const <DiscoveredFeed>[];
  String? _packBusyId;
  bool _addedAny = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) AppSnackBar.show(context, 'Clipboard is empty.');
      return;
    }
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _find() async {
    final String input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Enter a site or feed URL first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _candidates = const <DiscoveredFeed>[];
    });

    final FeedProvider feeds = context.read<FeedProvider>();
    final AddFeedResult result = await feeds.addFeed(
      input,
      categoryId: _categoryId,
    );
    if (!mounted) return;

    setState(() => _busy = false);

    if (result.needsSelection) {
      setState(() => _candidates = result.candidates ?? const []);
      return;
    }
    if (result.isDuplicate) {
      setState(() => _error = 'Already subscribed to this feed.');
      return;
    }
    if (result.hasError) {
      setState(() => _error = _friendly(result.error!));
      return;
    }
    await _finishOne(result);
  }

  Future<void> _addCandidate(DiscoveredFeed candidate) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final FeedProvider feeds = context.read<FeedProvider>();
    final AddFeedResult result = await feeds.addDiscoveredFeed(
      candidate,
      categoryId: _categoryId,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.isDuplicate) {
      setState(() => _error = 'Already subscribed to this feed.');
      return;
    }
    if (result.hasError) {
      setState(() => _error = _friendly(result.error!));
      return;
    }
    await _finishOne(result);
  }

  Future<void> _finishOne(AddFeedResult result) async {
    _addedAny = true;
    await context.read<ArticleProvider>().loadArticles();
    if (!mounted) return;
    final String name = result.feed?.title ?? 'Feed';
    final int count = result.newArticleCount;
    AppSnackBar.success(
      context,
      count > 0 ? 'Added $name - $count articles' : 'Added $name',
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _addPack(StarterPack pack) async {
    setState(() {
      _packBusyId = pack.id;
      _error = null;
    });

    final FeedProvider feeds = context.read<FeedProvider>();
    var added = 0;
    var skipped = 0;
    for (final StarterFeed feed in pack.feeds) {
      final AddFeedResult result = await feeds.addFeed(
        feed.url,
        categoryId: pack.categoryId,
      );
      if (result.isSuccess) {
        added++;
      } else {
        skipped++;
      }
      if (!mounted) return;
    }

    await context.read<ArticleProvider>().loadArticles();
    if (!mounted) return;
    setState(() => _packBusyId = null);

    if (added == 0) {
      AppSnackBar.error(
        context,
        'Could not add any ${pack.name} feeds. Check your connection.',
      );
      return;
    }
    _addedAny = true;
    AppSnackBar.success(
      context,
      'Added $added ${pack.name} feed${added == 1 ? '' : 's'}'
      '${skipped > 0 ? ' ($skipped skipped)' : ''}',
    );
    Navigator.of(context).pop(true);
  }

  /// Turns a provider error into something a reader can act on.
  static String _friendly(String error) {
    final String lower = error.toLowerCase();
    if (lower.contains('no feed')) {
      return 'No feeds found on that site. Try the feed URL directly.';
    }
    if (lower.contains('403') || lower.contains('blocked')) {
      return 'That site blocked the request (HTTP 403).';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'The site took too long to answer. Try again.';
    }
    if (lower.contains('socket') || lower.contains('network')) {
      return 'Network error - check your connection.';
    }
    return error;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final List<Category> categories = feeds.categories.isEmpty
        ? Category.defaultCategories
        : feeds.categories;

    return PopScope<bool>(
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: !widget.startOnPacks,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _find(),
              decoration: InputDecoration(
                hintText: 'example.com or feed URL',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  tooltip: 'Paste',
                  onPressed: _busy ? null : _paste,
                ),
              ),
            ),
            SizedBox(height: t.spaceM),
            _CategoryDropdown(
              categories: categories,
              value: _categoryId,
              enabled: !_busy,
              onChanged: (String? id) => setState(() => _categoryId = id),
            ),
            SizedBox(height: t.spaceM),
            GlowButton(
              label: 'Find feeds',
              icon: Icons.travel_explore_rounded,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _find,
            ),
            if (_error != null) ...<Widget>[
              SizedBox(height: t.spaceM),
              _ErrorBanner(message: _error!),
            ],
            if (_candidates.isNotEmpty) ...<Widget>[
              SizedBox(height: t.spaceS),
              SectionHeader(
                label: 'Feeds found',
                padding: EdgeInsets.only(top: t.spaceS, bottom: t.spaceXs),
              ),
              for (final DiscoveredFeed candidate in _candidates)
                SurfaceCard(
                  level: 2,
                  margin: EdgeInsets.only(bottom: t.spaceS),
                  padding: EdgeInsets.symmetric(
                    horizontal: t.spaceM,
                    vertical: t.spaceS,
                  ),
                  onTap: _busy ? null : () => _addCandidate(candidate),
                  child: Row(
                    children: <Widget>[
                      FeedAvatar(title: candidate.title, size: 28),
                      SizedBox(width: t.spaceM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              candidate.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              candidate.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: t.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.add_rounded, color: t.accent),
                    ],
                  ),
                ),
            ],
            SizedBox(height: t.spaceL),
            SectionHeader(
              label: 'Starter packs',
              padding: EdgeInsets.only(bottom: t.spaceS),
            ),
            Text(
              'Curated feeds that work out of the box.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
            ),
            SizedBox(height: t.spaceM),
            for (final StarterPack pack in StarterPack.all)
              _PackRow(
                pack: pack,
                busy: _packBusyId == pack.id,
                enabled: _packBusyId == null && !_busy,
                onAdd: () => _addPack(pack),
              ),
            SizedBox(height: t.spaceL),
            if (_addedAny)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Done'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Category> categories;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Set<String> known = <String>{
      for (final Category c in categories) c.id,
    };
    final String? safeValue = value != null && known.contains(value)
        ? value
        : null;

    return DropdownButtonFormField<String?>(
      value: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.folder_outlined),
      ),
      onChanged: enabled ? onChanged : null,
      items: <DropdownMenuItem<String?>>[
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'Auto (suggested)',
            style: TextStyle(color: t.textSecondary),
          ),
        ),
        for (final Category category in categories)
          DropdownMenuItem<String?>(
            value: category.id,
            child: Row(
              children: <Widget>[
                Icon(category.icon, size: 18, color: category.colorValue),
                SizedBox(width: t.spaceS),
                Flexible(
                  child: Text(category.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.pack,
    required this.busy,
    required this.enabled,
    required this.onAdd,
  });

  final StarterPack pack;
  final bool busy;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return SurfaceCard(
      level: 2,
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.symmetric(horizontal: t.spaceM, vertical: t.spaceM),
      onTap: enabled ? onAdd : null,
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: t.borderRadiusS,
            ),
            child: Icon(pack.icon, size: 20, color: t.accent),
          ),
          SizedBox(width: t.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(pack.name, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  pack.feeds.map((StarterFeed f) => f.title).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
          SizedBox(width: t.spaceS),
          if (busy)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            )
          else
            Icon(Icons.add_rounded, color: enabled ? t.accent : t.textTertiary),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.spaceM),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.12),
        borderRadius: t.borderRadiusS,
        border: Border.all(color: t.danger.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: t.danger),
          SizedBox(width: t.spaceS),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
