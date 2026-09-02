import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
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
  bool _showFullContent = false;
  String? _summary;
  bool _isLoadingSummary = false;
  late ArticleAnnotationProvider _annotationProvider;
  double _readingProgress = 0.0;
  late Article _article;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _scrollController.addListener(_onScroll);
    _annotationProvider = ArticleAnnotationProvider();

    ArticleAnnotationService().initializeTables();
    
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
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        final currentScroll = _scrollController.offset;
        setState(() {
          _readingProgress = (currentScroll / maxScroll).clamp(0.0, 1.0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _annotationProvider,
      child: Consumer2<SettingsProvider, ArticleAnnotationProvider>(
        builder: (context, settings, annotationProvider, child) {
          final theme = Theme.of(context);
          final liveArticle = context.read<ArticleProvider>().getArticleById(widget.article.id);
          if (liveArticle != null) _article = liveArticle;

          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight + 2),
              child: Column(
                children: [
                  FuturisticAppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          widget.article.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: widget.article.isStarred ? Colors.amber : null,
                        ),
                        onPressed: () => context.read<ArticleProvider>().toggleStarred(widget.article.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.auto_awesome_outlined),
                        onPressed: _generateSummary,
                        tooltip: 'Summarize',
                      ),
                      IconButton(
                        icon: const Icon(Icons.share_outlined),
                        onPressed: _shareArticle,
                      ),
                    ],
                  ),
                  LinearProgressIndicator(
                    value: _readingProgress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            body: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.article.imageUrl != null)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        widget.article.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.article.title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (widget.article.author != null) ...[
                              Text(
                                'By ${widget.article.author}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Text(
                              DateFormat('MMMM d, yyyy').format(widget.article.publishedDate),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        if (_summary != null) _buildSummarySection(theme),
                        if (_isLoadingSummary) const Center(child: CircularProgressIndicator()),
                        _buildMainContent(context, settings, annotationProvider),
                        const SizedBox(height: 48),
                        _buildReadOriginalButton(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: _buildBottomBar(theme),
          );
        },
      ),
    );
  }

  Widget _buildSummarySection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'AI SUMMARY',
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _summary!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, SettingsProvider settings, ArticleAnnotationProvider annotationProvider) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final article = articleProvider.getArticleById(widget.article.id) ?? _article;
        final displayContent = _showFullContent
            ? (article.fullContent ?? article.content)
            : article.content;

        return HighlightableText(
          text: _cleanContent(displayContent ?? ''),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: settings.fontSize,
            height: 1.6,
          ),
          highlights: annotationProvider.highlights,
          isEditMode: annotationProvider.isEditMode,
        );
      },
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.8),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  widget.article.isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                  color: widget.article.isSaved ? theme.colorScheme.primary : null,
                ),
                onPressed: () => context.read<ArticleProvider>().toggleSaved(widget.article.id),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Edit text',
                onPressed: _editArticleText,
              ),
              IconButton(
                icon: const Icon(Icons.text_fields_rounded),
                onPressed: _showSettingsDialog,
              ),
              IconButton(
                icon: const Icon(Icons.open_in_browser_rounded),
                onPressed: _launchOriginalArticle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOriginalButton(BuildContext context) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final isLoadingFull = articleProvider.isLoadingFullArticle(widget.article.id);
        final article = articleProvider.getArticleById(widget.article.id) ?? widget.article;
        final hasFullContent = article.fullContent != null && article.fullContent!.isNotEmpty;

        return Center(
          child: OutlinedButton.icon(
            onPressed: isLoadingFull ? null : () async {
              if (hasFullContent) {
                setState(() => _showFullContent = !_showFullContent);
              } else {
                final success = await articleProvider.loadFullArticle(widget.article.id);
                if (success) setState(() => _showFullContent = true);
              }
            },
            icon: Icon(_showFullContent ? Icons.description_rounded : Icons.article_rounded),
            label: Text(_showFullContent ? 'Show Summary' : (isLoadingFull ? 'Loading...' : 'Load Full Article')),
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Reading Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('Font Size'),
                Expanded(
                  child: Slider(
                    value: settings.fontSize,
                    min: 12,
                    max: 30,
                    divisions: 9,
                    onChanged: (value) => settings.setFontSize(value),
                  ),
                ),
                Text(settings.fontSize.toInt().toString()),
              ],
            ),
          ],
        ),
      ),
    );
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

  Future<void> _generateSummary() async {
    setState(() => _isLoadingSummary = true);
    try {
      final summary = await SummarizationService().summarizeArticle(_article);
      setState(() {
        _summary = summary;
        _isLoadingSummary = false;
      });
      context.read<ArticleProvider>().refreshArticle(widget.article.id);
    } catch (e) {
      setState(() => _isLoadingSummary = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  Future<void> _editArticleText() async {
    final editingFullContent = _showFullContent && _article.fullContent != null;
    final currentText = _cleanContent(
      (editingFullContent ? _article.fullContent : _article.content) ?? '',
    );

    final newText = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleTextEditorScreen(
          title: _article.title,
          initialText: currentText,
        ),
      ),
    );
    if (newText == null || newText == currentText) return;
    if (!mounted) return;

    final success = await context.read<ArticleProvider>().updateArticleContent(
          _article.id,
          newText,
          editFullContent: editingFullContent,
        );

    if (!mounted) return;
    if (success) {
      setState(() {
        _article = editingFullContent
            ? _article.copyWith(fullContent: newText)
            : _article.copyWith(content: newText);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Article text saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save changes')),
      );
    }
  }

  Future<void> _shareArticle() async {
    Share.share('${widget.article.title}\n\n${widget.article.url}');
  }

  Future<void> _launchOriginalArticle() async {
    final url = Uri.parse(widget.article.url);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    }
  }
}

/// Full-screen plain-text editor for article content. Pops with the edited
/// text on save, or null on cancel.
class ArticleTextEditorScreen extends StatefulWidget {
  final String title;
  final String initialText;

  const ArticleTextEditorScreen({
    super.key,
    required this.title,
    required this.initialText,
  });

  @override
  State<ArticleTextEditorScreen> createState() => _ArticleTextEditorScreenState();
}

class _ArticleTextEditorScreenState extends State<ArticleTextEditorScreen> {
  late final TextEditingController _controller;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(() {
      final changed = _controller.text != widget.initialText;
      if (changed != _hasChanges) {
        setState(() => _hasChanges = changed);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes to the article text.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Edit: ${widget.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton.icon(
              onPressed: _hasChanges
                  ? () => Navigator.pop(context, _controller.text)
                  : null,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Article text...',
            ),
          ),
        ),
      ),
    );
  }
}
