import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../providers/article_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/article/article_list.dart';
import '../../widgets/ui/ui.dart';

/// Which list the Saved tab is showing.
enum _SavedView { saved, starred }

/// The third tab: reading list and starred articles.
class SavedTab extends StatefulWidget {
  const SavedTab({super.key});

  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  _SavedView _view = _SavedView.saved;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    // Watched: the provider mutates these lists in place.
    final ArticleProvider articles = context.watch<ArticleProvider>();
    final List<Article> visible = _view == _SavedView.saved
        ? articles.savedArticles
        : articles.starredArticles;

    return AppScaffold(
      backgroundColor: Colors.transparent,
      appBar: const GlassAppBar(title: 'Saved', showBack: false),
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.spaceL,
              t.spaceS,
              t.spaceL,
              t.spaceM,
            ),
            child: SegmentedPills<_SavedView>(
              values: _SavedView.values,
              selected: _view,
              onChanged: (_SavedView v) => setState(() => _view = v),
              labelBuilder: (_SavedView v) =>
                  v == _SavedView.saved ? 'Saved' : 'Starred',
              iconBuilder: (_SavedView v) => v == _SavedView.saved
                  ? Icons.bookmark_rounded
                  : Icons.star_rounded,
            ),
          ),
          Expanded(
            child: ArticleListWidget(
              // Rebuilt (and re-keyed) whenever the view flips, so the list
              // never shows the other tab's rows for a frame.
              key: ValueKey<_SavedView>(_view),
              articles: visible,
              title: _view == _SavedView.saved ? 'Saved' : 'Starred',
              showFilter: false,
              groupByDate: false,
              onRefresh: () => articles.loadArticles(),
              emptyState: EmptyState(
                icon: _view == _SavedView.saved
                    ? Icons.bookmark_border_rounded
                    : Icons.star_border_rounded,
                title: _view == _SavedView.saved
                    ? 'Nothing saved yet'
                    : 'Nothing starred yet',
                message: _view == _SavedView.saved
                    ? 'Swipe an article left, or use its menu, to save it '
                          'for later.'
                    : 'Star the articles you want to keep coming back to.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
