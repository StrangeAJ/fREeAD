import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/article_reading_screen.dart';

class ArticleListWidget extends StatefulWidget {
  final List<Article> articles;
  final String? title;
  final bool showFilter;

  const ArticleListWidget({
    super.key,
    required this.articles,
    this.title,
    this.showFilter = true,
  });

  @override
  State<ArticleListWidget> createState() => _ArticleListWidgetState();
}

class _ArticleListWidgetState extends State<ArticleListWidget> {
  String _filter = 'all';
  String _sortBy = 'newest';
  List<Article> _filteredArticles = [];

  @override
  void initState() {
    super.initState();
    _filteredArticles = widget.articles;
  }

  @override
  void didUpdateWidget(ArticleListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articles != widget.articles) {
      _applyFiltersAndSort();
    }
  }

  void _applyFiltersAndSort() {
    setState(() {
      _filteredArticles = widget.articles.where((article) {
        if (_filter == 'unread') return !article.isRead;
        if (_filter == 'starred') return article.isStarred;
        if (_filter == 'saved') return article.isSaved;
        return true;
      }).toList();

      if (_sortBy == 'newest') {
        _filteredArticles.sort((a, b) => b.publishedDate.compareTo(a.publishedDate));
      } else if (_sortBy == 'oldest') {
        _filteredArticles.sort((a, b) => a.publishedDate.compareTo(b.publishedDate));
      } else if (_sortBy == 'title') {
        _filteredArticles.sort((a, b) => a.title.compareTo(b.title));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_filteredArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No articles found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (widget.showFilter) _buildFilterBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _filteredArticles.length,
            itemBuilder: (context, index) {
              final article = _filteredArticles[index];
              return _buildModernArticleCard(article);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Unread', 'unread'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Starred', 'starred'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Saved', 'saved'),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sort_rounded),
            onPressed: _showSortDialog,
            tooltip: 'Sort articles',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _filter = value;
            _applyFiltersAndSort();
          });
        }
      },
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sort by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildSortOption('Newest First', 'newest'),
              _buildSortOption('Oldest First', 'oldest'),
              _buildSortOption('Title (A-Z)', 'title'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOption(String label, String value) {
    return ListTile(
      title: Text(label),
      leading: Radio<String>(
        value: value,
        groupValue: _sortBy,
        onChanged: (newValue) {
          setState(() {
            _sortBy = newValue!;
            _applyFiltersAndSort();
          });
          Navigator.pop(context);
        },
      ),
      onTap: () {
        setState(() {
          _sortBy = value;
          _applyFiltersAndSort();
        });
        Navigator.pop(context);
      },
    );
  }

  Widget _buildModernArticleCard(Article article) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        final feed = feedProvider.getFeedById(article.feedId);
        final theme = Theme.of(context);

        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openArticle(article),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (article.imageUrl != null && article.imageUrl!.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      article.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: theme.colorScheme.surfaceVariant,
                        child: const Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (feed != null && feed.iconUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: CircleAvatar(
                                radius: 8,
                                backgroundImage: NetworkImage(feed.iconUrl!),
                              ),
                            ),
                          Text(
                            feed?.title ?? 'Unknown Source',
                            style: theme.textTheme.labelSmall,
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('MMM d, yyyy').format(article.publishedDate),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        article.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: article.isRead ? FontWeight.w500 : FontWeight.w700,
                          color: article.isRead ? theme.colorScheme.onSurface.withOpacity(0.7) : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (article.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          article.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (!article.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          const Spacer(),
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
                              color: article.isSaved ? theme.colorScheme.primary : null,
                            ),
                            onPressed: () => _toggleSaved(article),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_outlined),
                            onPressed: () {
                              // Basic share placeholder
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  }

  void _toggleSaved(Article article) {
    context.read<ArticleProvider>().toggleSaved(article.id);
  }
}
