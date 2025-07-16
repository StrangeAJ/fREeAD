import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/article_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/article_reading_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FreeAd'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshContent(),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.category),
            label: 'Categories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddFeedDialog(),
        child: const Icon(Icons.add),
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
      delegate: ArticleSearchDelegate(),
    );
  }

  void _showAddFeedDialog() {
    showDialog(
      context: context,
      builder: (context) => const AddFeedDialog(),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
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
          );
        }

        final articles = articleProvider.articles;
        if (articles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rss_feed, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No articles yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Add some RSS feeds to get started',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => articleProvider.refreshAllArticles(),
          child: ListView.builder(
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: article.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            article.imageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey[300],
                                child: const Icon(Icons.article),
                              );
                            },
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.article),
                        ),
                  title: Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: article.isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        article.timeAgo,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          article.isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: article.isSaved ? Colors.orange : null,
                        ),
                        onPressed: () => articleProvider.toggleSaved(article.id),
                      ),
                      IconButton(
                        icon: Icon(
                          article.isStarred ? Icons.star : Icons.star_border,
                          color: article.isStarred ? Colors.amber : null,
                        ),
                        onPressed: () => articleProvider.toggleStarred(article.id),
                      ),
                    ],
                  ),
                  onTap: () => _openArticle(context, article),
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
          return const Center(
            child: Text('No categories available'),
          );
        }

        return ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final feedCount = feedProvider.getFeedsByCategory(category.id).length;
            
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: category.color != null 
                        ? Color(int.parse(category.color!.substring(1, 7), radix: 16) + 0xFF000000)
                        : Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.category, color: Colors.white),
                ),
                title: Text(category.name),
                subtitle: Text(category.description),
                trailing: Text('$feedCount feeds'),
                onTap: () {
                  // TODO: Navigate to category detail screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Category: ${category.name}')),
                  );
                },
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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No saved articles',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Save articles to read them later',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: savedArticles.length,
          itemBuilder: (context, index) {
            final article = savedArticles[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(article.title),
                subtitle: Text(article.description),
                trailing: IconButton(
                  icon: const Icon(Icons.bookmark, color: Colors.orange),
                  onPressed: () => articleProvider.toggleSaved(article.id),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ArticleReadingScreen(article: article),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return ListView(
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette),
                    title: const Text('Theme'),
                    subtitle: Text(_getThemeText(settings.themeMode)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showThemeDialog(context, settings),
                  ),
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: const Text('Font Size'),
                    subtitle: Text('${settings.fontSize.toInt()}px'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFontSizeDialog(context, settings),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.refresh),
                    title: const Text('Auto Refresh'),
                    subtitle: const Text('Automatically refresh feeds'),
                    value: settings.autoRefresh,
                    onChanged: (value) => settings.setAutoRefresh(value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.image),
                    title: const Text('Load Images'),
                    subtitle: const Text('Show images in articles'),
                    value: settings.imageLoadingEnabled,
                    onChanged: (value) => settings.setImageLoadingEnabled(value),
                  ),
                ],
              ),
            ),
          ],
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
      builder: (context) => AlertDialog(
        title: const Text('Select Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: settings.themeMode,
              onChanged: (value) {
                if (value != null) {
                  settings.setThemeMode(value);
                  Navigator.of(context).pop();
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: settings.themeMode,
              onChanged: (value) {
                if (value != null) {
                  settings.setThemeMode(value);
                  Navigator.of(context).pop();
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
              groupValue: settings.themeMode,
              onChanged: (value) {
                if (value != null) {
                  settings.setThemeMode(value);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Font Size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: settings.availableFontSizes.map((entry) {
            return RadioListTile<double>(
              title: Text(entry.value),
              value: entry.key,
              groupValue: settings.fontSize,
              onChanged: (value) {
                if (value != null) {
                  settings.setFontSize(value);
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        ),
      ),
    );
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
