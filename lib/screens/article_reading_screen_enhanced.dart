import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/article_annotation_provider.dart';
import '../widgets/futuristic_buttons.dart';
import '../widgets/futuristic_widgets.dart';
import '../widgets/article_annotation_widgets.dart';
import '../widgets/highlightable_text.dart';
import '../services/summarization_service.dart';
import '../services/article_annotation_service.dart';

class ArticleReadingScreen extends StatefulWidget {
  final Article article;

  const ArticleReadingScreen({
    super.key,
    required this.article,
  });

  @override
  State<ArticleReadingScreen> createState() => _ArticleReadingScreenState();
}

class _ArticleReadingScreenState extends State<ArticleReadingScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  bool _showFullContent = false;
  String? _summary;
  bool _isLoadingSummary = false;
  bool _showNotesPanel = false;
  late ArticleAnnotationProvider _annotationProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _annotationProvider = ArticleAnnotationProvider();

    // Initialize annotation service
    ArticleAnnotationService().initializeTables();

    // Mark article as read and load annotations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ArticleProvider>().markAsRead(widget.article.id);
      _annotationProvider.loadAnnotations(widget.article.id);
      _loadExistingSummary();
    });
  }

  void _loadExistingSummary() {
    if (widget.article.summary != null && widget.article.summary!.isNotEmpty) {
      setState(() {
        _summary = widget.article.summary;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _annotationProvider.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.offset > 100 && !_isScrolled) {
      setState(() {
        _isScrolled = true;
      });
    } else if (_scrollController.offset <= 100 && _isScrolled) {
      setState(() {
        _isScrolled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _annotationProvider,
      child: Consumer2<SettingsProvider, ArticleAnnotationProvider>(
        builder: (context, settings, annotationProvider, child) {
          return Scaffold(
            backgroundColor: _getBackgroundColor(context, settings),
            body: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    _buildSliverAppBar(context, settings, annotationProvider),
                    SliverToBoxAdapter(
                      child: _buildArticleContent(context, settings, annotationProvider),
                    ),
                  ],
                ),
                // Highlight color picker overlay
                if (annotationProvider.selectedText != null)
                  Positioned(
                    bottom: 100,
                    left: 16,
                    right: 16,
                    child: HighlightColorPicker(
                      articleId: widget.article.id,
                      onHighlightAdded: () {
                        annotationProvider.loadAnnotations(widget.article.id);
                      },
                    ),
                  ),
                // Notes panel
                if (_showNotesPanel)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: ArticleNotesPanel(articleId: widget.article.id),
                  ),
              ],
            ),
            floatingActionButton: _buildFloatingActionButtons(context),
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, SettingsProvider settings, ArticleAnnotationProvider annotationProvider) {
    return SliverAppBar(
      expandedHeight: widget.article.imageUrl != null ? 200.0 : 120.0,
      floating: false,
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      actions: [
        Consumer<ArticleProvider>(
          builder: (context, articleProvider, child) {
            return IconButton(
              icon: Icon(
                widget.article.isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: widget.article.isSaved ? Colors.orange : null,
              ),
              onPressed: () {
                articleProvider.toggleSaved(widget.article.id);
              },
            );
          },
        ),
        Consumer<ArticleProvider>(
          builder: (context, articleProvider, child) {
            return IconButton(
              icon: Icon(
                widget.article.isStarred ? Icons.star : Icons.star_border,
                color: widget.article.isStarred ? Colors.amber : null,
              ),
              onPressed: () {
                articleProvider.toggleStarred(widget.article.id);
              },
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.auto_awesome),
          tooltip: 'Summarize',
          onPressed: _generateSummary,
        ),
        // Edit/Annotation toggle button
        IconButton(
          icon: Icon(
            annotationProvider.isEditMode ? Icons.edit_off : Icons.edit,
            color: annotationProvider.isEditMode ? Colors.orange : null,
          ),
          onPressed: () {
            annotationProvider.toggleEditMode();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  annotationProvider.isEditMode
                    ? 'Edit mode enabled - Tap text to highlight'
                    : 'Edit mode disabled',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          tooltip: annotationProvider.isEditMode ? 'Exit Edit Mode' : 'Enter Edit Mode',
        ),
        // Notes panel toggle
        IconButton(
          icon: Badge(
            isLabelVisible: annotationProvider.notes.isNotEmpty || annotationProvider.highlights.isNotEmpty,
            label: Text('${annotationProvider.notes.length + annotationProvider.highlights.length}'),
            child: const Icon(Icons.notes),
          ),
          onPressed: () {
            setState(() {
              _showNotesPanel = !_showNotesPanel;
            });
          },
          tooltip: 'View Notes & Highlights',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'share':
                await _shareArticle();
                break;
              case 'open_browser':
                await _openInBrowser();
                break;
              case 'copy_link':
                await _copyLink();
                break;
              case 'clear_annotations':
                _showClearAnnotationsDialog(context, annotationProvider);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'share', child: Text('Share Article')),
            const PopupMenuItem(value: 'open_browser', child: Text('Open in Browser')),
            const PopupMenuItem(value: 'copy_link', child: Text('Copy Link')),
            const PopupMenuItem(value: 'clear_annotations', child: Text('Clear All Notes & Highlights')),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: widget.article.imageUrl != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.article.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: const Icon(Icons.article, size: 48),
                      );
                    },
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Icon(Icons.article, size: 48),
              ),
      ),
    );
  }

  Widget _buildArticleContent(BuildContext context, SettingsProvider settings, ArticleAnnotationProvider annotationProvider) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with highlighting support
          HighlightableText(
            text: widget.article.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: settings.fontSize * 1.2,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            highlights: annotationProvider.highlights.where((h) =>
              widget.article.title.contains(h.selectedText)).toList(),
            isEditMode: annotationProvider.isEditMode,
          ),
          const SizedBox(height: 16),

          // Article metadata
          _buildMetadata(context, settings),

          // Summary section
          if (_isLoadingSummary || _summary != null)
            _buildSummary(context, settings),

          const SizedBox(height: 24),

          // Article content with highlighting
          _buildContent(context, settings, annotationProvider),

          const SizedBox(height: 32),

          // Read original button
          _buildReadOriginalButton(context),

          const SizedBox(height: 100), // Extra space for FAB
        ],
      ),
    );
  }

  Widget _buildMetadata(BuildContext context, SettingsProvider settings) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.article.author != null) ...[
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  widget.article.author!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: settings.fontSize * 0.9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                widget.article.timeAgo,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: settings.fontSize * 0.9,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, SettingsProvider settings) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingSummary)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Generating summary...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            )
          else if (_summary != null)
            SelectableText(
              _summary!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: settings.fontSize,
                height: 1.6,
                color: _getTextColor(context, settings),
              ),
            )
          else
            Text(
              'No summary available. Tap the summarize button to generate one.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SettingsProvider settings, ArticleAnnotationProvider annotationProvider) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final article = articleProvider.getArticleById(widget.article.id) ?? widget.article;
        final isLoadingFull = articleProvider.isLoadingFullArticle(widget.article.id);

        String displayContent;
        if (_showFullContent && article.fullContent != null && article.fullContent!.isNotEmpty) {
          displayContent = article.fullContent!;
        } else {
          displayContent = article.content ?? article.description;
        }

        if (displayContent.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.article_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'No content available',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Read Full Article" to load the complete article',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoadingFull)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text('Loading full article...', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),

            // Use HighlightableText for content with highlighting support
            if (_showFullContent && article.fullContent != null && article.fullContent!.isNotEmpty)
              Html(
                data: article.fullContent!,
                style: {
                  "body": Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(1.6),
                    color: _getTextColor(context, settings),
                  ),
                  "p": Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(1.6),
                    margin: Margins.only(bottom: 12),
                  ),
                },
                onLinkTap: (url, _, __) {
                  if (url != null) {
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                },
              )
            else
              HighlightableText(
                text: _cleanContent(displayContent),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: settings.fontSize,
                  height: 1.6,
                  color: _getTextColor(context, settings),
                ),
                highlights: annotationProvider.highlights,
                isEditMode: annotationProvider.isEditMode,
              ),
          ],
        );
      },
    );
  }

  Widget _buildReadOriginalButton(BuildContext context) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final article = articleProvider.getArticleById(widget.article.id) ?? widget.article;
        final isLoadingFull = articleProvider.isLoadingFullArticle(widget.article.id);
        final hasFullContent = article.fullContent != null && article.fullContent!.isNotEmpty;

        return Center(
          child: Column(
            children: [
              if (hasFullContent) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FuturisticGlowButton(
                      onPressed: isLoadingFull ? null : () {
                        setState(() {
                          _showFullContent = !_showFullContent;
                        });
                      },
                      icon: _showFullContent ? Icons.description_rounded : Icons.article_rounded,
                      label: _showFullContent ? 'Show Original' : 'Show Full Article',
                      isToggled: _showFullContent,
                      showGlow: true,
                      glowRadius: 25,
                      glowSpread: 3,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text(_showFullContent ? 'Show Original' : 'Show Full Article'),
                    ),
                    const SizedBox(width: 12),
                    FuturisticSecondaryButton(
                      onPressed: () => _launchOriginalArticle(),
                      icon: Icons.web_rounded,
                      label: 'Open in Browser',
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: const Text('Open in Browser'),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FuturisticGlowButton(
                      onPressed: isLoadingFull ? null : () async {
                        final success = await articleProvider.loadFullArticle(widget.article.id);
                        if (success) {
                          setState(() {
                            _showFullContent = true;
                          });
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(articleProvider.error ?? 'Failed to load full article'),
                                action: SnackBarAction(
                                  label: 'Try Browser',
                                  onPressed: _launchOriginalArticle,
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: Icons.article_rounded,
                      label: isLoadingFull ? 'Loading...' : 'Read Full Article',
                      isLoading: isLoadingFull,
                      showGlow: true,
                      glowRadius: 30,
                      glowSpread: 4,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(isLoadingFull ? 'Loading...' : 'Read Full Article'),
                    ),
                    const SizedBox(width: 12),
                    FuturisticSecondaryButton(
                      onPressed: () => _launchOriginalArticle(),
                      icon: Icons.web_rounded,
                      label: 'Open in Browser',
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: const Text('Open in Browser'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingActionButtons(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FuturisticFAB(
          onPressed: () {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          },
          icon: Icons.keyboard_arrow_up_rounded,
          tooltip: 'Scroll to top',
          showPulse: false,
        ),
        const SizedBox(height: 8),
        FuturisticFAB(
          onPressed: () => _shareArticle(),
          icon: Icons.share_rounded,
          tooltip: 'Share article',
          showPulse: true,
        ),
      ],
    );
  }

  // Helper methods
  Color _getBackgroundColor(BuildContext context, SettingsProvider settings) {
    return Theme.of(context).colorScheme.surface;
  }

  Color _getTextColor(BuildContext context, SettingsProvider settings) {
    return Theme.of(context).colorScheme.onSurface;
  }

  String _cleanContent(String content) {
    return content
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#39;'), "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Action methods
  Future<void> _generateSummary() async {
    setState(() {
      _isLoadingSummary = true;
    });

    try {
      final summary = await SummarizationService().summarizeArticle(widget.article);
      final settings = context.read<SettingsProvider>();
      final autoSave = settings.autoSaveSummaries;

      setState(() {
        _summary = summary;
        _isLoadingSummary = false;
      });

      final articleProvider = context.read<ArticleProvider>();
      await articleProvider.refreshArticle(widget.article.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(autoSave ? 'Summary Saved' : 'Summary generated'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoadingSummary = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _shareArticle() async {
    final shareText = '${widget.article.title}\n\n${widget.article.url}';
    Share.share(shareText, subject: widget.article.title);
  }

  Future<void> _openInBrowser() async {
    _launchOriginalArticle();
  }

  Future<void> _copyLink() async {
    Clipboard.setData(ClipboardData(text: widget.article.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  Future<void> _launchOriginalArticle() async {
    try {
      final Uri url = Uri.parse(widget.article.url);
      if (url.scheme.isEmpty) {
        throw Exception('Invalid URL: ${widget.article.url}');
      }

      bool launched = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      if (!launched) {
        launched = await launchUrl(url, mode: LaunchMode.inAppWebView);
      }

      if (!launched) {
        throw Exception('Could not open article in app');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening article: ${e.toString()}'),
            action: SnackBarAction(
              label: 'Copy URL',
              onPressed: _copyLink,
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showClearAnnotationsDialog(BuildContext context, ArticleAnnotationProvider annotationProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear Annotations'),
          content: const Text('Are you sure you want to clear all notes and highlights for this article?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await annotationProvider.clearAllAnnotations(widget.article.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notes and highlights cleared')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error clearing annotations: $e')),
                  );
                }
              },
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }
}
