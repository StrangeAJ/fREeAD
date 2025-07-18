import 'package:xml/xml.dart';
import '../models/rss_feed.dart';
import '../models/category.dart';

class OpmlService {
  static List<RSSFeed> parseOpml(String opmlContent) {
    List<RSSFeed> feeds = [];
    
    try {
      final document = XmlDocument.parse(opmlContent);
      final outlines = document.findAllElements('outline');
      
      for (final outline in outlines) {
        final xmlUrl = outline.getAttribute('xmlUrl');
        final title = outline.getAttribute('title') ?? outline.getAttribute('text');
        final description = outline.getAttribute('description') ?? '';
        final category = outline.getAttribute('category') ?? 'general';
        
        if (xmlUrl != null && xmlUrl.isNotEmpty) {
          final feed = RSSFeed(
            id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + feeds.length.toString(),
            title: title ?? 'Untitled Feed',
            url: xmlUrl,
            description: description,
            imageUrl: null,
            categoryId: _mapCategoryName(category),
            dateAdded: DateTime.now(),
            lastUpdated: DateTime.now(),
            isActive: true,
          );
          feeds.add(feed);
        }
      }
    } catch (e) {
      print('Error parsing OPML: $e');
      throw Exception('Failed to parse OPML file: $e');
    }
    
    return feeds;
  }
  
  static String _mapCategoryName(String categoryName) {
    // Map common category names to our predefined categories
    final lowercaseName = categoryName.toLowerCase();
    
    switch (lowercaseName) {
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
      default:
        return 'general'; // Default to general category
    }
  }
  
  static String generateOpml(List<RSSFeed> feeds, List<Category> categories) {
    final builder = XmlBuilder();
    
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', nest: () {
      builder.attribute('version', '1.0');
      
      builder.element('head', nest: () {
        builder.element('title', nest: () {
          builder.text('FreeAd RSS Feeds');
        });
        builder.element('dateCreated', nest: () {
          builder.text(DateTime.now().toIso8601String());
        });
        builder.element('dateModified', nest: () {
          builder.text(DateTime.now().toIso8601String());
        });
      });
      
      builder.element('body', nest: () {
        // Group feeds by category
        final feedsByCategory = <String, List<RSSFeed>>{};
        for (final feed in feeds) {
          final categoryId = feed.categoryId ?? 'general';
          feedsByCategory.putIfAbsent(categoryId, () => []).add(feed);
        }
        
        // Create category folders
        for (final category in categories) {
          final categoryFeeds = feedsByCategory[category.id] ?? [];
          if (categoryFeeds.isNotEmpty) {
            builder.element('outline', nest: () {
              builder.attribute('text', category.name);
              builder.attribute('title', category.name);
              
              for (final feed in categoryFeeds) {
                builder.element('outline', nest: () {
                  builder.attribute('type', 'rss');
                  builder.attribute('text', feed.title);
                  builder.attribute('title', feed.title);
                  builder.attribute('xmlUrl', feed.url);
                  builder.attribute('htmlUrl', feed.url);
                  if (feed.description.isNotEmpty) {
                    builder.attribute('description', feed.description);
                  }
                  builder.attribute('category', category.name);
                });
              }
            });
          }
        }
      });
    });
    
    return builder.buildDocument().toXmlString(pretty: true);
  }
}
