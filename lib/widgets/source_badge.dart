import 'package:flutter/material.dart';

import '../models/source.dart';

/// Small pill naming which data source a result came from.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        source.displayName,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// Lists every source a duplicated result was found under (the one already
/// shown plus each hidden duplicate's source) in a simple dialog.
void showDuplicateSourcesDialog(BuildContext context, List<Source> sources) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('مصادر أخرى'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final s in sources) SourceBadge(source: s)],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
