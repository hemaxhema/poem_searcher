import 'package:flutter/material.dart';

import '../models/source.dart';

/// Opens the "select sources" dialog: checkboxes to include/exclude each
/// [Source] and drag-to-reorder to set search priority. Returns the checked
/// sources in the chosen order, or `null` if the user cancelled/dismissed.
Future<List<Source>?> showSourceFilterDialog(
  BuildContext context,
  List<Source> current,
) {
  return showDialog<List<Source>>(
    context: context,
    builder: (context) => _SourceFilterDialog(initial: current),
  );
}

class _SourceFilterDialog extends StatefulWidget {
  const _SourceFilterDialog({required this.initial});

  final List<Source> initial;

  @override
  State<_SourceFilterDialog> createState() => _SourceFilterDialogState();
}

class _SourceFilterDialogState extends State<_SourceFilterDialog> {
  late List<Source> _order;
  late Set<Source> _included;

  @override
  void initState() {
    super.initState();
    _included = widget.initial.toSet();
    _order = [
      ...widget.initial,
      for (final source in Source.values)
        if (!_included.contains(source)) source,
    ];
  }

  void _setIncluded(Source source, bool value) {
    setState(() {
      if (value) {
        _included.add(source);
      } else if (_included.length > 1) {
        _included.remove(source);
      }
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      _order.insert(newIndex, _order.removeAt(oldIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('المصادر'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'حدد المصادر المراد البحث فيها، واسحبها لترتيب أولوية النتائج.',
              ),
            ),
            SizedBox(
              height: Source.values.length * 72.0,
              child: ReorderableListView(
                onReorder: _reorder,
                children: [
                  for (final source in _order)
                    CheckboxListTile(
                      key: ValueKey(source),
                      value: _included.contains(source),
                      onChanged: (value) =>
                          _setIncluded(source, value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(source.displayName),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([
            for (final source in _order)
              if (_included.contains(source)) source,
          ]),
          child: const Text('تطبيق'),
        ),
      ],
    );
  }
}
