import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/feed_provider.dart';
import '../providers/article_provider.dart';
import '../services/opml_service.dart';
import '../widgets/futuristic_widgets.dart';

class FeedManagementScreen extends StatefulWidget {
  const FeedManagementScreen({super.key});

  @override
  State<FeedManagementScreen> createState() => _FeedManagementScreenState();
}

class _FeedManagementScreenState extends State<FeedManagementScreen> {
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
      appBar: FuturisticAppBar(
        title: 'Manage Feeds',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import OPML',
            onPressed: _importOpml,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Export OPML',
            onPressed: _exportOpml,
          ),
        ],
      ),
      body: Consumer<FeedProvider>(
        builder: (context, feedProvider, child) {
          if (feedProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final feeds = feedProvider.feeds;
          if (feeds.isEmpty) {
            return const Center(child: Text('No feeds to manage'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: feeds.length,
            itemBuilder: (context, index) {
              final feed = feeds[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: feed.iconUrl != null
                      ? CircleAvatar(backgroundImage: NetworkImage(feed.iconUrl!))
                      : const CircleAvatar(child: Icon(Icons.rss_feed)),
                  title: Text(feed.title),
                  subtitle: Text(feed.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    onPressed: () => _confirmDelete(context, feed.id, feed.title),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, String id, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Feed'),
        content: Text('Are you sure you want to delete "$title"? This will also remove all its articles, summaries, highlights, and notes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final feedProvider = context.read<FeedProvider>();
              final success = await feedProvider.deleteFeed(id);
              if (mounted) {
                _showMessage(success
                    ? '"$title" deleted successfully.'
                    : 'Failed to delete "$title".');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _importOpml() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final name = file.name.toLowerCase();
      if (!name.endsWith('.opml') && !name.endsWith('.xml')) {
        _showMessage('Please select an .opml or .xml file.');
        return;
      }
      if (file.bytes == null) {
        _showMessage('Could not read the selected file.');
        return;
      }

      final content = utf8.decode(file.bytes!, allowMalformed: true);
      final feeds = OpmlService.parseOpml(content);
      if (feeds.isEmpty) {
        _showMessage('No feeds found in the OPML file.');
        return;
      }

      if (!mounted) return;
      final counts = await context.read<FeedProvider>().importFeeds(feeds);
      _showMessage(
        'Imported ${counts['imported']} feed(s)'
        '${(counts['skipped'] ?? 0) > 0 ? ', skipped ${counts['skipped']} duplicate(s)' : ''}.',
      );
    } catch (e) {
      _showMessage('OPML import failed: $e');
    }
  }

  Future<void> _exportOpml() async {
    try {
      final feedProvider = context.read<FeedProvider>();
      if (feedProvider.feeds.isEmpty) {
        _showMessage('No feeds to export.');
        return;
      }

      final opml = OpmlService.generateOpml(
        feedProvider.feeds,
        Category.defaultCategories,
      );

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save OPML file',
        fileName: 'freead-feeds.opml',
        type: FileType.any,
        bytes: utf8.encode(opml),
      );
      if (path != null) {
        _showMessage('Exported ${feedProvider.feeds.length} feed(s).');
      }
    } catch (e) {
      _showMessage('OPML export failed: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
