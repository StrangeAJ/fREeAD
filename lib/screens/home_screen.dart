import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../providers/feed_provider.dart';
import '../providers/article_provider.dart';
import '../providers/settings_provider.dart';
import '../services/summarization_service.dart';
import '../screens/article_reading_screen.dart';
import '../screens/feed_management_screen.dart';
import '../screens/category_articles_screen.dart';
import '../widgets/futuristic_widgets.dart';
import '../widgets/futuristic_dialogs.dart';
import '../widgets/futuristic_search_delegate.dart';
import '../widgets/feed_summary_dialog.dart';
import '../widgets/article_list_widget.dart';

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
    
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: FuturisticAppBar(
        title: 'FreeAd',
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
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Summarize Feed',
            onPressed: () {
              _showFeedSummaryDialog(context);
            },
          ),
        ],
      ),
      body: Container(
        color: theme.colorScheme.surface,
        child: SafeArea(
          bottom: false,
          child: _buildBody(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.category_outlined),
                  activeIcon: Icon(Icons.category_rounded),
                  label: 'Feeds',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bookmark_outline_rounded),
                  activeIcon: Icon(Icons.bookmark_rounded),
                  label: 'Saved',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddFeedDialog(),
        tooltip: 'Add Feed',
        child: const Icon(Icons.add_rounded),
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
        if (articleProvider.isLoading && articleProvider.articles.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final articles = articleProvider.articles;

        return RefreshIndicator(
          onRefresh: () => articleProvider.refreshAllArticles(),
          child: ArticleListWidget(articles: articles),
        );
      },
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

        final feeds = feedProvider.feeds;
        if (feeds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rss_feed_rounded, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                const Text('No feeds added yet'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _showAddFeedDialog(context),
                  child: const Text('Add your first feed'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: feeds.length,
          itemBuilder: (context, index) {
            final feed = feeds[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: feed.iconUrl != null
                    ? CircleAvatar(backgroundImage: NetworkImage(feed.iconUrl!))
                    : const CircleAvatar(child: Icon(Icons.rss_feed)),
                title: Text(feed.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(feed.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CategoryArticlesScreen(
                        categoryId: feed.id,
                        categoryName: feed.title,
                      ),
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

  void _showAddFeedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const FuturisticAddFeedDialog(),
    );
  }
}

class SavedTab extends StatelessWidget {
  const SavedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ArticleProvider>(
      builder: (context, articleProvider, child) {
        final articles = articleProvider.savedArticles;
        
        if (articles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_outline_rounded, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No saved articles yet'),
              ],
            ),
          );
        }

        return ArticleListWidget(
          articles: articles,
          showFilter: false,
          title: 'Saved Articles',
        );
      },
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildSectionHeader(context, 'Appearance'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_medium_rounded),
                title: const Text('Theme Mode'),
                subtitle: Text(settings.themeMode.name.toUpperCase()),
                onTap: () => _showThemePicker(context, settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'AI Summarization'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.api_rounded),
                title: const Text('Provider'),
                subtitle: Text(settings.summarizationProvider.toUpperCase()),
                onTap: () => _showProviderPicker(context, settings),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('API Keys'),
                subtitle: const Text('Manage your API keys'),
                onTap: () => _showApiKeysDialog(context, settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'About'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('FreeAd'),
            subtitle: const Text('Version 2.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'FreeAd',
                applicationVersion: '2.0.0',
                applicationLegalese: '© 2024 FreeAd Team',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Theme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildThemeOption(context, settings, ThemeMode.system, 'System Default'),
            _buildThemeOption(context, settings, ThemeMode.light, 'Light'),
            _buildThemeOption(context, settings, ThemeMode.dark, 'Dark'),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(BuildContext context, SettingsProvider settings, ThemeMode mode, String label) {
    return ListTile(
      title: Text(label),
      leading: Radio<ThemeMode>(
        value: mode,
        groupValue: settings.themeMode,
        onChanged: (value) {
          settings.setThemeMode(value!);
          Navigator.pop(context);
        },
      ),
      onTap: () {
        settings.setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showProviderPicker(BuildContext context, SettingsProvider settings) {
    final providers = ['openai', 'claude', 'gemini', 'openrouter', 'perplexity', 'nvidia'];
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select AI Provider', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...providers.map((p) => ListTile(
              title: Text(p.toUpperCase()),
              leading: Radio<String>(
                value: p,
                groupValue: settings.summarizationProvider,
                onChanged: (value) {
                  settings.setSummarizationProvider(value!);
                  Navigator.pop(context);
                },
              ),
              onTap: () {
                settings.setSummarizationProvider(p);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showApiKeysDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => const ApiKeySettingsDialog(),
    );
  }
}

class FuturisticAddFeedDialog extends StatefulWidget {
  const FuturisticAddFeedDialog({super.key});

  @override
  State<FuturisticAddFeedDialog> createState() => _FuturisticAddFeedDialogState();
}

class _FuturisticAddFeedDialogState extends State<FuturisticAddFeedDialog> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final List<Map<String, String>> _sampleFeeds = [
    {'title': 'BBC News', 'url': 'http://feeds.bbci.co.uk/news/rss.xml'},
    {'title': 'CNN', 'url': 'https://rss.cnn.com/rss/edition.rss'},
    {'title': 'Reuters', 'url': 'https://feeds.reuters.com/reuters/topNews'},
    {'title': 'NASA', 'url': 'https://www.nasa.gov/rss/dyn/breaking_news.rss'},
    {'title': 'NPR', 'url': 'https://feeds.npr.org/1001/rss.xml'},
  ];

  @override
  Widget build(BuildContext context) {
    return FuturisticDialog(
      title: 'Add RSS Feed',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'RSS Feed URL',
                prefixIcon: Icon(Icons.rss_feed),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter a URL';
                if (!Uri.tryParse(value)!.isAbsolute) return 'Please enter a valid URL';
                return null;
              },
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Suggested Feeds:', style: TextStyle(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sampleFeeds.map((feed) => ActionChip(
                label: Text(feed['title']!),
                onPressed: () => _urlController.text = feed['url']!,
              )).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addFeed,
          child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add Feed'),
        ),
      ],
    );
  }

  Future<void> _addFeed() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final success = await context.read<FeedProvider>().addFeed(_urlController.text);
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feed added successfully!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<FeedProvider>().error ?? 'Failed to add feed')));
      }
    }
  }
}

