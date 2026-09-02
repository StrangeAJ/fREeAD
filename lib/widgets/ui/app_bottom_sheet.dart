import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Shows the app's modal bottom sheet: surface 1, 28px top radius, drag
/// handle, keyboard-safe, scrollable.
///
/// * `expand: false` (default) - the sheet hugs its content and scrolls when it
///   would exceed 85% of the screen.
/// * `expand: true` - a full-height sheet (95%); the builder owns its own
///   scrolling (e.g. a `DraggableScrollableSheet` or a `Column` + `Expanded`).
///
/// ```dart
/// final choice = await showAppBottomSheet<String>(
///   context,
///   title: 'Sort by',
///   builder: (context) => Column(children: [...]),
/// );
/// ```
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool expand = false,
  List<Widget>? actions,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showHandle = true,
  EdgeInsetsGeometry? padding,
}) {
  final AppTokens t = context.tokens;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    backgroundColor: t.surface1,
    barrierColor: const Color(0xFF000000).withValues(alpha: 0.5),
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusL)),
    ),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (BuildContext sheetContext) => _AppSheetShell(
      title: title,
      actions: actions,
      expand: expand,
      showHandle: showHandle,
      padding: padding,
      child: Builder(builder: builder),
    ),
  );
}

/// One row in a [showAppMenuSheet] menu.
class AppMenuOption<T> {
  const AppMenuOption({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;

  /// Renders in the danger colour.
  final bool destructive;

  final bool enabled;
}

/// A long-press / overflow menu rendered as a bottom sheet. Returns the chosen
/// option's value, or null when dismissed.
///
/// ```dart
/// final action = await showAppMenuSheet<String>(context, title: article.title, options: [
///   AppMenuOption(value: 'share', label: 'Share', icon: Icons.ios_share_rounded),
///   AppMenuOption(value: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
/// ]);
/// ```
Future<T?> showAppMenuSheet<T>(
  BuildContext context, {
  required List<AppMenuOption<T>> options,
  String? title,
}) {
  return showAppBottomSheet<T>(
    context,
    title: title,
    padding: EdgeInsets.zero,
    builder: (BuildContext context) {
      final AppTokens t = context.tokens;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final AppMenuOption<T> option in options)
            ListTile(
              enabled: option.enabled,
              leading: option.icon == null
                  ? null
                  : Icon(
                      option.icon,
                      color: option.destructive ? t.danger : t.textSecondary,
                    ),
              title: Text(
                option.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: option.destructive ? t.danger : t.textPrimary,
                ),
              ),
              subtitle: option.subtitle == null ? null : Text(option.subtitle!),
              onTap: () => Navigator.of(context).pop(option.value),
            ),
          SizedBox(height: t.spaceS),
        ],
      );
    },
  );
}

class _AppSheetShell extends StatelessWidget {
  const _AppSheetShell({
    required this.child,
    required this.expand,
    required this.showHandle,
    this.title,
    this.actions,
    this.padding,
  });

  final Widget child;
  final bool expand;
  final bool showHandle;
  final String? title;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final MediaQueryData mq = MediaQuery.of(context);
    final double maxHeight = mq.size.height * (expand ? 0.95 : 0.85);

    final EdgeInsetsGeometry contentPadding =
        padding ?? EdgeInsets.fromLTRB(t.spaceL, 0, t.spaceL, t.spaceL);

    final Widget header = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showHandle)
          Padding(
            padding: EdgeInsets.only(top: t.spaceM, bottom: t.spaceS),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: t.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        if (title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.spaceL,
              showHandle ? t.spaceS : t.spaceL,
              t.spaceS,
              t.spaceM,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (actions != null) ...actions!,
              ],
            ),
          )
        else if (actions != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.spaceS),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions!,
            ),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: expand
            ? SizedBox(
                height: maxHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    header,
                    Expanded(
                      child: Padding(padding: contentPadding, child: child),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  header,
                  Flexible(
                    child: SingleChildScrollView(
                      padding: contentPadding,
                      child: child,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
