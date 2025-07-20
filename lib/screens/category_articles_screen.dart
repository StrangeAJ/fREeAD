import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../widgets/article_list_widget.dart';

class CategoryArticlesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryArticlesScreen({Key? key, required this.categoryId, required this.categoryName})
      : super(key: key);

  @override
  _CategoryArticlesScreenState createState() => _CategoryArticlesScreenState();
}

class _CategoryArticlesScreenState extends State<CategoryArticlesScreen> {
  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getArticlesByCategory(widget.categoryId),
      title: widget.categoryName,
      emptyMessage: 'No articles found in this category',
      onRefresh: () {
        // Refresh articles for this category
        context.read<ArticleProvider>().refreshArticles();
      },
    );
  }
}
