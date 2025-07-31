import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/article_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/article_reading_screen.dart';
import '../screens/feed_management_screen.dart';
import '../screens/category_articles_screen.dart';
import '../widgets/futuristic_widgets.dart';
import '../widgets/futuristic_dialogs.dart';
import '../widgets/futuristic_search_delegate.dart';
import '../widgets/feed_summary_dialog.dart';
import '../utils/time_formatter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: FuturisticAppBar(
        title: 'fREeAD',
        actions: [
          IconButton(
            icon: const Icon(Icons.rss_feed_rounded),
            onPressed: () => _showFeedManagement(),
            tooltip: 'Manage Feeds',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refreshContent(),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _showSearch(),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Summarize Feed',
            onPressed: () {
              _showFeedSummaryDialog(context);
            },
          ),
        ],
      ),
      body: AnimatedGradientBackground(
        colors: isDark ? [
          const Color.fromARGB(255, 0, 0, 0),
          const Color.fromARGB(250, 10, 10, 10),
          const Color.fromARGB(240, 40, 40, 40),
        ] : [
          const Color(0xFFF5F5F7),
          const Color.fromARGB(255, 205, 205, 205),
          const Color.fromARGB(255, 190, 190, 190),
        ],
        duration: const Duration(seconds: 30),
        child: SafeArea(
          child: _buildBody(),
        ),
      ),
      bottomNavigationBar: FuturisticBottomNav(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.category_rounded),
            label: 'Categories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_rounded),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FuturisticFAB(
        onPressed: () => _showAddFeedDialog(),
        icon: Icons.add_rounded,
        tooltip: 'Add Feed',
        showPulse: true,
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const HomeTab();
      case 1:
        return const CategoriesTab();
      case 2:
        return const SavedTab();
      case 3:
        return const SettingsTab();
      default:
        return const HomeTab();
    }
  }

  void _refreshContent() {
    final articleProvider = context.read<ArticleProvider>();
    final feedProvider = context.read<FeedProvider>();
    
    articleProvider.refreshAllArticles();
    feedProvider.refreshAllFeeds();
  }

  void _showSearch() {
    showSearch(
      context: context,
      delegate: FuturisticSearchDelegate(),
    );
  }

  void _showFeedManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeedManagementScreen(),
      ),
    );
  }

  void _showAddFeedDialog() {
    showDialog(
      context: context,
      builder: (context) => const FuturisticAddFeedDialog(),
    );
  }

  void _showFeedSummaryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const FeedSummaryDialog(),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        if (articleProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (articleProvider.error != null) {
          return Center(
            child:
                Flexible(
                  child:
                      FuturisticCard(
              showGlow: true,
              glowColor: Colors.yellowAccent,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading articles',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    articleProvider.error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => articleProvider.loadArticles(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
                  ),
          );
        }

        final articles = articleProvider.articles;
        if (articles.isEmpty) {
          return Center(
            child: FuturisticCard(
              glowColor: Colors.redAccent,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.rss_feed_rounded, 
                    size: 64, 
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No articles yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add some RSS feeds to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // TODO() Function to get Feed Name and Feed Icon URL


        // Function to get Feed Name and Feed Icon URL
        String _getFeedName(String feedId) {
          final feedProvider = context.read<FeedProvider>();
          final feed = feedProvider.getFeedById(feedId);
          return feed?.title ?? 'Unknown Feed';
        }

        String? _getFeedIconUrl(String feedId) {
          final feedProvider = context.read<FeedProvider>();
          final feed = feedProvider.getFeedById(feedId);
          return feed?.imageUrl;
        }

        return RefreshIndicator(
          onRefresh: () => articleProvider.refreshAllArticles(),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100), // Account for bottom nav
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return FuturisticCard(
                onTap: () => _openArticle(context, article),
                showGlow: !article.isRead,
                glowColor: const Color.fromARGB(194, 105, 160, 255),
                borderColor: article.isRead ? const Color.fromARGB(105, 255, 255, 0) : const Color.fromARGB(255, 195, 105, 255),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Article image
                    Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16), color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: article.imageUrl != null
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              article.imageUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.article_rounded,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          )
                              : Icon(
                            Icons.article_outlined,
                            size: 40,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // Add Feed Icon or Name of Feed Here
                        const SizedBox(height: 8),
                        Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Feed icon or RSS icon
                              _getFeedIconUrl(article.feedId) != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      _getFeedIconUrl(article.feedId)!,
                                      width: 12,
                                      height: 12,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(
                                          Icons.rss_feed,
                                          size: 12,
                                          color: Theme.of(context).colorScheme.primary,
                                        );
                                      },
                                    ),
                                  )
                                : Icon(
                                    Icons.rss_feed,
                                    size: 12,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                              const SizedBox(width: 4),
                              // Feed name
                              Expanded(
                                child: Text(
                                  _getFeedName(article.feedId),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 16),
                    
                    // Article content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: article.isRead ? FontWeight.w500 : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            article.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(flex: 1,
                              child :
                                Row(
                                    children:[
                                      Icon(
                                      Icons.access_time_rounded,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                TimeFormatter.formatRelativeTime(article.publishedDate),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              )
                                    ]
                                )
                              ),
                              Flexible(flex: 1,
                                child :
                                Row(
                                  children:[
                                    Icon(
                                      Icons.person_rounded,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(width: 2),
                                    Expanded(child:
                                    Text(
                                      article.author?.trimLeft() ?? 'Unknown',
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),

                                      ),
                                    ),
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Action buttons
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            article.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: article.isSaved ? Colors.orange : null,
                          ),
                          onPressed: () => articleProvider.toggleSaved(article.id),
                        ),
                        IconButton(
                          icon: Icon(
                            article.isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                            color: article.isStarred ? Colors.amber : null,
                          ),
                          onPressed: () => articleProvider.toggleStarred(article.id),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openArticle(BuildContext context, article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleReadingScreen(article: article),
      ),
    );
  }
}

class CategoriesTab extends StatelessWidget {
  const CategoriesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        if (feedProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = feedProvider.categories;
        if (categories.isEmpty) {
          return Center(
            child: FuturisticCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.category_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No categories yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Categories will appear here as you add feeds',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100), // Account for bottom nav
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final feedCount = feedProvider.getFeedsByCategory(category.id).length;
            return FuturisticCard(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CategoryArticlesScreen(
                      categoryId: category.id,
                      categoryName: category.name,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: category.color != null 
                          ? Color(int.parse(category.color!.substring(1, 7), radix: 16) + 0xFF000000)
                          : Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (category.color != null 
                              ? Color(int.parse(category.color!.substring(1, 7), radix: 16) + 0xFF000000)
                              : Theme.of(context).colorScheme.primary).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.category_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category.description,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$feedCount feeds',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class SavedTab extends StatelessWidget {
  const SavedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final savedArticles = articleProvider.savedArticles;
        
        if (savedArticles.isEmpty) {
          return Center(
            child: FuturisticCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved articles',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Save articles to read them later',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100), // Account for bottom nav
          itemCount: savedArticles.length,
          itemBuilder: (context, index) {
            final article = savedArticles[index];
            return FuturisticCard(
              onTap: () => _openArticle(context, article),
              showGlow: true,
              glowColor: Colors.orange,
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: Colors.orange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          article.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Saved • ${article.timeAgo}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_rounded, color: Colors.orange),
                    onPressed: () => articleProvider.toggleSaved(article.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  void _openArticle(BuildContext context, article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleReadingScreen(article: article),
      ),
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 16),
              // Theme setting
              FuturisticCard(
                onTap: () => _showThemeDialog(context, settings),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.palette_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Theme',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getThemeText(settings.themeMode),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
              // Font size setting
              FuturisticCard(
                onTap: () => _showFontSizeDialog(context, settings),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.text_fields_rounded,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Font Size',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${settings.fontSize.toInt()}px',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Features',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 16),
              // Auto refresh toggle
              FuturisticCard(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto Refresh',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Automatically refresh feeds',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.autoRefresh,
                      onChanged: (value) => settings.setAutoRefresh(value),
                    ),
                  ],
                ),
              ),
              // Image loading toggle
              FuturisticCard(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.image_rounded,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Load Images',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Show images in articles',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.imageLoadingEnabled,
                      onChanged: (value) => settings.setImageLoadingEnabled(value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'AI Models',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 16),

              // Preferred provider selection
              FuturisticCard(
                onTap: () => _showPreferredProviderDialog(context, settings),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.star, color: Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preferred Provider',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            settings.preferredProvider == SettingsProvider.providerNone
                              ? 'None selected'
                              : settings.availableAiProviders
                                  .firstWhere((e) => e.key == settings.preferredProvider)
                                  .value,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  ],
                ),
              ),

              // Provider status overview
              FuturisticCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configured Providers',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ...settings.availableAiProviders
                        .where((provider) => provider.key != SettingsProvider.providerNone)
                        .map((provider) {
                      final isConfigured = settings.isProviderConfigured(provider.key);
                      final isPreferred = settings.preferredProvider == provider.key;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              isConfigured ? Icons.check_circle : Icons.circle_outlined,
                              size: 20,
                              color: isConfigured
                                ? (isPreferred ? Colors.blue : Colors.green)
                                : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                provider.value,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: isConfigured
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  fontWeight: isPreferred ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isPreferred)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'PREFERRED',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),

              // API Keys section - show all providers
              ...settings.availableAiProviders
                  .where((provider) => provider.key != SettingsProvider.providerNone)
                  .map((provider) {
                final apiKey = _getApiKeyForProvider(settings, provider.key);
                final isConfigured = apiKey.isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FuturisticCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getProviderIcon(provider.key),
                              color: isConfigured ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${provider.value} API Key',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: isConfigured
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ),
                            if (isConfigured)
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: apiKey,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Enter ${provider.value} API key',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: apiKey.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => _clearApiKey(settings, provider.key),
                                )
                              : null,
                          ),
                          onChanged: (value) => _updateApiKey(settings, provider.key, value),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  String _getThemeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemeDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface.withAlpha(127),
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Theme',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              _buildThemeOption(
                context,
                'Light',
                ThemeMode.light,
                settings.themeMode,
                Icons.light_mode_rounded,
                () {
                  settings.setThemeMode(ThemeMode.light);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 12),
              _buildThemeOption(
                context,
                'Dark',
                ThemeMode.dark,
                settings.themeMode,
                Icons.dark_mode_rounded,
                () {
                  settings.setThemeMode(ThemeMode.dark);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 12),
              _buildThemeOption(
                context,
                'System',
                ThemeMode.system,
                settings.themeMode,
                Icons.settings_system_daydream_rounded,
                () {
                  settings.setThemeMode(ThemeMode.system);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String title,
    ThemeMode value,
    ThemeMode groupValue,
    IconData icon,
    VoidCallback onTap,
  ) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.outline.withAlpha(225)
              : Theme.of(context).colorScheme.outline.withAlpha(180),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface.withAlpha(127),
        child: GlassContainer(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  'Select Font Size',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Font size options with better spacing
                ...settings.availableFontSizes.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        settings.setFontSize(entry.key);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: settings.fontSize == entry.key
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline.withAlpha(204),
                          ),
                          color: settings.fontSize == entry.key
                              ? Theme.of(context).colorScheme.primary.withAlpha(90)
                              : Theme.of(context).colorScheme.outline.withAlpha(40),
                        ),
                        child: Row(
                          children: [
                            // Radio indicator
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: settings.fontSize == entry.key
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outline.withAlpha(204),
                                  width: 2,
                                ),
                                color: settings.fontSize == entry.key
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                              child: settings.fontSize == entry.key
                                  ? Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            
                            // Font size label
                            Expanded(
                              child: Text(
                                entry.value,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: settings.fontSize == entry.key
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface,
                                  fontWeight: settings.fontSize == entry.key
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
                
                const SizedBox(height: 16),
                
                // Close button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPreferredProviderDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: settings.availableAiProviders.map((entry) {
              return ListTile(
                leading: Radio<String>(
                  value: entry.key,
                  groupValue: settings.preferredProvider,
                  onChanged: (value) {
                    if (value != null) {
                      settings.setPreferredProvider(value);
                    }
                    Navigator.of(context).pop();
                  },
                ),
                title: Text(entry.value),
                onTap: () {
                  settings.setPreferredProvider(entry.key);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // Helper methods for API key management
  String _getApiKeyForProvider(SettingsProvider settings, String providerKey) {
    switch (providerKey) {
      case 'openai':
        return settings.openaiApiKey;
      case 'anthropic':
      case 'claude':
        return settings.claudeApiKey;
      case 'google':
      case 'gemini':
        return settings.geminiApiKey;
      case 'ollama':
      case 'openrouter':
        return settings.openrouterApiKey;
      case 'perplexity':
        return settings.perplexityApiKey;
      default:
        return '';
    }
  }

  IconData _getProviderIcon(String providerKey) {
    switch (providerKey) {
      case 'openai':
        return Icons.psychology;
      case 'anthropic':
      case 'claude':
        return Icons.smart_toy;
      case 'google':
      case 'gemini':
        return Icons.cloud;
      case 'ollama':
      case 'openrouter':
        return Icons.computer;
      case 'perplexity':
        return Icons.api;
      default:
        return Icons.api;
    }
  }

  void _clearApiKey(SettingsProvider settings, String providerKey) {
    _updateApiKey(settings, providerKey, '');
  }

  void _updateApiKey(SettingsProvider settings, String providerKey, String value) {
    switch (providerKey) {
      case 'openai':
        settings.setOpenaiApiKey(value);
        break;
      case 'anthropic':
      case 'claude':
        settings.setClaudeApiKey(value);
        break;
      case 'google':
      case 'gemini':
        settings.setGeminiApiKey(value);
        break;
      case 'ollama':
      case 'openrouter':
        settings.setOpenrouterApiKey(value);
        break;
      case 'perplexity':
        settings.setPerplexityApiKey(value);
        break;
    }
  }
}

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Sample RSS feeds for testing
  final List<Map<String, String>> _sampleFeeds = [
    {
      'title': 'Simple RSS Test',
      'url': 'https://rss.cnn.com/rss/edition.rss',
    },
    {
      'title': 'BBC News',
      'url': 'http://feeds.bbci.co.uk/news/rss.xml',
    },
    {
      'title': 'Reuters',
      'url': 'https://feeds.reuters.com/reuters/topNews',
    },
    {
      'title': 'NASA',
      'url': 'https://www.nasa.gov/rss/dyn/breaking_news.rss',
    },
    {
      'title': 'NPR',
      'url': 'https://feeds.npr.org/1001/rss.xml',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add RSS Feed'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'RSS Feed URL',
                  hintText: 'https://example.com/rss.xml',
                  prefixIcon: Icon(Icons.rss_feed),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a URL';
                  }
                  if (!Uri.tryParse(value)!.isAbsolute) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
                onChanged: (value) {
                  // Auto-validate while typing
                  if (value.isNotEmpty) {
                    _formKey.currentState?.validate();
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // Sample feeds section
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Or try these sample feeds:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 8),
              
              // Sample feeds as buttons instead of ListView
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _sampleFeeds.map((feed) {
                  return ActionChip(
                    label: Text(
                      feed['title']!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      _urlController.text = feed['url']!;
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addFeed,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Feed'),
        ),
      ],
    );
  }

  Future<void> _addFeed() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final feedProvider = context.read<FeedProvider>();
    final success = await feedProvider.addFeed(_urlController.text);

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('RSS feed added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedProvider.error ?? 'Failed to add RSS feed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class ArticleSearchDelegate extends SearchDelegate {
  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    if (query.isEmpty) {
      return const Center(
        child: Text('Enter search terms'),
      );
    }

    return FutureBuilder(
      future: context.read<ArticleProvider>().searchArticles(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final articles = snapshot.data ?? [];
        if (articles.isEmpty) {
          return const Center(child: Text('No articles found'));
        }

        return ListView.builder(
          itemCount: articles.length,
          itemBuilder: (context, index) {
            final article = articles[index];
            return ListTile(
              title: Text(article.title),
              subtitle: Text(article.description),
              onTap: () {
                close(context, article);
              },
            );
          },
        );
      },
    );
  }
}