class ApiKeySettingsDialog extends StatefulWidget {
  const ApiKeySettingsDialog({super.key});

  @override
  State<ApiKeySettingsDialog> createState() => _ApiKeySettingsDialogState();
}

class _ApiKeySettingsDialogState extends State<ApiKeySettingsDialog> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _controllers = {
      'openai': TextEditingController(text: settings.openaiApiKey),
      'claude': TextEditingController(text: settings.claudeApiKey),
      'gemini': TextEditingController(text: settings.geminiApiKey),
      'openrouter': TextEditingController(text: settings.openrouterApiKey),
      'perplexity': TextEditingController(text: settings.perplexityApiKey),
      'nvidia': TextEditingController(text: settings.nvidiaApiKey),
    };
  }

  @override
  Widget build(BuildContext context) {
    return FuturisticDialog(
      title: 'API Keys',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _controllers.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: e.value,
              decoration: InputDecoration(
                labelText: e.key.toUpperCase(),
                prefixIcon: const Icon(Icons.vpn_key_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save_rounded),
                  onPressed: () => _saveKey(e.key, e.value.text),
                ),
              ),
              obscureText: true,
            ),
          )).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  void _saveKey(String provider, String value) {
    final settings = context.read<SettingsProvider>();
    switch (provider) {
      case 'openai': settings.setOpenaiApiKey(value); break;
      case 'claude': settings.setClaudeApiKey(value); break;
      case 'gemini': settings.setGeminiApiKey(value); break;
      case 'openrouter': settings.setOpenrouterApiKey(value); break;
      case 'perplexity': settings.setPerplexityApiKey(value); break;
      case 'nvidia': settings.setNvidiaApiKey(value); break;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${provider.toUpperCase()} key saved')));
  }
}
