import 'package:flutter/material.dart';

/// One curated feed inside a [StarterPack].
@immutable
class StarterFeed {
  const StarterFeed(this.title, this.url);

  final String title;
  final String url;
}

/// A themed bundle of feeds offered on the empty states, so a fresh install has
/// something to read in two taps.
///
/// Every URL below was verified to answer 2xx (2026-09-02) before being
/// hardcoded, per the v3 plan.
@immutable
class StarterPack {
  const StarterPack({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.icon,
    required this.feeds,
  });

  final String id;
  final String name;

  /// Category the feeds land in; matches `Category.defaultCategories`.
  final String categoryId;
  final IconData icon;
  final List<StarterFeed> feeds;

  static const List<StarterPack> all = <StarterPack>[
    StarterPack(
      id: 'tech',
      name: 'Tech',
      categoryId: 'technology',
      icon: Icons.memory_rounded,
      feeds: <StarterFeed>[
        StarterFeed('The Verge', 'https://www.theverge.com/rss/index.xml'),
        StarterFeed(
          'Ars Technica',
          'https://feeds.arstechnica.com/arstechnica/index',
        ),
        StarterFeed('TechCrunch', 'https://techcrunch.com/feed/'),
        StarterFeed('Hacker News', 'https://hnrss.org/frontpage'),
        StarterFeed('Wired', 'https://www.wired.com/feed/rss'),
      ],
    ),
    StarterPack(
      id: 'news',
      name: 'News',
      categoryId: 'news',
      icon: Icons.public_rounded,
      feeds: <StarterFeed>[
        StarterFeed('BBC News', 'http://feeds.bbci.co.uk/news/rss.xml'),
        StarterFeed('NPR', 'https://feeds.npr.org/1001/rss.xml'),
        StarterFeed('The Guardian', 'https://www.theguardian.com/world/rss'),
        StarterFeed('Al Jazeera', 'https://www.aljazeera.com/xml/rss/all.xml'),
      ],
    ),
    StarterPack(
      id: 'science',
      name: 'Science',
      categoryId: 'science',
      icon: Icons.science_rounded,
      feeds: <StarterFeed>[
        StarterFeed('NASA', 'https://www.nasa.gov/news-release/feed/'),
        StarterFeed(
          'Science Daily',
          'https://www.sciencedaily.com/rss/all.xml',
        ),
        StarterFeed('Quanta Magazine', 'https://www.quantamagazine.org/feed/'),
      ],
    ),
    StarterPack(
      id: 'programming',
      name: 'Programming',
      categoryId: 'programming',
      icon: Icons.code_rounded,
      feeds: <StarterFeed>[
        StarterFeed('Dev.to', 'https://dev.to/feed'),
        StarterFeed('GitHub Blog', 'https://github.blog/feed/'),
        StarterFeed(
          'Smashing Magazine',
          'https://www.smashingmagazine.com/feed/',
        ),
        StarterFeed('CSS-Tricks', 'https://css-tricks.com/feed/'),
      ],
    ),
    StarterPack(
      id: 'sports',
      name: 'Sports',
      categoryId: 'sports',
      icon: Icons.sports_soccer_rounded,
      feeds: <StarterFeed>[
        StarterFeed('ESPN', 'https://www.espn.com/espn/rss/news'),
        StarterFeed('BBC Sport', 'http://feeds.bbci.co.uk/sport/rss.xml'),
        StarterFeed(
          'ESPNcricinfo',
          'https://www.espncricinfo.com/rss/content/story/feeds/0.xml',
        ),
      ],
    ),
    StarterPack(
      id: 'entertainment',
      name: 'Entertainment',
      categoryId: 'entertainment',
      icon: Icons.movie_rounded,
      feeds: <StarterFeed>[
        StarterFeed('Variety', 'https://variety.com/feed/'),
        StarterFeed('Polygon', 'https://www.polygon.com/rss/index.xml'),
        StarterFeed('IGN', 'https://feeds.feedburner.com/ign/all'),
      ],
    ),
    StarterPack(
      id: 'design',
      name: 'Design',
      categoryId: 'culture',
      icon: Icons.palette_rounded,
      feeds: <StarterFeed>[
        StarterFeed('Dezeen', 'https://www.dezeen.com/feed/'),
        StarterFeed('designboom', 'https://www.designboom.com/feed/'),
      ],
    ),
  ];
}
