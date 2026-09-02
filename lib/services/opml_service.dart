import 'package:xml/xml.dart';

import '../models/category.dart';
import '../models/rss_feed.dart';
import '../utils/app_logger.dart';
import 'ai/categorization_service.dart';
import 'rss/rss_service.dart';

/// Reads and writes OPML subscription lists.
class OpmlService {
  /// Parses [opmlContent] into feeds.
  ///
  /// Category resolution order:
  /// 1. the outline's own `category` attribute (legacy name map, kept stable
  ///    for existing users and `test/opml_service_test.dart`),
  /// 2. the enclosing folder outline's text,
  /// 3. offline quick categorisation of the feed itself.
  static List<RSSFeed> parseOpml(String opmlContent) {
    final feeds = <RSSFeed>[];

    try {
      final document = XmlDocument.parse(opmlContent);
      final outlines = document.findAllElements('outline');
      final now = DateTime.now();
      final seenUrls = <String>{};

      for (final outline in outlines) {
        final xmlUrl = outline.getAttribute('xmlUrl');
        if (xmlUrl == null || xmlUrl.trim().isEmpty) continue;
        final url = xmlUrl.trim();
        if (!seenUrls.add(url)) continue;

        final title =
            outline.getAttribute('title') ??
            outline.getAttribute('text') ??
            'Untitled Feed';
        final description = outline.getAttribute('description') ?? '';
        final htmlUrl = outline.getAttribute('htmlUrl');

        feeds.add(
          RSSFeed(
            id: RssService.feedIdFor(url),
            title: title,
            url: url,
            description: description,
            imageUrl: null,
            categoryId: _resolveCategory(
              outline: outline,
              title: title,
              description: description,
              url: url,
              siteUrl: htmlUrl,
            ),
            siteUrl: htmlUrl,
            dateAdded: now,
            lastUpdated: now,
            isActive: true,
          ),
        );
      }
    } catch (e) {
      AppLog.e('Error parsing OPML', e);
      throw Exception('Failed to parse OPML file: $e');
    }

    return feeds;
  }

  static String _resolveCategory({
    required XmlElement outline,
    required String title,
    required String description,
    required String url,
    String? siteUrl,
  }) {
    final explicit = outline.getAttribute('category');
    final mapped = mapCategoryName(explicit);
    if (mapped != null) return mapped;

    // Folder outlines wrap their feeds; use the folder label as a hint.
    final parent = outline.parentElement;
    if (parent != null && parent.name.local == 'outline') {
      final folder =
          parent.getAttribute('title') ?? parent.getAttribute('text');
      final fromFolder = mapCategoryName(folder);
      if (fromFolder != null) return fromFolder;
    }

    return quickCategorizeOne(
      RSSFeed(
        id: url,
        title: title,
        url: url,
        description: description,
        siteUrl: siteUrl,
        dateAdded: DateTime.now(),
      ),
      Category.defaultCategories,
    );
  }

  /// Maps an OPML category label onto one of the built-in category ids.
  ///
  /// Returns null when the label is unknown so callers can fall back to
  /// content based categorisation. The explicit cases below are the v2
  /// behaviour and are relied on by existing exports.
  static String? mapCategoryName(String? categoryName) {
    if (categoryName == null) return null;
    final name = categoryName.trim().toLowerCase();
    if (name.isEmpty) return null;

    switch (name) {
      case 'tech':
      case 'technology':
      case 'programming':
      case 'development':
        return 'technology';
      case 'news':
      case 'general':
      case 'world':
        return 'general';
      case 'sport':
      case 'sports':
        return 'sports';
      case 'entertainment':
      case 'movies':
      case 'tv':
        return 'entertainment';
      case 'business':
      case 'finance':
      case 'money':
        return 'business';
    }
    return categoryIdForName(name);
  }

  /// Serialises [feeds] into an OPML document, grouped by [categories].
  static String generateOpml(List<RSSFeed> feeds, List<Category> categories) {
    final builder = XmlBuilder();

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'opml',
      nest: () {
        builder.attribute('version', '1.0');

        builder.element(
          'head',
          nest: () {
            builder.element('title', nest: () => builder.text('FreeAd RSS Feeds'));
            builder.element(
              'dateCreated',
              nest: () => builder.text(DateTime.now().toIso8601String()),
            );
            builder.element(
              'dateModified',
              nest: () => builder.text(DateTime.now().toIso8601String()),
            );
          },
        );

        builder.element(
          'body',
          nest: () {
            final feedsByCategory = <String, List<RSSFeed>>{};
            for (final feed in feeds) {
              final categoryId = feed.categoryId ?? 'general';
              feedsByCategory.putIfAbsent(categoryId, () => []).add(feed);
            }

            final knownCategoryIds = categories.map((c) => c.id).toSet();
            for (final category in categories) {
              final categoryFeeds = feedsByCategory[category.id] ?? const [];
              if (categoryFeeds.isEmpty) continue;
              builder.element(
                'outline',
                nest: () {
                  builder.attribute('text', category.name);
                  builder.attribute('title', category.name);
                  for (final feed in categoryFeeds) {
                    _writeFeed(builder, feed, category.name);
                  }
                },
              );
            }

            // Feeds whose category is not in the provided list are exported
            // flat so nothing is silently dropped.
            for (final entry in feedsByCategory.entries) {
              if (knownCategoryIds.contains(entry.key)) continue;
              for (final feed in entry.value) {
                _writeFeed(builder, feed, null);
              }
            }
          },
        );
      },
    );

    return builder.buildDocument().toXmlString(pretty: true);
  }

  static void _writeFeed(XmlBuilder builder, RSSFeed feed, String? category) {
    builder.element(
      'outline',
      nest: () {
        builder.attribute('type', 'rss');
        builder.attribute('text', feed.title);
        builder.attribute('title', feed.title);
        builder.attribute('xmlUrl', feed.url);
        builder.attribute('htmlUrl', feed.siteUrl ?? feed.url);
        if (feed.description.isNotEmpty) {
          builder.attribute('description', feed.description);
        }
        if (category != null) builder.attribute('category', category);
      },
    );
  }
}
