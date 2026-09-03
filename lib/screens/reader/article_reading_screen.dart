import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_settings.dart';
import '../../models/article.dart';
import '../../models/article_highlight.dart';
import '../../models/rss_feed.dart';
import '../../providers/ai_chat_provider.dart';
import '../../providers/article_annotation_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai/ai_service.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../utils/app_logger.dart';
import '../../utils/text_utils.dart';
import '../../widgets/ui/ui.dart';
import 'annotations_sheet.dart';
import 'ask_ai_sheet.dart';
import 'reader_content_view.dart';
import 'reader_settings_sheet.dart';
import 'summary_card.dart';

/// The reading screen.
///
/// Layout notes (this is where the v2 "title hidden behind the toolbar" bug
/// lived): the scaffold deliberately extends the body behind the glass app bar,
/// so **every** sliver below the bar has to pay for that itself. With a hero
/// image the image is the thing that sits under the bar, and its height is
/// clamped to at least `statusBar + kToolbarHeight + progressBar + spaceXl`.
/// Without one, a spacer sliver of exactly that height opens the scroll view.
/// Either way the title starts below the toolbar.
class ArticleReadingScreen extends StatefulWidget {
  const ArticleReadingScreen({super.key, required this.article});

  final Article article;

  @override
  State<ArticleReadingScreen> createState() => _ArticleReadingScreenState();
}

class _ArticleReadingScreenState extends State<ArticleReadingScreen> {
  static const double _progressBarHeight = 2;
  static const double _bottomGutter = 120;

  final ScrollController _scroll = ScrollController();
  late final ArticleAnnotationProvider _annotations =
      ArticleAnnotationProvider();

  AiService? _localAi;
  AiChatProvider? _chat;

  double _progress = 0;
  bool _showFullContent = true;
  bool _showSummary = false;
  bool _autoLoadAttempted = false;
  String _projection = '';
  String? _selectedText;

