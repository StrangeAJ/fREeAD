import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/article.dart';
import '../providers/article_provider.dart';
import '../widgets/article_list_widget.dart';

class StarredArticlesScreen extends StatelessWidget {
  const StarredArticlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getStarredArticles(),
      title: 'Starred Articles',
      emptyMessage: 'No starred articles yet',
      defaultViewType: ArticleViewType.card,
      onRefresh: () {
        context.read<ArticleProvider>().refreshArticles();
      },
    );
  }
}

class SavedArticlesScreen extends StatelessWidget {
  const SavedArticlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getSavedArticles(),
      title: 'Saved Articles',
      emptyMessage: 'No saved articles yet',
      defaultViewType: ArticleViewType.card,
      onRefresh: () {
        context.read<ArticleProvider>().refreshArticles();
      },
    );
  }
}

class UnreadArticlesScreen extends StatelessWidget {
  const UnreadArticlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getUnreadArticles(),
      title: 'Unread Articles',
      emptyMessage: 'All caught up! No unread articles.',
      defaultViewType: ArticleViewType.list,
      onRefresh: () {
        context.read<ArticleProvider>().refreshArticles();
      },
    );
  }
}

class RecentArticlesScreen extends StatelessWidget {
  final int days;

  const RecentArticlesScreen({super.key, this.days = 7});

  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getRecentArticles(days),
      title: 'Recent Articles (${days}d)',
      emptyMessage: 'No articles found in the last $days days',
      defaultViewType: ArticleViewType.card,
      onRefresh: () {
        context.read<ArticleProvider>().refreshArticles();
      },
    );
  }
}

class AllArticlesScreen extends StatelessWidget {
  const AllArticlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ArticleListWidget(
      articlesLoader: () => context.read<ArticleProvider>().getAllArticles(),
      title: 'All Articles',
      emptyMessage: 'No articles found',
      defaultViewType: ArticleViewType.list,
      onRefresh: () {
        context.read<ArticleProvider>().refreshArticles();
      },
    );
  }
}
