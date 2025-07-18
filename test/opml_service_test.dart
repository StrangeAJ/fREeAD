import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/opml_service.dart';
import 'package:freead/models/rss_feed.dart';
import 'package:freead/models/category.dart';

void main() {
  group('OpmlService', () {
    test('should parse valid OPML content', () {
      const opmlContent = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <head>
    <title>Test Feeds</title>
  </head>
  <body>
    <outline text="Technology" title="Technology">
      <outline type="rss" text="TechCrunch" title="TechCrunch" 
               xmlUrl="https://feeds.feedburner.com/TechCrunch" 
               htmlUrl="https://techcrunch.com" 
               description="Technology news" 
               category="Technology"/>
    </outline>
    <outline type="rss" text="BBC News" title="BBC News" 
             xmlUrl="http://feeds.bbci.co.uk/news/rss.xml" 
             htmlUrl="https://www.bbc.com/news" 
             description="BBC News feed" 
             category="News"/>
  </body>
</opml>''';

      final feeds = OpmlService.parseOpml(opmlContent);
      
      expect(feeds.length, equals(2));
      expect(feeds[0].title, equals('TechCrunch'));
      expect(feeds[0].url, equals('https://feeds.feedburner.com/TechCrunch'));
      expect(feeds[0].description, equals('Technology news'));
      expect(feeds[0].categoryId, equals('technology'));
      
      expect(feeds[1].title, equals('BBC News'));
      expect(feeds[1].url, equals('http://feeds.bbci.co.uk/news/rss.xml'));
      expect(feeds[1].categoryId, equals('general'));
    });

    test('should handle feeds without categories', () {
      const opmlContent = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <body>
    <outline type="rss" text="Test Feed" title="Test Feed" 
             xmlUrl="https://example.com/feed.xml"/>
  </body>
</opml>''';

      final feeds = OpmlService.parseOpml(opmlContent);
      
      expect(feeds.length, equals(1));
      expect(feeds[0].categoryId, equals('general'));
    });

    test('should skip invalid feeds without xmlUrl', () {
      const opmlContent = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <body>
    <outline text="Invalid Feed" title="Invalid Feed" 
             htmlUrl="https://example.com"/>
    <outline type="rss" text="Valid Feed" title="Valid Feed" 
             xmlUrl="https://example.com/feed.xml"/>
  </body>
</opml>''';

      final feeds = OpmlService.parseOpml(opmlContent);
      
      expect(feeds.length, equals(1));
      expect(feeds[0].title, equals('Valid Feed'));
    });

    test('should generate valid OPML from feeds and categories', () {
      final categories = [
        Category(
          id: 'technology',
          name: 'Technology',
          description: 'Tech news',
          dateCreated: DateTime.now(),
          sortOrder: 0,
          isDefault: true,
        ),
        Category(
          id: 'general',
          name: 'General',
          description: 'General news',
          dateCreated: DateTime.now(),
          sortOrder: 1,
          isDefault: true,
        ),
      ];

      final feeds = [
        RSSFeed(
          id: '1',
          title: 'TechCrunch',
          url: 'https://feeds.feedburner.com/TechCrunch',
          description: 'Technology news',
          categoryId: 'technology',
          dateAdded: DateTime.now(),
          lastUpdated: DateTime.now(),
          isActive: true,
        ),
        RSSFeed(
          id: '2',
          title: 'BBC News',
          url: 'http://feeds.bbci.co.uk/news/rss.xml',
          description: 'BBC News feed',
          categoryId: 'general',
          dateAdded: DateTime.now(),
          lastUpdated: DateTime.now(),
          isActive: true,
        ),
      ];

      final opmlContent = OpmlService.generateOpml(feeds, categories);
      
      expect(opmlContent, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(opmlContent, contains('<opml version="1.0">'));
      expect(opmlContent, contains('TechCrunch'));
      expect(opmlContent, contains('BBC News'));
      expect(opmlContent, contains('Technology'));
      expect(opmlContent, contains('General'));
      expect(opmlContent, contains('https://feeds.feedburner.com/TechCrunch'));
      expect(opmlContent, contains('http://feeds.bbci.co.uk/news/rss.xml'));
    });

    test('should map category names correctly', () {
      const opmlContent = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <body>
    <outline type="rss" text="Tech Feed" xmlUrl="https://tech.com/feed.xml" category="programming"/>
    <outline type="rss" text="Sports Feed" xmlUrl="https://sport.com/feed.xml" category="sport"/>
    <outline type="rss" text="Finance Feed" xmlUrl="https://money.com/feed.xml" category="finance"/>
    <outline type="rss" text="Movies Feed" xmlUrl="https://movies.com/feed.xml" category="movies"/>
  </body>
</opml>''';

      final feeds = OpmlService.parseOpml(opmlContent);
      
      expect(feeds[0].categoryId, equals('technology'));
      expect(feeds[1].categoryId, equals('sports'));
      expect(feeds[2].categoryId, equals('business'));
      expect(feeds[3].categoryId, equals('entertainment'));
    });
  });
}
