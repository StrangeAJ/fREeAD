import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/article.dart';
import '../../providers/article_provider.dart';
import '../../screens/article_reading_screen.dart';
import '../ui/ui.dart';

/// Actions shared by every article row style and by the reader.
///
/// Nothing here caches an [Article]: each call looks the current instance up in
/// [ArticleProvider] by id, so an action always acts on fresh state.
abstract final class ArticleActions {
  /// Pushes the reader.
  static Future<void> open(BuildContext context, Article article) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArticleReadingScreen(article: article),
      ),
    );
  }

  static Future<void> openInBrowser(
    BuildContext context,
    Article article,
  ) async {
    final Uri? uri = Uri.tryParse(article.url);
    if (uri == null || article.url.trim().isEmpty) {
      AppSnackBar.error(context, 'This article has no link.');
      return;
    }
    try {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        AppSnackBar.error(context, 'Could not open the link.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, 'Could not open the link.');
      }
    }
  }

  static Future<void> share(BuildContext context, Article article) async {
    final String url = article.url.trim();
    final String text = url.isEmpty ? article.title : '${article.title}\n$url';
    try {
      await Share.share(text, subject: article.title);
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, 'Could not share this article.');
      }
    }
  }

  static Future<void> copyLink(BuildContext context, Article article) async {
    await Clipboard.setData(ClipboardData(text: article.url));
    if (context.mounted) AppSnackBar.success(context, 'Link copied');
  }

  static void toggleStar(BuildContext context, Article article) {
    context.read<ArticleProvider>().toggleStarred(article.id);
  }

  static void toggleSaved(BuildContext context, Article article) {
    context.read<ArticleProvider>().toggleSaved(article.id);
  }

  static Future<void> toggleRead(BuildContext context, Article article) {
    final ArticleProvider provider = context.read<ArticleProvider>();
    return article.isRead
        ? provider.markAsUnread(article.id)
        : provider.markAsRead(article.id);
  }

  /// Marks every article above [article] in [ordered] as read.
  static Future<void> markAboveAsRead(
    BuildContext context,
    Article article,
    List<Article> ordered,
  ) async {
    final ArticleProvider provider = context.read<ArticleProvider>();
    final int index = ordered.indexWhere((Article a) => a.id == article.id);
    if (index <= 0) return;
    var changed = 0;
    for (final Article above in ordered.take(index)) {
      if (above.isRead) continue;
      await provider.markAsRead(above.id);
      changed++;
    }
    if (context.mounted && changed > 0) {
      AppSnackBar.success(context, 'Marked $changed as read');
    }
  }

  /// The long-press menu. [ordered] backs "Mark all above as read".
  static Future<void> showMenu(
    BuildContext context,
    Article article, {
    List<Article> ordered = const <Article>[],
  }) async {
    final String? choice = await showAppMenuSheet<String>(
      context,
      title: article.title,
      options: <AppMenuOption<String>>[
        const AppMenuOption<String>(
          value: 'open',
          label: 'Open',
          icon: Icons.chrome_reader_mode_outlined,
        ),
        const AppMenuOption<String>(
          value: 'browser',
          label: 'Open in browser',
          icon: Icons.open_in_new_rounded,
        ),
        const AppMenuOption<String>(
          value: 'share',
          label: 'Share',
          icon: Icons.ios_share_rounded,
        ),
        AppMenuOption<String>(
          value: 'read',
          label: article.isRead ? 'Mark as unread' : 'Mark as read',
          icon: article.isRead
              ? Icons.mark_email_unread_outlined
              : Icons.mark_email_read_outlined,
        ),
        AppMenuOption<String>(
          value: 'save',
          label: article.isSaved ? 'Remove from saved' : 'Save',
          icon: article.isSaved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
        ),
        AppMenuOption<String>(
          value: 'star',
          label: article.isStarred ? 'Unstar' : 'Star',
          icon: article.isStarred
              ? Icons.star_rounded
              : Icons.star_border_rounded,
        ),
        const AppMenuOption<String>(
          value: 'copy',
          label: 'Copy link',
          icon: Icons.link_rounded,
        ),
        AppMenuOption<String>(
          value: 'above',
          label: 'Mark all above as read',
          icon: Icons.done_all_rounded,
          enabled: ordered.length > 1,
        ),
      ],
    );

    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'open':
        await open(context, article);
      case 'browser':
        await openInBrowser(context, article);
      case 'share':
        await share(context, article);
      case 'read':
        await toggleRead(context, article);
      case 'save':
        toggleSaved(context, article);
      case 'star':
        toggleStar(context, article);
      case 'copy':
        await copyLink(context, article);
      case 'above':
        await markAboveAsRead(context, article, ordered);
    }
  }
}
