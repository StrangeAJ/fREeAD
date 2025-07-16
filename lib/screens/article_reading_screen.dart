import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/futuristic_buttons.dart';
import '../widgets/futuristic_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Mark article as read when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ArticleProvider>().markAsRead(widget.article.id);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Scaffold(
          backgroundColor: _getBackgroundColor(context, settings),
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildSliverAppBar(context, settings),
              SliverToBoxAdapter(
                child: _buildArticleContent(context, settings),
              ),
            ],
          ),
          floatingActionButton: _buildFloatingActionButtons(context),
        );
      },
    );
  }

  Widget _buildSliverAppBar(BuildContext context, SettingsProvider settings) {
    return SliverAppBar(
      expandedHeight: widget.article.imageUrl != null ? 200.0 : 120.0,
      floating: false,
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
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
                        child: const Icon(
                          Icons.article,
                          size: 48,
                        ),
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
                child: const Icon(
                  Icons.article,
                  size: 48,
                ),
              ),
      ),
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
        PopupMenuButton<String>(
          onSelected: _handleMenuSelection,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share),
                  SizedBox(width: 8),
                  Text('Share'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'copy_link',
              child: Row(
                children: [
                  Icon(Icons.link),
                  SizedBox(width: 8),
                  Text('Copy Link'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'open_browser',
              child: Row(
                children: [
                  Icon(Icons.web),
                  SizedBox(width: 8),
                  Text('Open in App Browser'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildArticleContent(BuildContext context, SettingsProvider settings) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            widget.article.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: settings.fontSize * 1.2,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          
          // Article metadata
          _buildMetadata(context, settings),
          
          const SizedBox(height: 24),
          
          // Article content
          _buildContent(context, settings),
          
          const SizedBox(height: 32),
          
          // Read original link
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
                Icon(
                  Icons.person,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
              Icon(
                Icons.schedule,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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

  Widget _buildContent(BuildContext context, SettingsProvider settings) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final article = articleProvider.getArticleById(widget.article.id) ?? widget.article;
        final isLoadingFull = articleProvider.isLoadingFullArticle(widget.article.id);
        
        // Determine which content to show
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
                Icon(
                  Icons.article_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
            // Loading indicator for full article
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
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading full article...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Content type indicator
            if (_showFullContent && article.fullContent != null && article.fullContent!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.article,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Full Article',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Article content
            if (_showFullContent && article.fullContent != null && article.fullContent!.isNotEmpty)
              Html(
                data: article.fullContent!,
                style: {
                  "body": Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(1.6),
                    color: _getTextColor(context, settings),
                    fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
                  ),
                  "p": Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(1.6),
                    margin: Margins.only(bottom: 12),
                  ),
                  "h1": Style(
                    fontSize: FontSize(settings.fontSize * 1.5),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 16, bottom: 8),
                  ),
                  "h2": Style(
                    fontSize: FontSize(settings.fontSize * 1.3),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 14, bottom: 6),
                  ),
                  "h3": Style(
                    fontSize: FontSize(settings.fontSize * 1.2),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(top: 12, bottom: 4),
                  ),
                  "blockquote": Style(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                    padding: HtmlPaddings.only(left: 16, top: 8, bottom: 8),
                    margin: Margins.only(top: 8, bottom: 8),
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  "a": Style(
                    color: Theme.of(context).colorScheme.primary,
                    textDecoration: TextDecoration.underline,
                  ),
                  "img": Style(
                    margin: Margins.only(top: 8, bottom: 8),
                  ),
                  "ul": Style(
                    margin: Margins.only(top: 8, bottom: 8),
                  ),
                  "ol": Style(
                    margin: Margins.only(top: 8, bottom: 8),
                  ),
                  "li": Style(
                    margin: Margins.only(bottom: 4),
                  ),
                  "strong": Style(
                    fontWeight: FontWeight.bold,
                  ),
                  "em": Style(
                    fontStyle: FontStyle.italic,
                  ),
                  "code": Style(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 2),
                    fontSize: FontSize(settings.fontSize * 0.9),
                    fontFamily: 'monospace',
                  ),
                  "pre": Style(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    padding: HtmlPaddings.all(12),
                    margin: Margins.only(top: 8, bottom: 8),
                    fontSize: FontSize(settings.fontSize * 0.9),
                    fontFamily: 'monospace',
                  ),
                },
                onLinkTap: (url, _, __) {
                  if (url != null) {
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                },
              )
            else
              SelectableText(
                _cleanContent(displayContent),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: settings.fontSize,
                  height: 1.6,
                  color: _getTextColor(context, settings),
                ),
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
              // Toggle between full content and original content
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
                // Load full article for the first time
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

  Color _getBackgroundColor(BuildContext context, SettingsProvider settings) {
    return Theme.of(context).colorScheme.surface;
  }

  Color _getTextColor(BuildContext context, SettingsProvider settings) {
    return Theme.of(context).colorScheme.onSurface;
  }

  String _cleanContent(String content) {
    // Remove HTML tags and clean up the content
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

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'share':
        _shareArticle();
        break;
      case 'copy_link':
        _copyLink();
        break;
      case 'open_browser':
        _launchOriginalArticle();
        break;
    }
  }

  void _shareArticle() {
    final shareText = '${widget.article.title}\n\n${widget.article.url}';
    Share.share(
      shareText,
      subject: widget.article.title,
    );
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: widget.article.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  void _launchOriginalArticle() async {
    try {
      // Print URL for debugging
      print('Attempting to launch URL in-app: ${widget.article.url}');
      
      final Uri url = Uri.parse(widget.article.url);
      
      // Check if URL is valid
      if (url.scheme.isEmpty) {
        throw Exception('Invalid URL: ${widget.article.url}');
      }
      
      // Launch URL in in-app browser only
      bool launched = await launchUrl(
        url,
        mode: LaunchMode.inAppBrowserView,
      );
      
      if (!launched) {
        // If in-app browser fails, try webview
        launched = await launchUrl(
          url,
          mode: LaunchMode.inAppWebView,
        );
      }
      
      if (!launched) {
        throw Exception('Could not open article in app');
      }
    } catch (e) {
      print('Error launching URL: $e');
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
}
