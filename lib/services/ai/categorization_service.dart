import 'dart:convert';

import '../../models/category.dart';
import '../../models/rss_feed.dart';
import '../../utils/app_logger.dart';
import 'ai_models.dart';
import 'ai_service.dart';

/// Where a [CategorySuggestion] came from.
enum CategorySource {
  /// Offline keyword + known-domain heuristics.
  quick,

  /// A batched model call.
  ai,
}

/// One proposed category change for a feed.
class CategorySuggestion {
  const CategorySuggestion({
    required this.feedId,
    required this.currentCategoryId,
    required this.suggestedCategoryId,
    this.newCategoryName,
    this.confidence = 0.5,
    this.source = CategorySource.quick,
  });

  final String feedId;
  final String? currentCategoryId;

  /// An id that exists in the category list passed in (or [kFallbackCategoryId]
  /// when [newCategoryName] is set).
  final String suggestedCategoryId;

  /// Display name of a category the model wants to create, or null.
  final String? newCategoryName;

  /// 0.0 - 1.0.
  final double confidence;
  final CategorySource source;

  /// True when applying this suggestion would actually change something.
  bool get isChange =>
      newCategoryName != null || suggestedCategoryId != currentCategoryId;

  CategorySuggestion copyWith({
    String? suggestedCategoryId,
    String? newCategoryName,
    double? confidence,
    CategorySource? source,
    bool clearNewCategory = false,
  }) {
    return CategorySuggestion(
      feedId: feedId,
      currentCategoryId: currentCategoryId,
      suggestedCategoryId: suggestedCategoryId ?? this.suggestedCategoryId,
      newCategoryName: clearNewCategory
          ? null
          : (newCategoryName ?? this.newCategoryName),
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }

  @override
  String toString() =>
      'CategorySuggestion($feedId -> ${newCategoryName ?? suggestedCategoryId}, '
      '${source.name}, ${confidence.toStringAsFixed(2)})';
}

/// Category used when nothing matches.
const String kFallbackCategoryId = 'general';

/// Alias kept for the callers written against the Phase 1A stopgap file.
const String kDefaultCategoryId = kFallbackCategoryId;

/// Category names / synonyms as they appear in OPML folders and `category`
/// attributes, mapped to the default category ids.
const Map<String, String> categoryAliases = <String, String>{
  'tech': 'technology',
  'technology': 'technology',
  'gadgets': 'technology',
  'hardware': 'technology',
  'programming': 'programming',
  'development': 'programming',
  'developers': 'programming',
  'coding': 'programming',
  'software': 'programming',
  'engineering': 'programming',
  'news': 'news',
  'world': 'news',
  'politics': 'news',
  'general': 'general',
  'uncategorized': 'general',
  'business': 'business',
  'finance': 'business',
  'money': 'business',
  'economy': 'business',
  'markets': 'business',
  'science': 'science',
  'space': 'science',
  'research': 'science',
  'sport': 'sports',
  'sports': 'sports',
  'entertainment': 'entertainment',
  'movies': 'entertainment',
  'film': 'entertainment',
  'tv': 'entertainment',
  'music': 'entertainment',
  'games': 'gaming',
  'gaming': 'gaming',
  'health': 'health',
  'fitness': 'health',
  'medicine': 'health',
  'design': 'culture',
  'art': 'culture',
  'culture': 'culture',
  'architecture': 'culture',
  'lifestyle': 'lifestyle',
  'food': 'lifestyle',
  'travel': 'lifestyle',
  'cooking': 'lifestyle',
};

/// Maps an OPML folder / `category` attribute to a category id, or null when
/// the name is not a known synonym.
String? categoryIdForName(String? name) {
  if (name == null) return null;
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  return categoryAliases[key];
}

// =============================================================================
// Quick (offline) categorisation
// =============================================================================

/// Best category id for [feed], chosen from [categories].
///
/// Known domains win outright; otherwise weighted keyword matches on the feed
/// title, description and URL decide. Ties fall back to `general`.
String quickCategorizeOne(RSSFeed feed, List<Category> categories) {
  final available = <String>{for (final category in categories) category.id};
  final fallback = available.contains(kFallbackCategoryId)
      ? kFallbackCategoryId
      : (categories.isNotEmpty ? categories.first.id : kFallbackCategoryId);

  final uri = Uri.tryParse(feed.url.trim());
  final siteUri = Uri.tryParse(feed.siteUrl?.trim() ?? '');
  final host = _hostOf(uri) ?? _hostOf(siteUri) ?? '';
  final path = '${uri?.path ?? ''} ${siteUri?.path ?? ''}'.toLowerCase();

  final domainHit = _categoryForDomain(host, path);
  if (domainHit != null && available.contains(domainHit)) return domainHit;

  final title = _normalize(feed.title);
  final description = _normalize(feed.description);
  final urlText = _normalize('$host $path');

  final scores = <String, int>{};
  _keywordCategories.forEach((categoryId, keywords) {
    if (!available.contains(categoryId)) return;
    var score = 0;
    for (final keyword in keywords) {
      if (_containsWord(title, keyword)) score += 3;
      if (_containsWord(description, keyword)) score += 2;
      if (_containsWord(urlText, keyword)) score += 2;
    }
    if (score > 0) scores[categoryId] = score;
  });

  // A category whose own name appears in the feed title is a strong signal,
  // and it is the only way user-created categories can ever match.
  for (final category in categories) {
    final name = _normalize(category.name).trim().split(' ').first;
    if (name.length < 4) continue;
    if (_containsWord(title, name)) {
      scores.update(category.id, (score) => score + 4, ifAbsent: () => 4);
    }
  }

  if (scores.isEmpty) return fallback;

  var bestId = fallback;
  var bestScore = 0;
  var tied = false;
  scores.forEach((categoryId, score) {
    if (score > bestScore) {
      bestScore = score;
      bestId = categoryId;
      tied = false;
    } else if (score == bestScore) {
      tied = true;
    }
  });

  if (bestScore <= 0 || tied) return fallback;
  return bestId;
}

/// Quick categorisation for many feeds: `feedId -> categoryId`.
Map<String, String> quickCategorize(
  List<RSSFeed> feeds,
  List<Category> categories,
) {
  return {
    for (final feed in feeds) feed.id: quickCategorizeOne(feed, categories),
  };
}

String? _hostOf(Uri? uri) {
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _normalize(String input) {
  final lower = input.toLowerCase();
  final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9+#]+'), ' ');
  return ' ${cleaned.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
}

bool _containsWord(String normalizedHaystack, String keyword) =>
    normalizedHaystack.contains(' $keyword ');

/// Domain lookup, longest suffix wins. BBC is split by URL path, and feed
/// proxies (FeedBurner and friends) are resolved through the path's brand.
String? _categoryForDomain(String host, String path) {
  if (host.isEmpty) return null;

  if (host.contains('bbc.co.uk') ||
      host.contains('bbci.co.uk') ||
      host.contains('bbc.com')) {
    return path.contains('sport') ? 'sports' : 'news';
  }
  if (host.contains('indiatimes.com')) {
    if (path.contains('sport')) return 'sports';
    if (path.contains('tech')) return 'technology';
    if (host.startsWith('economictimes')) return 'business';
    return 'news';
  }
  if (host.endsWith('reddit.com')) {
    // /r/<subreddit>[/...] - treat the subreddit as a category name.
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final index = segments.indexOf('r');
    if (index != -1 && index + 1 < segments.length) {
      final alias = categoryIdForName(segments[index + 1]);
      if (alias != null) return alias;
    }
    return null;
  }

  String? best;
  var bestLength = 0;
  _domainCategories.forEach((domain, categoryId) {
    if (host == domain || host.endsWith('.$domain')) {
      if (domain.length > bestLength) {
        bestLength = domain.length;
        best = categoryId;
      }
    }
  });
  if (best != null) return best;

  if (_feedProxyHosts.any((proxy) => host.endsWith(proxy))) {
    for (final segment in path.split('/')) {
      final brand = _brandCategories[segment.trim().toLowerCase()];
      if (brand != null) return brand;
    }
  }
  return null;
}

/// Hosts that proxy someone else's feed; the brand lives in the path.
const List<String> _feedProxyHosts = <String>[
  'feedburner.com',
  'feedpress.me',
  'feedpress.com',
  'rsshub.app',
];

/// Brand label (`ign`, `techcrunch`, ...) -> category, derived from
/// [_domainCategories]. Ambiguous or generic labels are skipped.
final Map<String, String> _brandCategories = () {
  const skip = <String>{
    'co',
    'com',
    'org',
    'net',
    'www',
    'blog',
    'feeds',
    'news',
    'go',
    'dev',
    'health',
    'science',
  };
  final map = <String, String>{};
  for (final entry in _domainCategories.entries) {
    final labels = entry.key.split('.');
    if (labels.length < 2) continue;
    final brand = labels[labels.length - 2];
    if (brand.length <= 2 || skip.contains(brand)) continue;
    map.putIfAbsent(brand, () => entry.value);
  }
  return map;
}();

/// Known feed/site domains and the category they belong to.
const Map<String, String> _domainCategories = <String, String>{
  // --- technology ---
  'techcrunch.com': 'technology',
  'theverge.com': 'technology',
  'arstechnica.com': 'technology',
  'feeds.arstechnica.com': 'technology',
  'wired.com': 'technology',
  'engadget.com': 'technology',
  '9to5mac.com': 'technology',
  '9to5google.com': 'technology',
  'macrumors.com': 'technology',
  'androidpolice.com': 'technology',
  'androidauthority.com': 'technology',
  'androidcentral.com': 'technology',
  'xda-developers.com': 'technology',
  'gizmodo.com': 'technology',
  'cnet.com': 'technology',
  'zdnet.com': 'technology',
  'thenextweb.com': 'technology',
  'venturebeat.com': 'technology',
  'tomshardware.com': 'technology',
  'anandtech.com': 'technology',
  'mashable.com': 'technology',
  'digitaltrends.com': 'technology',
  'theregister.com': 'technology',
  'slashdot.org': 'technology',
  'techradar.com': 'technology',
  'technologyreview.com': 'technology',

  // --- programming ---
  'hnrss.org': 'programming',
  'news.ycombinator.com': 'programming',
  'ycombinator.com': 'programming',
  'lobste.rs': 'programming',
  'dev.to': 'programming',
  'github.blog': 'programming',
  'github.com': 'programming',
  'css-tricks.com': 'programming',
  'smashingmagazine.com': 'programming',
  'stackoverflow.blog': 'programming',
  'martinfowler.com': 'programming',
  'infoq.com': 'programming',
  'hashnode.com': 'programming',
  'hashnode.dev': 'programming',
  'overreacted.io': 'programming',
  'joelonsoftware.com': 'programming',
  'jvns.ca': 'programming',
  'realpython.com': 'programming',
  'kubernetes.io': 'programming',
  'blog.rust-lang.org': 'programming',
  'go.dev': 'programming',
  'raywenderlich.com': 'programming',
  'freecodecamp.org': 'programming',

  // --- news ---
  'npr.org': 'news',
  'feeds.npr.org': 'news',
  'theguardian.com': 'news',
  'nytimes.com': 'news',
  'reuters.com': 'news',
  'aljazeera.com': 'news',
  'cnn.com': 'news',
  'ndtv.com': 'news',
  'thehindu.com': 'news',
  'indianexpress.com': 'news',
  'hindustantimes.com': 'news',
  'washingtonpost.com': 'news',
  'apnews.com': 'news',
  'abcnews.go.com': 'news',
  'cbsnews.com': 'news',
  'nbcnews.com': 'news',
  'dw.com': 'news',
  'france24.com': 'news',
  'politico.com': 'news',
  'thehill.com': 'news',
  'usatoday.com': 'news',
  'latimes.com': 'news',

  // --- business ---
  'bloomberg.com': 'business',
  'cnbc.com': 'business',
  'ft.com': 'business',
  'wsj.com': 'business',
  'economist.com': 'business',
  'forbes.com': 'business',
  'businessinsider.com': 'business',
  'marketwatch.com': 'business',
  'fortune.com': 'business',
  'hbr.org': 'business',
  'seekingalpha.com': 'business',
  'moneycontrol.com': 'business',
  'livemint.com': 'business',
  'coindesk.com': 'business',

  // --- sports ---
  'espn.com': 'sports',
  'espn.co.uk': 'sports',
  'skysports.com': 'sports',
  'goal.com': 'sports',
  'nba.com': 'sports',
  'nfl.com': 'sports',
  'mlb.com': 'sports',
  'cricbuzz.com': 'sports',
  'espncricinfo.com': 'sports',
  'bleacherreport.com': 'sports',
  'theathletic.com': 'sports',
  'formula1.com': 'sports',
  'uefa.com': 'sports',
  'fifa.com': 'sports',

  // --- entertainment ---
  'variety.com': 'entertainment',
  'hollywoodreporter.com': 'entertainment',
  'deadline.com': 'entertainment',
  'ew.com': 'entertainment',
  'rollingstone.com': 'entertainment',
  'billboard.com': 'entertainment',
  'pitchfork.com': 'entertainment',
  'avclub.com': 'entertainment',
  'indiewire.com': 'entertainment',
  'collider.com': 'entertainment',
  'screenrant.com': 'entertainment',

  // --- gaming ---
  'ign.com': 'gaming',
  'polygon.com': 'gaming',
  'kotaku.com': 'gaming',
  'gamespot.com': 'gaming',
  'pcgamer.com': 'gaming',
  'eurogamer.net': 'gaming',
  'rockpapershotgun.com': 'gaming',
  'gamesradar.com': 'gaming',
  'destructoid.com': 'gaming',
  'nintendolife.com': 'gaming',
  'vg247.com': 'gaming',

  // --- science ---
  'nasa.gov': 'science',
  'sciencedaily.com': 'science',
  'quantamagazine.org': 'science',
  'nature.com': 'science',
  'newscientist.com': 'science',
  'phys.org': 'science',
  'science.org': 'science',
  'scientificamerican.com': 'science',
  'livescience.com': 'science',
  'space.com': 'science',
  'eurekalert.org': 'science',
  'arxiv.org': 'science',
  'esa.int': 'science',

  // --- health ---
  'webmd.com': 'health',
  'healthline.com': 'health',
  'medicalnewstoday.com': 'health',
  'health.harvard.edu': 'health',
  'mayoclinic.org': 'health',
  'nih.gov': 'health',
  'statnews.com': 'health',
  'medscape.com': 'health',

  // --- art & design ---
  'dezeen.com': 'culture',
  'designboom.com': 'culture',
  'core77.com': 'culture',
  'archdaily.com': 'culture',
  'thisiscolossal.com': 'culture',
  'colossal.com': 'culture',
  'itsnicethat.com': 'culture',
  'creativebloq.com': 'culture',
  'design-milk.com': 'culture',
  'artnews.com': 'culture',
  'hyperallergic.com': 'culture',

  // --- lifestyle ---
  'lifehacker.com': 'lifestyle',
  'seriouseats.com': 'lifestyle',
  'bonappetit.com': 'lifestyle',
  'lonelyplanet.com': 'lifestyle',
  'epicurious.com': 'lifestyle',
  'thekitchn.com': 'lifestyle',
  'apartmenttherapy.com': 'lifestyle',
  'nomadicmatt.com': 'lifestyle',
  'food52.com': 'lifestyle',
  'atlasobscura.com': 'lifestyle',
};

/// Keyword lists per category, matched on whole words.
const Map<String, List<String>> _keywordCategories = <String, List<String>>{
  'technology': [
    'tech',
    'technology',
    'gadget',
    'gadgets',
    'smartphone',
    'smartphones',
    'android',
    'ios',
    'iphone',
    'ipad',
    'macos',
    'apple',
    'samsung',
    'microsoft',
    'windows',
    'hardware',
    'laptop',
    'laptops',
    'cpu',
    'gpu',
    'semiconductor',
    'chip',
    'chips',
    'ai',
    'artificial intelligence',
    'machine learning',
    'robotics',
    'drone',
    'drones',
    'cybersecurity',
    'electronics',
    'telecom',
    '5g',
    'cloud computing',
    'saas',
    'silicon',
    'computing',
  ],
  'programming': [
    'programming',
    'developer',
    'developers',
    'software',
    'coding',
    'code',
    'devops',
    'javascript',
    'typescript',
    'python',
    'rust',
    'golang',
    'java',
    'kotlin',
    'swift',
    'c++',
    'php',
    'ruby',
    'react',
    'angular',
    'vue',
    'node',
    'frontend',
    'backend',
    'fullstack',
    'web development',
    'open source',
    'git',
    'github',
    'linux',
    'kubernetes',
    'docker',
    'database',
    'api',
    'compiler',
    'algorithms',
    'hacker news',
    'css',
    'html',
    'sql',
    'engineering blog',
    'flutter',
    'dart',
    'web dev',
    'software engineering',
  ],
  'news': [
    'news',
    'world',
    'politics',
    'breaking',
    'headlines',
    'current affairs',
    'national',
    'international',
    'government',
    'election',
    'elections',
    'policy',
    'war',
    'diplomacy',
    'journalism',
    'herald',
    'tribune',
    'gazette',
    'press',
    'daily news',
    'top stories',
  ],
  'business': [
    'business',
    'finance',
    'financial',
    'economy',
    'economic',
    'market',
    'markets',
    'stocks',
    'stock',
    'investing',
    'investment',
    'startup',
    'startups',
    'venture',
    'entrepreneur',
    'money',
    'banking',
    'trading',
    'crypto',
    'cryptocurrency',
    'bitcoin',
    'fintech',
    'wall street',
    'earnings',
    'ipo',
    'commerce',
  ],
  'sports': [
    'sport',
    'sports',
    'football',
    'soccer',
    'cricket',
    'basketball',
    'baseball',
    'tennis',
    'golf',
    'hockey',
    'nfl',
    'nba',
    'mlb',
    'nhl',
    'ufc',
    'mma',
    'boxing',
    'olympics',
    'formula 1',
    'f1',
    'motogp',
    'athletics',
    'premier league',
    'fifa',
    'rugby',
    'badminton',
    'wrestling',
    'scores',
  ],
  'entertainment': [
    'entertainment',
    'movie',
    'movies',
    'film',
    'films',
    'cinema',
    'tv',
    'television',
    'celebrity',
    'celebrities',
    'music',
    'box office',
    'hollywood',
    'bollywood',
    'streaming',
    'netflix',
    'showbiz',
    'trailer',
    'awards',
    'oscars',
    'anime',
    'comics',
    'tv show',
  ],
  'gaming': [
    'game',
    'games',
    'gaming',
    'gamer',
    'gamers',
    'videogame',
    'video games',
    'esports',
    'playstation',
    'xbox',
    'nintendo',
    'steam',
    'pc gaming',
    'rpg',
    'fps',
    'indie games',
    'console',
    'video game',
  ],
  'science': [
    'science',
    'scientific',
    'research',
    'physics',
    'chemistry',
    'biology',
    'astronomy',
    'space',
    'nasa',
    'cosmos',
    'universe',
    'climate',
    'environment',
    'geology',
    'neuroscience',
    'genetics',
    'quantum',
    'mathematics',
    'discovery',
    'scientists',
    'archaeology',
    'evolution',
  ],
  'health': [
    'health',
    'healthcare',
    'medical',
    'medicine',
    'wellness',
    'fitness',
    'nutrition',
    'diet',
    'mental health',
    'disease',
    'doctor',
    'doctors',
    'hospital',
    'pharma',
    'covid',
    'vaccine',
    'therapy',
    'psychology',
    'yoga',
    'workout',
  ],
  'culture': [
    'art',
    'arts',
    'design',
    'architecture',
    'designer',
    'illustration',
    'photography',
    'typography',
    'museum',
    'gallery',
    'creative',
    'interior',
    'graphic design',
    'industrial design',
    'craft',
    'aesthetics',
    'exhibition',
    'ux',
    'ui design',
  ],
  'lifestyle': [
    'lifestyle',
    'food',
    'recipe',
    'recipes',
    'cooking',
    'travel',
    'restaurant',
    'restaurants',
    'garden',
    'fashion',
    'style',
    'parenting',
    'productivity',
    'minimalism',
    'diy',
    'coffee',
    'wine',
    'beauty',
    'shopping',
    'hotel',
    'hotels',
    'destination',
  ],
};

// =============================================================================
// AI categorisation
// =============================================================================

/// Prompt used for AI categorisation. Kept here so tests can assert on it.
const String kCategorizationSystemPrompt =
    'You classify RSS feeds into categories for a reader app. '
    'Reply with a JSON array only - no prose, no explanations, no code fences.';

/// Asks the configured model to categorise [feeds], batching the request.
///
/// Any feed the model skips (or answers with an unknown category) falls back to
/// [quickCategorizeOne]. Never throws for parse problems; transport/auth errors
/// from [AiService] do propagate as [AiException].
Future<List<CategorySuggestion>> aiCategorize(
  List<RSSFeed> feeds,
  List<Category> categories, {
  required AiService ai,
  int batchSize = 60,
}) async {
  if (feeds.isEmpty) return const [];

  final quick = quickCategorize(feeds, categories);
  final validIds = <String>{for (final category in categories) category.id};
  final results = <String, CategorySuggestion>{};

  final limit = batchSize < 1 ? 1 : batchSize;
  for (var start = 0; start < feeds.length; start += limit) {
    final batch = feeds.sublist(
      start,
      start + limit > feeds.length ? feeds.length : start + limit,
    );
    try {
      final reply = await ai.chat(
        [AiMessage.user(buildCategorizationPrompt(batch, categories))],
        system: kCategorizationSystemPrompt,
        maxTokens: (batch.length * 48)
            .clamp(AiLimits.taskMaxTokens, 4096)
            .toInt(),
      );
      final parsed = parseCategorizationResponse(reply, batch, validIds, quick);
      results.addAll({for (final entry in parsed) entry.feedId: entry});
    } on AiException {
      rethrow;
    } catch (e, st) {
      AppLog.e('AI categorisation batch failed', e, st);
    }
  }

  return [
    for (final feed in feeds)
      results[feed.id] ??
          CategorySuggestion(
            feedId: feed.id,
            currentCategoryId: feed.categoryId,
            suggestedCategoryId: quick[feed.id] ?? kFallbackCategoryId,
            confidence: 0.4,
          ),
  ];
}

/// Builds the user prompt for one batch.
String buildCategorizationPrompt(
  List<RSSFeed> feeds,
  List<Category> categories,
) {
  final buffer = StringBuffer()
    ..writeln('Available categories (use the id, not the name):');
  for (final category in categories) {
    buffer.writeln('- ${category.id}: ${category.name}');
  }
  buffer
    ..writeln()
    ..writeln('Feeds to classify:')
    ..writeln();
  for (final feed in feeds) {
    final description = feed.description.trim().replaceAll(RegExp(r'\s+'), ' ');
    buffer.writeln(
      '- id: ${feed.id}\n'
      '  title: ${feed.title}\n'
      '  url: ${feed.url}\n'
      '  about: ${description.length > 160 ? '${description.substring(0, 160)}...' : description}',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'Reply with ONLY a JSON array, one object per feed, in this exact shape:',
    )
    ..writeln(
      '[{"id": "<feed id>", "category": "<category id from the list>", '
      '"newCategory": null, "confidence": 0.0}]',
    )
    ..writeln(
      'Set "newCategory" to a short display name only when none of the '
      'existing categories fit; in that case set "category" to '
      '"$kFallbackCategoryId". "confidence" is between 0 and 1.',
    );
  return buffer.toString();
}

/// Parses a model reply into suggestions, tolerating fences and stray prose.
List<CategorySuggestion> parseCategorizationResponse(
  String reply,
  List<RSSFeed> batch,
  Set<String> validCategoryIds,
  Map<String, String> quickResults,
) {
  final byId = {for (final feed in batch) feed.id: feed};
  final decoded = _decodeJsonArray(reply);
  if (decoded == null) {
    AppLog.w('AI categorisation reply was not JSON');
    return const [];
  }

  final suggestions = <CategorySuggestion>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final feedId = entry['id']?.toString();
    final feed = feedId == null ? null : byId[feedId];
    if (feed == null) continue;

    final rawNew = entry['newCategory'];
    var newCategoryName = rawNew is String ? rawNew.trim() : '';
    if (newCategoryName.toLowerCase() == 'null') newCategoryName = '';

    final rawCategory = entry['category']?.toString().trim().toLowerCase();
    final quickFallback = quickResults[feed.id] ?? kFallbackCategoryId;
    final categoryId =
        rawCategory != null && validCategoryIds.contains(rawCategory)
        ? rawCategory
        : (newCategoryName.isNotEmpty ? kFallbackCategoryId : quickFallback);

    final rawConfidence = entry['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : (double.tryParse(rawConfidence?.toString() ?? '') ?? 0.6).clamp(
            0.0,
            1.0,
          );

    suggestions.add(
      CategorySuggestion(
        feedId: feed.id,
        currentCategoryId: feed.categoryId,
        suggestedCategoryId: categoryId,
        newCategoryName: newCategoryName.isEmpty ? null : newCategoryName,
        confidence: confidence.toDouble(),
        source: CategorySource.ai,
      ),
    );
  }
  return suggestions;
}

List<dynamic>? _decodeJsonArray(String reply) {
  var text = reply.trim();
  if (text.isEmpty) return null;

  // Strip ``` / ```json fences.
  text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '').replaceAll('```', '');

  final start = text.indexOf('[');
  final end = text.lastIndexOf(']');
  if (start == -1 || end == -1 || end <= start) return null;

  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is List) return decoded;
  } catch (e) {
    AppLog.w('Could not decode AI categorisation JSON', e);
  }
  return null;
}

// =============================================================================
// Object wrapper
// =============================================================================

/// Object-oriented facade over the top-level categorisation functions, so
/// screens can hold one injectable dependency.
class CategorizationService {
  const CategorizationService();

  /// See [quickCategorizeOne].
  String categorizeOne(RSSFeed feed, List<Category> categories) =>
      quickCategorizeOne(feed, categories);

  /// See [quickCategorize].
  Map<String, String> categorizeAll(
    List<RSSFeed> feeds,
    List<Category> categories,
  ) => quickCategorize(feeds, categories);

  /// See [aiCategorize].
  Future<List<CategorySuggestion>> categorizeWithAi(
    List<RSSFeed> feeds,
    List<Category> categories, {
    required AiService ai,
    int batchSize = 60,
  }) => aiCategorize(feeds, categories, ai: ai, batchSize: batchSize);
}
