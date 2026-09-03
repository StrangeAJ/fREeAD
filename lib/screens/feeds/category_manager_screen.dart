import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../providers/article_provider.dart';
import '../../providers/feed_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ui/ui.dart';

/// Colour swatches offered when creating or renaming a category.
const List<String> _kPalette = <String>[
  '#94A3B8',
  '#60A5FA',
  '#22D3EE',
  '#A78BFA',
  '#34D399',
  '#FBBF24',
  '#FB923C',
  '#F472B6',
  '#C084FC',
  '#F87171',
  '#E879F9',
  '#4ADE80',
];

/// Create, rename, recolour, reorder and delete categories.
class CategoryManagerScreen extends StatelessWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final FeedProvider feeds = context.watch<FeedProvider>();
    final List<Category> categories = feeds.categories;

    return AppScaffold(
      appBar: GlassAppBar(
        title: 'Categories',
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New category',
            onPressed: () => _edit(context, null),
          ),
        ],
      ),
      body: categories.isEmpty
          ? EmptyState(
              icon: Icons.folder_outlined,
              title: 'No categories',
              message: 'Create one to group your feeds.',
              primaryActionLabel: 'New category',
              primaryActionIcon: Icons.add_rounded,
              onPrimaryAction: () => _edit(context, null),
            )
          : ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(
                t.spaceL,
                t.spaceS,
                t.spaceL,
                t.space3xl * 2,
              ),
              itemCount: categories.length,
              onReorder: (int oldIndex, int newIndex) async {
                final List<String> ids = categories
                    .map((Category c) => c.id)
                    .toList();
                final int target = newIndex > oldIndex
                    ? newIndex - 1
                    : newIndex;
                ids.insert(target, ids.removeAt(oldIndex));
                await context.read<FeedProvider>().reorderCategories(ids);
              },
              itemBuilder: (BuildContext context, int index) {
                final Category category = categories[index];
                return _CategoryRow(
                  key: ValueKey<String>('category-${category.id}'),
                  category: category,
                  index: index,
                  feedCount: feeds.feedsByCategory[category.id]?.length ?? 0,
                  onEdit: () => _edit(context, category),
                  onDelete: () => _delete(context, category),
                );
              },
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  static Future<void> _edit(BuildContext context, Category? existing) async {
    final _CategoryDraft? draft = await showAppBottomSheet<_CategoryDraft>(
      context,
      title: existing == null ? 'New category' : 'Edit category',
      builder: (BuildContext context) => _CategoryEditor(existing: existing),
    );
    if (draft == null || !context.mounted) return;

    final FeedProvider feeds = context.read<FeedProvider>();
    if (existing == null) {
      final Category? created = await feeds.addCategory(
        draft.name,
        iconName: draft.iconName,
        color: draft.color,
      );
      if (!context.mounted) return;
      if (created == null) {
        AppSnackBar.error(context, 'Could not create that category.');
      } else {
        AppSnackBar.success(context, 'Created ${created.name}');
      }
      return;
    }

    final bool ok = await feeds.updateCategory(
      existing.copyWith(
        name: draft.name,
        iconName: draft.iconName,
        color: draft.color,
      ),
    );
    if (!context.mounted) return;
    if (ok) {
      AppSnackBar.success(context, 'Category updated');
    } else {
      AppSnackBar.error(context, 'Could not update that category.');
    }
  }

  static Future<void> _delete(BuildContext context, Category category) async {
    if (category.id == FeedProvider.defaultCategoryId) {
      AppSnackBar.show(context, 'General cannot be deleted.');
      return;
    }

    final bool confirmed = await showAppConfirm(
      context,
      'Delete ${category.name}?',
      'Its feeds and articles move to General. Nothing is lost.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final FeedProvider feeds = context.read<FeedProvider>();
    final ArticleProvider articles = context.read<ArticleProvider>();
    final bool ok = await feeds.deleteCategory(category.id);
    await articles.loadArticles();
    if (!context.mounted) return;
    if (ok) {
      AppSnackBar.success(context, 'Deleted ${category.name}');
    } else {
      AppSnackBar.error(context, 'Could not delete that category.');
    }
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.index,
    required this.feedCount,
    required this.onEdit,
    required this.onDelete,
  });

  final Category category;
  final int index;
  final int feedCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isGeneral = category.id == FeedProvider.defaultCategoryId;

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: t.spaceS),
      padding: EdgeInsets.symmetric(horizontal: t.spaceM, vertical: t.spaceS),
      onTap: onEdit,
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: category.colorValue.withValues(alpha: 0.16),
              borderRadius: t.borderRadiusS,
            ),
            child: Icon(category.icon, size: 18, color: category.colorValue),
          ),
          SizedBox(width: t.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(color: t.textPrimary),
                ),
                Text(
                  '$feedCount feed${feedCount == 1 ? '' : 's'}',
                  style: text.bodySmall?.copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: isGeneral ? 'General cannot be deleted' : 'Delete',
            color: t.textTertiary,
            onPressed: isGeneral ? null : onDelete,
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: EdgeInsets.only(left: t.spaceXs),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 20,
                color: t.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the editor sheet returns.
@immutable
class _CategoryDraft {
  const _CategoryDraft({
    required this.name,
    required this.iconName,
    required this.color,
  });

  final String name;
  final String iconName;
  final String color;
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.existing});

  final Category? existing;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String _iconName = widget.existing?.iconName ?? 'rss_feed';
  late String _color = widget.existing?.color ?? _kPalette.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final List<String> icons = Category.availableIconNames;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          SizedBox(height: t.spaceL),
          SectionHeader(
            label: 'Icon',
            padding: EdgeInsets.only(bottom: t.spaceS),
          ),
          Wrap(
            spacing: t.spaceS,
            runSpacing: t.spaceS,
            children: <Widget>[
              for (final String name in icons)
                _PickerTile(
                  selected: _iconName == name,
                  color: Category.parseColor(_color),
                  onTap: () => setState(() => _iconName = name),
                  child: Icon(
                    Category.iconForName(name),
                    size: 18,
                    color: _iconName == name
                        ? Category.parseColor(_color)
                        : t.textSecondary,
                  ),
                ),
            ],
          ),
          SizedBox(height: t.spaceL),
          SectionHeader(
            label: 'Colour',
            padding: EdgeInsets.only(bottom: t.spaceS),
          ),
          Wrap(
            spacing: t.spaceS,
            runSpacing: t.spaceS,
            children: <Widget>[
              for (final String hex in _kPalette)
                _PickerTile(
                  selected: _color == hex,
                  color: Category.parseColor(hex),
                  onTap: () => setState(() => _color = hex),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Category.parseColor(hex),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: t.spaceXl),
          GlowButton(
            label: widget.existing == null ? 'Create' : 'Save',
            expand: true,
            onPressed: () {
              final String name = _name.text.trim();
              if (name.isEmpty) {
                AppSnackBar.error(context, 'Give the category a name.');
                return;
              }
              Navigator.of(context).pop(
                _CategoryDraft(name: name, iconName: _iconName, color: _color),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: t.borderRadiusS,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : t.surface2,
          borderRadius: t.borderRadiusS,
          border: Border.all(color: selected ? color : t.hairline),
        ),
        child: child,
      ),
    );
  }
}
