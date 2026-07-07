import 'package:flutter/material.dart';

/// Small tappable circular "+N" badge with a tooltip, used to surface a count
/// of items hidden behind a dialog (e.g. alternate riwayat, duplicate sources).
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    required this.tooltip,
    required this.onTap,
  });

  final int count;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Text(
                '+$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
