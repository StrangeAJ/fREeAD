import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import '../providers/feed_provider.dart';
import '../providers/article_provider.dart';
import '../models/rss_feed.dart';
import '../services/opml_service.dart';
import '../widgets/futuristic_widgets.dart';

class FeedManagementScreen extends StatefulWidget {
  const FeedManagementScreen({super.key});

  @override
  State<FeedManagementScreen> createState() => _FeedManagementScreenState();
}

class _FeedManagementScreenState extends State<FeedManagementScreen> {
  String _selectedCategory = 'all';
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FeedProvider>().loadFeeds();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Feeds'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import OPML',
            onPressed: () => _showImportOpmlDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export OPML',
            onPressed: () => _exportOpmlFile(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<FeedProvider>().refreshAllFeeds();
              context.read<ArticleProvider>().refreshAllArticles();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter
          _buildCategoryFilter(),
          // Feed list
          Expanded(
            child: _buildFeedList(),
          ),
        ],
      ),
      floatingActionButton: FuturisticFAB(
        icon: Icons.add,
        tooltip: 'Add Feed',
        onPressed: () => _showAddFeedDialog(),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        final categories = ['all', ...feedProvider.categories.map((c) => c.id)];
        
        return Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category == 'all' ? 'All' : category),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = category;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeedList() {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        if (feedProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (feedProvider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading feeds',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  feedProvider.error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => feedProvider.loadFeeds(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final feeds = _selectedCategory == 'all' 
            ? feedProvider.feeds 
            : feedProvider.getFeedsByCategory(_selectedCategory);

        if (feeds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.rss_feed,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No feeds found',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first RSS feed to get started',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddFeedDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Feed'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: feeds.length,
          itemBuilder: (context, index) {
            final feed = feeds[index];
            return _buildFeedCard(feed);
          },
        );
      },
    );
  }

  Widget _buildFeedCard(RSSFeed feed) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feed.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feed.url,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: feed.isActive,
                  onChanged: (value) => _toggleFeedStatus(feed, value),
                ),
              ],
            ),
            if (feed.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                feed.description,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Updated: ${_formatDate(feed.lastUpdated ?? DateTime.now())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _refreshFeed(feed),
                      tooltip: 'Refresh Feed',
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showEditFeedDialog(feed),
                      tooltip: 'Edit Feed',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _showDeleteConfirmation(feed),
                      tooltip: 'Delete Feed',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _showImportOpmlDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import OPML File'),
        content: const Text('Select an OPML file to import your RSS feeds.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _importOpmlFile();
            },
            child: const Text('Select File'),
          ),
        ],
      ),
    );
  }

  Future<void> _importOpmlFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['opml', 'xml'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        if (file.path != null) {
          final fileContent = await File(file.path!).readAsString();
          final feeds = OpmlService.parseOpml(fileContent);
          
          if (feeds.isNotEmpty) {
            await _showImportPreviewDialog(feeds);
          } else {
            _showErrorDialog('No feeds found in the OPML file.');
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Error importing OPML file: $e');
    }
  }

  Future<void> _showImportPreviewDialog(List<RSSFeed> feeds) async {
    final selectedFeeds = List<bool>.filled(feeds.length, true);
    bool isImporting = false;
    
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing during import
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Import ${feeds.length} feeds'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: isImporting
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Importing feeds...'),
                        SizedBox(height: 8),
                        Text('Please wait while we add your feeds.',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                selectedFeeds.fillRange(0, selectedFeeds.length, true);
                              });
                            },
                            child: const Text('Select All'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                selectedFeeds.fillRange(0, selectedFeeds.length, false);
                              });
                            },
                            child: const Text('Select None'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: feeds.length,
                          itemBuilder: (context, index) {
                            final feed = feeds[index];
                            return CheckboxListTile(
                              title: Text(feed.title),
                              subtitle: Text(feed.url),
                              value: selectedFeeds[index],
                              onChanged: (value) {
                                setState(() {
                                  selectedFeeds[index] = value ?? false;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: isImporting
              ? [] // Hide buttons during import
              : [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        isImporting = true;
                      });
                      
                      try {
                        await _importSelectedFeeds(feeds, selectedFeeds);
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        setState(() {
                          isImporting = false;
                        });
                        _showErrorDialog('Error importing feeds: $e');
                      }
                    },
                    child: const Text('Import Selected'),
                  ),
                ],
        ),
      ),
    );
  }

  Future<void> _importSelectedFeeds(List<RSSFeed> feeds, List<bool> selectedFeeds) async {
    int importedCount = 0;
    int failedCount = 0;
    final feedProvider = context.read<FeedProvider>();
    
    for (int i = 0; i < feeds.length; i++) {
      if (selectedFeeds[i]) {
        try {
          final success = await feedProvider.addFeed(feeds[i].url);
          if (success) {
            importedCount++;
          } else {
            failedCount++;
          }
        } catch (e) {
          failedCount++;
          print('Failed to import feed ${feeds[i].title}: $e');
        }
      }
    }
    
    if (mounted) {
      String message;
      Color backgroundColor;
      
      if (failedCount == 0) {
        message = 'Successfully imported $importedCount feeds';
        backgroundColor = Colors.green;
      } else if (importedCount == 0) {
        message = 'Failed to import any feeds';
        backgroundColor = Colors.red;
      } else {
        message = 'Imported $importedCount feeds, $failedCount failed';
        backgroundColor = Colors.orange;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _exportOpmlFile() async {
    try {
      final feedProvider = context.read<FeedProvider>();
      final feeds = feedProvider.feeds;
      final categories = feedProvider.categories;
      
      if (feeds.isEmpty) {
        _showErrorDialog('No feeds to export.');
        return;
      }
      
      final opmlContent = OpmlService.generateOpml(feeds, categories);
      
      // Show export options dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export OPML'),
          content: const Text('Choose how you want to export your feeds:'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _shareOpmlFile(opmlContent);
              },
              child: const Text('Share'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _saveOpmlFile(opmlContent, 'freead_feeds_${DateTime.now().millisecondsSinceEpoch}.opml');
              },
              child: const Text('Save File'),
            ),
          ],
        ),
      );
      
    } catch (e) {
      _showErrorDialog('Error exporting OPML file: $e');
    }
  }

  Future<void> _shareOpmlFile(String content) async {
    try {
      // Create a temporary file for sharing
      final tempDir = Directory.systemTemp;
      final fileName = 'freead_feeds_${DateTime.now().millisecondsSinceEpoch}.opml';
      final file = File(path.join(tempDir.path, fileName));
      
      await file.writeAsString(content);
      
      await Share.shareXFiles([XFile(file.path)], text: 'RSS Feeds exported from FreeAd');
      
    } catch (e) {
      _showErrorDialog('Error sharing file: $e');
    }
  }

  Future<void> _saveOpmlFile(String content, String fileName) async {
    try {
      // Convert string content to bytes
      final bytes = utf8.encode(content);
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save OPML File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['opml'],
        bytes: bytes,
      );
      
      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OPML file exported successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _showErrorDialog('Error saving file: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFeedDialog() async {
    showDialog(
      context: context,
      builder: (context) => const _AddFeedDialog(),
    );
  }

  Future<void> _showEditFeedDialog(RSSFeed feed) async {
    showDialog(
      context: context,
      builder: (context) => EditFeedDialog(feed: feed),
    );
  }

  Future<void> _toggleFeedStatus(RSSFeed feed, bool isActive) async {
    final updatedFeed = feed.copyWith(isActive: isActive);
    final success = await context.read<FeedProvider>().updateFeed(updatedFeed);
    
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update feed: ${context.read<FeedProvider>().error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshFeed(RSSFeed feed) async {
    final success = await context.read<FeedProvider>().refreshFeed(feed.id);
    
    if (success) {
      // Also refresh articles for this feed
      context.read<ArticleProvider>().refreshFeedArticles(feed.id, feed.url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feed refreshed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh feed: ${context.read<FeedProvider>().error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmation(RSSFeed feed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Feed'),
        content: Text('Are you sure you want to delete "${feed.title}"?\n\nThis will also remove all articles from this feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await context.read<FeedProvider>().deleteFeed(feed.id);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feed deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh articles after deleting feed
        context.read<ArticleProvider>().loadArticles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete feed: ${context.read<FeedProvider>().error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class EditFeedDialog extends StatefulWidget {
  final RSSFeed feed;
  
  const EditFeedDialog({super.key, required this.feed});

  @override
  State<EditFeedDialog> createState() => _EditFeedDialogState();
}

class _EditFeedDialogState extends State<EditFeedDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late String _selectedCategory;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.feed.title);
    _descriptionController = TextEditingController(text: widget.feed.description);
    _selectedCategory = widget.feed.categoryId ?? 'general';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Feed'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Consumer<FeedProvider>(
              builder: (context, feedProvider, child) {
                // Ensure selectedCategory exists in the available categories
                if (!feedProvider.categories.any((cat) => cat.id == _selectedCategory)) {
                  _selectedCategory = feedProvider.categories.isNotEmpty ? feedProvider.categories.first.id : 'general';
                }
                
                return DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: feedProvider.categories.map((category) {
                    return DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateFeed,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update'),
        ),
      ],
    );
  }

  Future<void> _updateFeed() async {
    setState(() => _isLoading = true);

    final updatedFeed = widget.feed.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      categoryId: _selectedCategory,
    );

    final success = await context.read<FeedProvider>().updateFeed(updatedFeed);

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feed updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update feed: ${context.read<FeedProvider>().error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _AddFeedDialog extends StatefulWidget {
  const _AddFeedDialog();

  @override
  State<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<_AddFeedDialog> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add RSS Feed'),
      content: Form(
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
            ),
          ],
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

    final success = await context.read<FeedProvider>().addFeed(_urlController.text.trim());

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feed added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add feed: ${context.read<FeedProvider>().error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
