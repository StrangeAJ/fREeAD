import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/rss_feed.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../services/opml_service.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ui/ui.dart';

/// OPML import/export, shared by the Feeds tab and the manage screen.
abstract final class OpmlActions {
  /// Picks an .opml/.xml file and imports its feeds.
  static Future<void> import(BuildContext context) async {
    final FeedProvider feeds = context.read<FeedProvider>();
    final ArticleProvider articles = context.read<ArticleProvider>();

    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final PlatformFile file = picked.files.first;
      final String name = file.name.toLowerCase();
      if (!name.endsWith('.opml') && !name.endsWith('.xml')) {
        if (context.mounted) {
          AppSnackBar.error(context, 'Pick an .opml or .xml file.');
        }
        return;
      }
      if (file.bytes == null) {
        if (context.mounted) {
          AppSnackBar.error(context, 'Could not read that file.');
        }
        return;
      }

      final List<RSSFeed> parsed = OpmlService.parseOpml(
        utf8.decode(file.bytes!, allowMalformed: true),
      );
      if (parsed.isEmpty) {
        if (context.mounted) {
          AppSnackBar.error(context, 'No feeds found in that OPML file.');
        }
        return;
      }

      final Map<String, int> counts = await feeds.importFeeds(parsed);
      await articles.loadArticles();
      if (!context.mounted) return;

      final int imported = counts['imported'] ?? 0;
      final int skipped = counts['skipped'] ?? 0;
      AppSnackBar.success(
        context,
        'Imported $imported feed${imported == 1 ? '' : 's'}'
        '${skipped > 0 ? ', skipped $skipped duplicate'
                  '${skipped == 1 ? '' : 's'}' : ''}',
      );
    } catch (e) {
      AppLog.e('OPML import failed', e);
      if (context.mounted) {
        AppSnackBar.error(context, 'Import failed. The file may be malformed.');
      }
    }
  }

  /// Writes every subscription to an OPML file the user picks.
  static Future<void> export(BuildContext context) async {
    final FeedProvider feeds = context.read<FeedProvider>();
    if (feeds.feeds.isEmpty) {
      AppSnackBar.show(context, 'No feeds to export.');
      return;
    }

    try {
      final String opml = OpmlService.generateOpml(
        feeds.feeds,
        feeds.categories,
      );
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save OPML file',
        fileName: 'freead-feeds.opml',
        type: FileType.any,
        bytes: utf8.encode(opml),
      );
      if (!context.mounted || path == null) return;
      AppSnackBar.success(
        context,
        'Exported ${feeds.feeds.length} feed'
        '${feeds.feeds.length == 1 ? '' : 's'}',
      );
    } catch (e) {
      AppLog.e('OPML export failed', e);
      if (context.mounted) AppSnackBar.error(context, 'Export failed.');
    }
  }
}
