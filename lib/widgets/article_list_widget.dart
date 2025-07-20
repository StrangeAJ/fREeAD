import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../providers/feed_provider.dart';
import '../screens/article_reading_screen.dart';
import '../widgets/futuristic_widgets.dart';
import 'package:intl/intl.dart';

enum ArticleViewType { list, card, compact }
enum ArticleSortType { newest, oldest, title, feed }
enum ArticleFilterType { all, unread, starred, saved }

class ArticleListWidget extends StatefulWidget {
  final Future<List<Article>> Function() articlesLoader;
  final String title;
  final String emptyMessage;
  final bool showSearchBar;
  final bool showFilters;
  final bool enableSwipeActions;
  final VoidCallback? onRefresh;
  final ArticleViewType defaultViewType;

  const ArticleListWidget({
    super.key,
    required this.articlesLoader,
    required this.title,
    this.emptyMessage = 'No articles found',
    this.showSearchBar = true,
    this.showFilters = true,
    this.enableSwipeActions = true,
    this.onRefresh,
    this.defaultViewType = ArticleViewType.card,
  });

  @override
  State<ArticleListWidget> createState() => _ArticleListWidgetState();
}

class _ArticleListWidgetState extends State<ArticleListWidget> {
  late Future<List<Article>> _articlesFuture;
  List<Article> _allArticles = [];
  List<Article> _filteredArticles = [];

  ArticleViewType _viewType = ArticleViewType.card;
  ArticleSortType _sortType = ArticleSortType.newest;
  ArticleFilterType _filterType = ArticleFilterType.all;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _viewType = widget.defaultViewType;
    _loadArticles();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _loadArticles() {
    setState(() {
      _articlesFuture = widget.articlesLoader();
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFiltersAndSort();
    });
  }

