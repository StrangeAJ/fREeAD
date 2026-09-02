/// Compatibility shim for the pre-v3 empty state. New code uses
/// `EmptyState` from `lib/widgets/ui/empty_state.dart`.
library;

import 'package:flutter/material.dart';

import 'ui/empty_state.dart' as ui;

/// Legacy empty state (icon / title / subtitle / single button). Delegates to
/// the design-system [ui.EmptyState].
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onButtonPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onButtonPressed;

  @override
  Widget build(BuildContext context) {
    return ui.EmptyState(
      icon: icon,
      title: title,
      message: subtitle,
      primaryActionLabel: buttonText,
      primaryActionIcon: Icons.add_rounded,
      onPrimaryAction: onButtonPressed,
    );
  }
}
