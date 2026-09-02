import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import 'glow_button.dart';

/// The empty / error state used by every list in the app: a glyph inside a soft
/// accent disc, a title, a message and up to two actions.
///
/// ```dart
/// EmptyState(
///   icon: Icons.rss_feed_rounded,
///   title: 'No feeds yet',
///   message: 'Add your first feed to start reading.',
///   primaryActionLabel: 'Add feed',
///   onPrimaryAction: _addFeed,
/// )
/// ```
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.primaryActionIcon,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
    this.iconColor,
    this.padding,
  });

  final IconData icon;
  final String title;
  final String? message;

  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final IconData? primaryActionIcon;

  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Smaller disc + tighter spacing, for empty states inside a card.
  final bool compact;

  /// Overrides the accent (e.g. the danger colour for error states).
  final Color? iconColor;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = iconColor ?? t.accent;
    final double disc = compact ? 56 : 76;

    return Center(
      child: SingleChildScrollView(
        padding:
            padding ??
            EdgeInsets.symmetric(horizontal: t.space3xl, vertical: t.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: disc,
              height: disc,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: tint.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: compact ? 24 : 32, color: tint),
            ),
            SizedBox(height: compact ? t.spaceL : t.spaceXl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (compact ? text.titleMedium : text.headlineSmall)
                  ?.copyWith(color: t.textPrimary),
            ),
            if (message != null) ...<Widget>[
              SizedBox(height: t.spaceS),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: t.textSecondary),
              ),
            ],
            if (primaryActionLabel != null) ...<Widget>[
              SizedBox(height: t.space2xl),
              GlowButton(
                label: primaryActionLabel!,
                icon: primaryActionIcon,
                onPressed: onPrimaryAction,
              ),
            ],
            if (secondaryActionLabel != null) ...<Widget>[
              SizedBox(height: t.spaceS),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