  String get _articleId => widget.article.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final SettingsProvider settings = context.read<SettingsProvider>();
      if (settings.markReadOnOpen) {
        context.read<ArticleProvider>().markAsRead(_articleId);
      }
      _annotations.loadAnnotations(_articleId);
      _maybeAutoLoadFullArticle();
      _restoreScrollPosition();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _chat?.dispose();
    _annotations.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scroll position
  // ---------------------------------------------------------------------------

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final double value = (_scroll.offset / max).clamp(0.0, 1.0);
    if ((value - _progress).abs() < 0.004) return;
    setState(() => _progress = value);
    context.read<ArticleProvider>().saveScrollProgress(_articleId, value);
  }

  /// Jumps back to where the reader stopped last time.
  ///
  /// The body renders asynchronously, so `maxScrollExtent` is still 0 on the
  /// first frame; retry a handful of times before giving up. Nothing is
  /// scheduled at all when there is no stored position, which keeps widget
  /// tests free of pending timers.
  Future<void> _restoreScrollPosition() async {
    if (!mounted) return;
    if (!context.read<SettingsProvider>().rememberScrollPosition) return;

    final double target = widget.article.scrollProgress;
    if (target <= 0.01 || target >= 0.999) return;

    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || !_scroll.hasClients) return;
      final double max = _scroll.position.maxScrollExtent;
      if (max > 0) {
        _scroll.jumpTo(max * target);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  // ---------------------------------------------------------------------------
  // AI plumbing
  // ---------------------------------------------------------------------------

  /// `main.dart` does not provide `Provider<AiService>` yet (Phase 3 will hoist
  /// it), so fall back to a locally owned instance built from the settings.
  AiService get _ai {
    try {
      return Provider.of<AiService>(context, listen: false);
    } on ProviderNotFoundException {
      return _localAi ??= AiService(
        configSource: SettingsAiConfigSource(context.read<SettingsProvider>()),
      );
    }
  }

  /// The conversation for this reader session.
  ///
  /// Rebuilt when the full body arrives while the chat is still empty, so the
  /// model is never left answering from the RSS excerpt after the real article
  /// has been extracted.
  AiChatProvider _chatProvider(Article article) {
    final AiChatProvider? existing = _chat;
    if (existing != null) {
      final bool stale =
          existing.messages.isEmpty &&
          existing.article.hasFullContent != article.hasFullContent;
      if (!stale) return existing;
      existing.dispose();
    }
    return _chat = AiChatProvider(article: article, ai: _ai);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _maybeAutoLoadFullArticle() async {
    if (_autoLoadAttempted || !mounted) return;
    final SettingsProvider settings = context.read<SettingsProvider>();
    if (!settings.autoLoadFullArticle) return;

    final ArticleProvider articles = context.read<ArticleProvider>();
    final Article article =
        articles.getArticleById(_articleId) ?? widget.article;
    if (article.hasFullContent || article.isRssContentSubstantial) return;

    _autoLoadAttempted = true;
    await _loadFullArticle(engine: settings.extractionEngine, silent: true);
  }

  Future<void> _loadFullArticle({
    ExtractionEngine? engine,
    bool force = false,
    bool silent = false,
  }) async {
    if (!mounted) return;
    final ArticleProvider articles = context.read<ArticleProvider>();
    final ExtractionEngine chosen =
        engine ?? context.read<SettingsProvider>().extractionEngine;

    final bool ok = await articles.loadFullArticle(
      _articleId,
      engine: chosen,
      force: force,
    );
    if (!mounted) return;

    if (ok) {
      setState(() => _showFullContent = true);
      return;
    }

    final String message =
        articles.lastExtractionError(_articleId) ??
        'Could not load the full article.';
    if (!silent) {
      AppSnackBar.show(
        context,
        message,
        kind: AppSnackKind.error,
        action: 'Open in browser',
        onAction: _openInBrowser,
      );
    }
  }

  Future<void> _openInBrowser() async {
    final Uri? uri = Uri.tryParse(widget.article.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLog.w('Could not open ${widget.article.url}', e);
      if (mounted) {
        AppSnackBar.error(context, 'No app can open this link.');
      }
    }
  }

  Future<void> _share(Article article) async {
    try {
      await Share.share('${article.title}\n\n${article.url}');
    } catch (e) {
      AppLog.w('Share failed', e);
    }
  }

  Future<void> _copyLink(Article article) async {
    await Clipboard.setData(ClipboardData(text: article.url));
    if (!mounted) return;
    AppSnackBar.success(context, 'Link copied');
  }

  Future<void> _openAskAi(Article article, {String? prefill}) async {
    await showAskAiSheet(
      context,
      chat: _chatProvider(article),
      initialPrompt: prefill,
    );
  }

  Future<void> _openOverflow(Article article) async {
    final String? choice = await showAppMenuSheet<String>(
      context,
      title: article.title,
      options: <AppMenuOption<String>>[
        const AppMenuOption<String>(
          value: 'browser',
          label: 'Open in browser',
          icon: Icons.open_in_new_rounded,
        ),
        const AppMenuOption<String>(
          value: 'copy',
          label: 'Copy link',
          icon: Icons.link_rounded,
        ),
        const AppMenuOption<String>(
          value: 'notes',
          label: 'Notes & highlights',
          icon: Icons.edit_note_rounded,
        ),
        const AppMenuOption<String>(
          value: 'edit',
          label: 'Edit text',
          icon: Icons.text_snippet_outlined,
        ),
        const AppMenuOption<String>(
          value: 'reload',
          label: 'Reload full article',
          icon: Icons.refresh_rounded,
        ),
        AppMenuOption<String>(
          value: 'clear',
          label: 'Clear cached article',
          icon: Icons.layers_clear_outlined,
          enabled: article.hasFullContent,
        ),
        const AppMenuOption<String>(
          value: 'clear_notes',
          label: 'Clear notes & highlights',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'browser':
        await _openInBrowser();
      case 'copy':
        await _copyLink(article);
      case 'notes':
        await showAnnotationsSheet(
          context,
          articleId: _articleId,
          annotations: _annotations,
        );
      case 'edit':
        await _editText(article);
      case 'reload':
        await _pickEngineAndReload();
      case 'clear':
        await context.read<ArticleProvider>().clearFullContent(_articleId);
        if (mounted) setState(() => _showFullContent = true);
      case 'clear_notes':
        final bool confirmed = await showAppConfirm(
          context,
          'Clear notes & highlights?',
          'Every highlight and note on this article is deleted.',
          confirmLabel: 'Clear',
          destructive: true,
        );
        if (confirmed) await _annotations.clearAllAnnotations(_articleId);
    }
  }

  Future<void> _pickEngineAndReload() async {
    final ExtractionEngine? engine = await showAppMenuSheet<ExtractionEngine>(
      context,
      title: 'Reload with',
      options: <AppMenuOption<ExtractionEngine>>[
        for (final ExtractionEngine value in ExtractionEngine.values)
          AppMenuOption<ExtractionEngine>(
            value: value,
            label: value.label,
            subtitle: value.description,
            icon: switch (value) {
              ExtractionEngine.auto => Icons.auto_mode_rounded,
              ExtractionEngine.fast => Icons.bolt_rounded,
              ExtractionEngine.browser => Icons.travel_explore_rounded,
            },
          ),
      ],
    );
    if (engine == null || !mounted) return;
    await _loadFullArticle(engine: engine, force: true);
  }

  Future<void> _editText(Article article) async {
    final String current = ReaderContentView.plainTextFor(
      article,
      showFullContent: _showFullContent,
    );

    final String? edited = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) =>
            ArticleTextEditorScreen(title: article.title, initialText: current),
      ),
    );
    if (edited == null || edited == current || !mounted) return;

    final bool editingFull = _showFullContent && article.hasFullContent;
    final bool ok = await context.read<ArticleProvider>().updateArticleContent(
      _articleId,
      _paragraphsToHtml(edited),
      editFullContent: editingFull,
    );
    if (!mounted) return;
    if (ok) {
      AppSnackBar.success(context, 'Article text saved');
    } else {
      AppSnackBar.error(context, 'Could not save the changes');
    }
  }

  /// Turns edited plain text back into simple paragraph HTML so the reader
  /// keeps rendering it as HTML instead of one wall of text.
  static String _paragraphsToHtml(String text) {
    final List<String> paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((String p) => p.trim())
        .where((String p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return '';
    String escape(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    return paragraphs.map((String p) => '<p>${escape(p)}</p>').join();
  }

  // ---------------------------------------------------------------------------
  // Selection toolbar
  // ---------------------------------------------------------------------------

  Future<void> _highlightSelection() async {
    final String? text = _selectedText;
    if (text == null || text.trim().isEmpty) return;
    _annotations.setSelection(text);

    final String? color = await showHighlightColorSheet(context);
    if (color == null) return;
    await _annotations.addHighlight(_articleId, color);
  }

  Future<void> _noteSelection() async {
    final String? text = _selectedText;
    if (text != null && text.trim().isNotEmpty) {
      _annotations.setSelection(text);
    }
    final String? note = await showNoteEditor(context, title: 'New note');
    if (note == null || note.trim().isEmpty) return;
    await _annotations.addNote(_articleId, note);
  }

  Future<void> _askAboutSelection(Article article) async {
    final String text = (_selectedText ?? '').trim();
    final String prefill = text.isEmpty
        ? ''
        : 'About this passage: "${truncate(text, 400)}"\n';
    await _openAskAi(article, prefill: prefill);
  }

  Widget _selectionToolbar(
    BuildContext context,
    SelectableRegionState state,
    Article article,
  ) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          label: 'Highlight',
          onPressed: () {
            state.hideToolbar();
            _highlightSelection();
          },
        ),
        ContextMenuButtonItem(
          label: 'Note',
          onPressed: () {
            state.hideToolbar();
            _noteSelection();
          },
        ),
        ContextMenuButtonItem(
          label: 'Ask AI',
          onPressed: () {
            state.hideToolbar();
            _askAboutSelection(article);
          },
        ),
        ContextMenuButtonItem(
          label: 'Copy',
          onPressed: () {
            state.hideToolbar();
            final String text = (_selectedText ?? '').trim();
            if (text.isEmpty) return;
            Clipboard.setData(ClipboardData(text: text));
          },
        ),
        ContextMenuButtonItem(
          label: 'Share',
          onPressed: () {
            state.hideToolbar();
            final String text = (_selectedText ?? '').trim();
            if (text.isEmpty) return;
            Share.share('$text\n\n${article.url}');
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ArticleProvider articles = context.watch<ArticleProvider>();
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final Article article =
        articles.getArticleById(_articleId) ?? widget.article;

    // Keep the annotation offsets aligned with whatever body is on screen.
    final String projection = ReaderContentView.plainTextFor(
      article,
      showFullContent: _showFullContent,
    );
    if (projection != _projection) {
      _projection = projection;
      _annotations.setArticleText(projection);
    }

    final EdgeInsets viewPadding = MediaQuery.paddingOf(context);
    final double contentTop =
        viewPadding.top + kToolbarHeight + _progressBarHeight;
    final double width = MediaQuery.sizeOf(context).width;

    final String? heroUrl = settings.showImages ? article.imageUrl : null;
    final bool hasHero = heroUrl != null && heroUrl.trim().isNotEmpty;

    return AppScaffold(
      appBar: GlassAppBar(
        titleWidget: _appBarTitle(article),
        bottom: ReadingProgressBar(
          progress: _progress,
          height: _progressBarHeight,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: article.isStarred ? 'Unstar' : 'Star',
            onPressed: () => articles.toggleStarred(_articleId),
            icon: Icon(
              article.isStarred
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: article.isStarred ? t.warning : null,
            ),
          ),
          IconButton(
            tooltip: article.isSaved ? 'Remove from saved' : 'Save',
            onPressed: () => articles.toggleSaved(_articleId),
            icon: Icon(
              article.isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              color: article.isSaved ? t.accent : null,
            ),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: () => _share(article),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: () => _openOverflow(article),
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      bottomBar: _bottomBar(t, articles, article),
      body: SelectionArea(
        onSelectionChanged: (SelectedContent? content) =>
            _selectedText = content?.plainText,
        contextMenuBuilder:
            (BuildContext context, SelectableRegionState state) =>
                _selectionToolbar(context, state, article),
        child: CustomScrollView(
          controller: _scroll,
          slivers: <Widget>[
            // --- top spacing / hero ------------------------------------
            if (hasHero)
              SliverToBoxAdapter(
                child: _HeroImage(
                  articleId: article.id,
                  url: heroUrl,
                  // Never shorter than the app bar: the title must not end
                  // up underneath the toolbar on narrow screens.
                  height: math.max(width * 9 / 16, contentTop + t.spaceXl),
                ),
              )
            else
              SliverToBoxAdapter(
                child: SizedBox(height: contentTop + t.spaceXl),
              ),

            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: t.spaceXl),
              sliver: SliverList.list(
                children: <Widget>[
                  if (hasHero) SizedBox(height: t.spaceXl),
                  _title(article),
                  SizedBox(height: t.spaceM),
                  _meta(t, article),
                  SizedBox(height: t.spaceL),
                  _stateChips(t, articles, article),
                  if (_showSummary) ...<Widget>[
                    SizedBox(height: t.spaceL),
                    SummaryCard(
                      key: ValueKey<String>('summary-${article.id}'),
                      article: article,
                      ai: _ai,
                      onClose: () => setState(() => _showSummary = false),
                    ),
                  ],
                  SizedBox(height: t.space2xl),
                  _content(articles, settings, article, heroUrl),
                  SizedBox(height: t.space3xl),
                  _readOriginal(t),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SizedBox(height: _bottomGutter + viewPadding.bottom),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appBarTitle(Article article) {
    final String label = article.siteName?.trim().isNotEmpty == true
        ? article.siteName!.trim()
        : (hostOf(article.url) ?? '');
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }

  Widget _title(Article article) {
    final String rss = article.title.trim();
    final String title = rss.isNotEmpty
        ? rss
        : (article.extractedTitle?.trim() ?? '');
    return Text(
      title,
      style: AppTypography.readingHeading(1).copyWith(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: context.tokens.textPrimary,
      ),
    );
  }

  Widget _meta(AppTokens t, Article article) {
    final TextTheme text = Theme.of(context).textTheme;
    final RSSFeed? feed = _feedFor(article);
    final String source =
        feed?.title ?? article.siteName ?? hostOf(article.url) ?? 'Unknown';

    final List<String> bits = <String>[
      if (article.author != null && article.author!.trim().isNotEmpty)
        article.author!.trim(),
      relativeTime(article.publishedDate),
      '${article.readingMinutes} min read',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        FeedAvatar(
          title: source,
          feedId: article.feedId,
          imageUrl: feed?.iconUrl ?? faviconUrlFor(article.url),
          size: 28,
        ),
        SizedBox(width: t.spaceM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(color: t.textSecondary),
              ),
              Text(
                bits.join('  -  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: t.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  RSSFeed? _feedFor(Article article) {
    try {
      return Provider.of<FeedProvider>(
        context,
        listen: false,
      ).getFeedById(article.feedId);
    } on ProviderNotFoundException {
      return null;
    } catch (e) {
      return null;
    }
  }

  Widget _stateChips(AppTokens t, ArticleProvider articles, Article article) {
    final bool loading = articles.isLoadingFullArticle(_articleId);
    final String? error = articles.lastExtractionError(_articleId);

    final Widget stateChip;
    if (loading) {
      stateChip = PillChip(
        label: 'Loading full article...',
        icon: Icons.downloading_rounded,
        selected: true,
        trailing: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent),
          ),
        ),
      );
    } else if (article.hasFullContent) {
      stateChip = PillChip(
        label: _showFullContent ? 'Full article' : 'RSS excerpt',
        icon: _showFullContent
            ? Icons.article_rounded
            : Icons.short_text_rounded,
        selected: _showFullContent,
        onTap: () => setState(() => _showFullContent = !_showFullContent),
      );
    } else if (error != null) {
      stateChip = PillChip(
        label: 'Extraction failed - retry',
        icon: Icons.error_outline_rounded,
        color: t.danger,
        selected: true,
        onTap: () => _loadFullArticle(force: true),
      );
    } else {
      stateChip = PillChip(
        label: 'RSS excerpt',
        icon: Icons.download_rounded,
        onTap: () => _loadFullArticle(),
      );
    }

    return Wrap(
      spacing: t.spaceS,
      runSpacing: t.spaceS,
      children: <Widget>[
        stateChip,
        PillChip(
          label: 'Summary',
          icon: Icons.summarize_outlined,
          selected: _showSummary,
          onTap: () => setState(() => _showSummary = !_showSummary),
        ),
        PillChip(
          label: 'Ask AI',
          icon: Icons.auto_awesome_rounded,
          onTap: () => _openAskAi(article),
        ),
      ],
    );
  }

  Widget _content(
    ArticleProvider articles,
    SettingsProvider settings,
    Article article,
    String? heroUrl,
  ) {
    final AppTokens t = context.tokens;
    final bool loading = articles.isLoadingFullArticle(_articleId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The annotation provider is owned by this state object rather than
        // the widget tree, so listen to it directly.
        ListenableBuilder(
          listenable: _annotations,
          builder: (BuildContext context, Widget? _) => ReaderContentView(
            article: article,
            readingFont: settings.readingFont,
            fontSize: settings.fontSize,
            lineHeight: settings.lineHeight,
            showImages: settings.showImages,
            showFullContent: _showFullContent,
            highlights: _annotations.highlights,
            heroImageUrl: heroUrl,
            onHighlightTap: (String id) {
              final ArticleHighlight? highlight = _annotations.highlightById(
                id,
              );
              if (highlight == null) return;
              showHighlightOptionsSheet(
                context,
                highlight: highlight,
                annotations: _annotations,
              );
            },
          ),
        ),
        if (loading) ...<Widget>[
          SizedBox(height: t.spaceXl),
          Row(
            children: <Widget>[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: t.accent,
                ),
              ),
              SizedBox(width: t.spaceM),
              Text(
                'Loading full article...',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: t.textTertiary),
              ),
            ],
          ),
          SizedBox(height: t.spaceL),
          SkeletonGroup(child: Skeleton.lines(6)),
        ],
      ],
    );
  }

  Widget _readOriginal(AppTokens t) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: _openInBrowser,
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('Read the original'),
      ),
    );
  }

  Widget _bottomBar(AppTokens t, ArticleProvider articles, Article article) {
    return GlassBottomBar(
      padding: EdgeInsets.symmetric(horizontal: t.spaceM, vertical: t.spaceS),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: article.isSaved ? 'Saved' : 'Save',
            onPressed: () => articles.toggleSaved(_articleId),
            icon: Icon(
              article.isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              color: article.isSaved ? t.accent : null,
            ),
          ),
          IconButton(
            tooltip: article.isStarred ? 'Starred' : 'Star',
            onPressed: () => articles.toggleStarred(_articleId),
            icon: Icon(
              article.isStarred
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: article.isStarred ? t.warning : null,
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.spaceS),
              child: GlowButton(
                expand: true,
                label: 'Ask AI',
                icon: Icons.auto_awesome_rounded,
                onPressed: () => _openAskAi(article),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Text settings',
            onPressed: () => showReaderSettingsSheet(context),
            icon: const Icon(Icons.text_fields_rounded),
          ),
          IconButton(
            tooltip: 'Open in browser',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
    );
  }
}

/// The 16:9 lead image, fading into the page background.
class _HeroImage extends StatelessWidget {
  const _HeroImage({
    required this.articleId,
    required this.url,
    required this.height,
  });

  final String articleId;
  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Hero(
            tag: 'article-image-$articleId',
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              fadeInDuration: AppTokens.motionFast,
              placeholder: (BuildContext context, String _) =>
                  ColoredBox(color: t.surface2),
              errorWidget: (BuildContext context, String _, Object __) =>
                  ColoredBox(color: t.surface2),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    t.bg.withValues(alpha: 0.55),
                    t.bg.withValues(alpha: 0.0),
                    t.bg.withValues(alpha: 0.85),
                    t.bg,
                  ],
                  stops: const <double>[0, 0.35, 0.88, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen plain-text editor for article content. Pops with the edited
/// text on save, or null on cancel.
class ArticleTextEditorScreen extends StatefulWidget {
  const ArticleTextEditorScreen({
    super.key,
    required this.title,
    required this.initialText,
  });

  final String title;
  final String initialText;

  @override
  State<ArticleTextEditorScreen> createState() =>
      _ArticleTextEditorScreenState();
}

class _ArticleTextEditorScreenState extends State<ArticleTextEditorScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final bool changed = _controller.text != widget.initialText;
      if (changed != _hasChanges) setState(() => _hasChanges = changed);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return PopScope<Object?>(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool discard = await showAppConfirm(
          context,
          'Discard changes?',
          'You have unsaved changes to the article text.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep editing',
          destructive: true,
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        extendBodyBehindAppBar: false,
        appBar: GlassAppBar(
          opaque: true,
          titleWidget: Text(
            'Edit: ${widget.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: _hasChanges
                  ? () => Navigator.of(context).pop(_controller.text)
                  : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.all(t.spaceL),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(hintText: 'Article text...'),
          ),
        ),
      ),
    );
  }
}
