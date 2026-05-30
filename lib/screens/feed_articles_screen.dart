import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../widgets/article_list_widget.dart';
import '../widgets/futuristic_widgets.dart';

class FeedArticlesScreen extends StatefulWidget {
  final String feedId;
  final String feedTitle;

  const FeedArticlesScreen({super.key, required this.feedId, required this.feedTitle});

  @override
  State<FeedArticlesScreen> createState() => _FeedArticlesScreenState();
}

class _FeedArticlesScreenState extends State<FeedArticlesScreen> {
  late Future<List<Article>> _articlesFuture;

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  void _loadArticles() {
    setState(() {
      _articlesFuture = context.read<ArticleProvider>().getArticlesByFeed(widget.feedId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FuturisticAppBar(
        title: widget.feedTitle,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<Article>>(
        future: _articlesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final articles = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: () async {
              await context.read<ArticleProvider>().refreshAllArticles();
              _loadArticles();
            },
            child: ArticleListWidget(
              articles: articles,
              title: widget.feedTitle,
            ),
          );
        },
      ),
    );
  }
}
