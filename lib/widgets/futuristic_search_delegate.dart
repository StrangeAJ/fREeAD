import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/article_provider.dart';
import '../models/article.dart';
import '../screens/feed_articles_screen.dart';
import '../screens/article_reading_screen.dart';

class FuturisticSearchDelegate extends SearchDelegate<dynamic> {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    final articleProvider = Provider.of<ArticleProvider>(context, listen: false);
    final feedResults = feedProvider.feeds.where((feed) {
      final lower = query.toLowerCase();
      return feed.title.toLowerCase().contains(lower) || feed.url.toLowerCase().contains(lower);
    }).toList();

    return FutureBuilder<List<Article>>(
      future: articleProvider.searchArticles(query),
      builder: (context, snapshot) {
        final articleResults = snapshot.data ?? [];
        return ListView(
          children: [
            if (feedResults.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Feeds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ...feedResults.map((feed) => ListTile(
                    leading: const Icon(Icons.rss_feed),
                    title: Text(feed.title),
                    subtitle: Text(feed.url),
                    onTap: () {
                      close(context, null);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FeedArticlesScreen(
                            feedId: feed.id,
                            feedTitle: feed.title,
                          ),
                        ),
                      );
                    },
                  )),
            ],
            if (articleResults.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Articles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ...articleResults.map((article) => ListTile(
                    leading: const Icon(Icons.article),
                    title: Text(article.title),
                    subtitle: Text(article.feedId),
                    onTap: () {
                      close(context, null);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArticleReadingScreen(article: article),
                        ),
                      );
                    },
                  )),
            ],
            if (feedResults.isEmpty && articleResults.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'No results found for "${query}"',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // Show same as results for simplicity
    return buildResults(context);
  }
}
