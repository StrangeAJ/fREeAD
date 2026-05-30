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

  @override
  void initState() {
    super.initState();
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
    final displayContent = _showFullContent ? (widget.article.fullContent ?? widget.article.content) : widget.article.content;

    return HighlightableText(
      text: _cleanContent(displayContent ?? ''),
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: settings.fontSize,
        height: 1.6,
      ),
      highlights: annotationProvider.highlights,
      isEditMode: annotationProvider.isEditMode,
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
        
        return Center(
          child: OutlinedButton.icon(
            onPressed: isLoadingFull ? null : () async {
              if (widget.article.fullContent != null) {
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
      final summary = await SummarizationService().summarizeArticle(widget.article);
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