  void _applyFiltersAndSort() {
    List<Article> filtered = List.from(_allArticles);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((article) {
        return article.title.toLowerCase().contains(_searchQuery) ||
               article.description.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // Apply status filter
    switch (_filterType) {
      case ArticleFilterType.unread:
        filtered = filtered.where((article) => !article.isRead).toList();
        break;
      case ArticleFilterType.starred:
        filtered = filtered.where((article) => article.isStarred).toList();
        break;
      case ArticleFilterType.saved:
        filtered = filtered.where((article) => article.isSaved).toList();
        break;
      case ArticleFilterType.all:
        break;
    }

    // Apply sorting
    switch (_sortType) {
      case ArticleSortType.newest:
        filtered.sort((a, b) => b.publishedDate.compareTo(a.publishedDate));
        break;
      case ArticleSortType.oldest:
        filtered.sort((a, b) => a.publishedDate.compareTo(b.publishedDate));
        break;
      case ArticleSortType.title:
        filtered.sort((a, b) => a.title.compareTo(b.title));
        break;
      case ArticleSortType.feed:
        filtered.sort((a, b) => a.feedId.compareTo(b.feedId));
        break;
    }

    _filteredArticles = filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // View type toggle
          PopupMenuButton<ArticleViewType>(
            icon: Icon(_getViewTypeIcon()),
            onSelected: (type) {
              setState(() {
                _viewType = type;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ArticleViewType.card,
                child: Row(
                  children: [
                    Icon(Icons.view_agenda_rounded),
                    SizedBox(width: 8),
                    Text('Card View'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ArticleViewType.list,
                child: Row(
                  children: [
                    Icon(Icons.view_list_rounded),
                    SizedBox(width: 8),
                    Text('List View'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ArticleViewType.compact,
                child: Row(
                  children: [
                    Icon(Icons.view_headline_rounded),
                    SizedBox(width: 8),
                    Text('Compact View'),
                  ],
                ),
              ),
            ],
          ),
          // Sort menu
          if (widget.showFilters)
            PopupMenuButton<ArticleSortType>(
              icon: Icon(Icons.sort_rounded),
              onSelected: (type) {
                setState(() {
                  _sortType = type;
                  _applyFiltersAndSort();
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: ArticleSortType.newest,
                  child: Text('Newest First'),
                ),
                PopupMenuItem(
                  value: ArticleSortType.oldest,
                  child: Text('Oldest First'),
                ),
                PopupMenuItem(
                  value: ArticleSortType.title,
                  child: Text('By Title'),
                ),
                PopupMenuItem(
                  value: ArticleSortType.feed,
                  child: Text('By Feed'),
                ),
              ],
            ),
          // Refresh button
          if (widget.onRefresh != null)
            IconButton(
              icon: Icon(Icons.refresh_rounded),
              onPressed: () {
                widget.onRefresh!();
                _loadArticles();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          if (widget.showSearchBar)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search articles...',
                  prefixIcon: Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          // Filter chips
          if (widget.showFilters)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('All', ArticleFilterType.all),
                  SizedBox(width: 8),
                  _buildFilterChip('Unread', ArticleFilterType.unread),
                  SizedBox(width: 8),
                  _buildFilterChip('Starred', ArticleFilterType.starred),
                  SizedBox(width: 8),
                  _buildFilterChip('Saved', ArticleFilterType.saved),
                ],
              ),
            ),

          // Articles list
          Expanded(
            child: FutureBuilder<List<Article>>(
              future: _articlesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: FuturisticCard(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Error Loading Articles',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadArticles,
                            child: Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                _allArticles = snapshot.data ?? [];
                _applyFiltersAndSort();

                if (_filteredArticles.isEmpty) {
                  return Center(
                    child: FuturisticCard(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.article_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                          ),
                          SizedBox(height: 16),
                          Text(
                            widget.emptyMessage,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_searchQuery.isNotEmpty || _filterType != ArticleFilterType.all) ...[
                            SizedBox(height: 8),
                            Text(
                              'Try adjusting your search or filters',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    if (widget.onRefresh != null) {
                      widget.onRefresh!();
                    }
                    _loadArticles();
                  },
                  child: _buildArticlesList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getViewTypeIcon() {
    switch (_viewType) {
      case ArticleViewType.card:
        return Icons.view_agenda_rounded;
      case ArticleViewType.list:
        return Icons.view_list_rounded;
      case ArticleViewType.compact:
        return Icons.view_headline_rounded;
    }
  }

  Widget _buildFilterChip(String label, ArticleFilterType type) {
    return FilterChip(
      label: Text(label),
      selected: _filterType == type,
      onSelected: (selected) {
        setState(() {
          _filterType = type;
          _applyFiltersAndSort();
        });
      },
    );
  }

  Widget _buildArticlesList() {
    switch (_viewType) {
      case ArticleViewType.card:
        return ListView.builder(
          itemCount: _filteredArticles.length,
          itemBuilder: (context, index) => _buildCardView(_filteredArticles[index]),
        );
      case ArticleViewType.list:
        return ListView.builder(
          itemCount: _filteredArticles.length,
          itemBuilder: (context, index) => _buildListView(_filteredArticles[index]),
        );
      case ArticleViewType.compact:
        return ListView.builder(
          itemCount: _filteredArticles.length,
          itemBuilder: (context, index) => _buildCompactView(_filteredArticles[index]),
        );
    }
  }

  Widget _buildCardView(Article article) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        final feed = feedProvider.getFeedById(article.feedId);

        return FuturisticCard(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: InkWell(
            onTap: () => _openArticle(article),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with feed info and date
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          feed?.title ?? 'Unknown Feed',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat('MMM d, HH:mm').format(article.publishedDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),

                  // Title
                  Text(
                    article.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: article.isRead ? FontWeight.normal : FontWeight.bold,
                      color: article.isRead
                          ? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                          : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Description
                  if (article.description.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Text(
                      article.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  SizedBox(height: 12),

                  // Actions row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (!article.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (!article.isRead) SizedBox(width: 8),
                          if (article.author?.isNotEmpty == true)
                            Text(
                              'by ${article.author}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              article.isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                              color: article.isStarred ? Colors.amber : null,
                            ),
                            onPressed: () => _toggleStar(article),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: Icon(
                              article.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                              color: article.isSaved ? Theme.of(context).colorScheme.primary : null,
                            ),
                            onPressed: () => _toggleSaved(article),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView(Article article) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        final feed = feedProvider.getFeedById(article.feedId);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            child: Icon(
              Icons.article_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            article.title,
            style: TextStyle(
              fontWeight: article.isRead ? FontWeight.normal : FontWeight.bold,
              color: article.isRead
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                  : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.description.isNotEmpty) ...[
                SizedBox(height: 4),
                Text(
                  article.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    feed?.title ?? 'Unknown Feed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    DateFormat('MMM d').format(article.publishedDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!article.isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              SizedBox(width: 8),
              if (article.isStarred)
                Icon(Icons.star_rounded, color: Colors.amber, size: 16),
              if (article.isSaved)
                Icon(Icons.bookmark_rounded, color: Theme.of(context).colorScheme.primary, size: 16),
            ],
          ),
          onTap: () => _openArticle(article),
        );
      },
    );
  }

  Widget _buildCompactView(Article article) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        final feed = feedProvider.getFeedById(article.feedId);

        return ListTile(
          dense: true,
          title: Text(
            article.title,
            style: TextStyle(
              fontWeight: article.isRead ? FontWeight.normal : FontWeight.bold,
              color: article.isRead
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                  : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  feed?.title ?? 'Unknown Feed',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                DateFormat('MMM d').format(article.publishedDate),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!article.isRead)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              if (article.isStarred)
                Icon(Icons.star_rounded, color: Colors.amber, size: 14),
              if (article.isSaved)
                Icon(Icons.bookmark_rounded, color: Theme.of(context).colorScheme.primary, size: 14),
            ],
          ),
          onTap: () => _openArticle(article),
        );
      },
    );
  }

  void _openArticle(Article article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleReadingScreen(article: article),
      ),
    );
  }

  void _toggleStar(Article article) {
    context.read<ArticleProvider>().toggleStar(article.id);
    // Don't try to modify the immutable article object directly
    // The provider will handle updating the state and notify listeners
    setState(() {
      // Refresh the filtered articles after the provider updates
      _applyFiltersAndSort();
    });
  }

  void _toggleSaved(Article article) {
    context.read<ArticleProvider>().toggleSaved(article.id);
    // Don't try to modify the immutable article object directly
    // The provider will handle updating the state and notify listeners
    setState(() {
      // Refresh the filtered articles after the provider updates
      _applyFiltersAndSort();
    });
  }
}
