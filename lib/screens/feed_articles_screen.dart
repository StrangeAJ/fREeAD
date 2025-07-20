import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../widgets/article_list_widget.dart';

class FeedArticlesScreen extends StatefulWidget {
  final String feedId;
  final String feedTitle;

  const FeedArticlesScreen({Key? key, required this.feedId, required this.feedTitle})
      : super(key: key);

  @override
  _FeedArticlesScreenState createState() => _FeedArticlesScreenState();
}

class _FeedArticlesScreenState extends State<FeedArticlesScreen> {
  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getArticlesByFeed(widget.feedId),
      title: widget.feedTitle,
      emptyMessage: 'No articles found in this feed',
      onRefresh: () {
        // Refresh the specific feed
        context.read<ArticleProvider>().refreshFeed(widget.feedId);
      },
    );
  }
}
