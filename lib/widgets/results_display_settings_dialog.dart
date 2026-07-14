import 'package:flutter/material.dart';

import '../services/app_fonts.dart';
import '../services/results_display_prefs.dart';

/// Opens the "search results display settings" dialog: a slider for the
/// result tiles' font size and a picker for their font family. Returns the
/// chosen [ResultsDisplaySettings], or `null` if the user cancelled/dismissed.
Future<ResultsDisplaySettings?> showResultsDisplaySettingsDialog(
  BuildContext context,
  ResultsDisplaySettings current,
) {
  return showDialog<ResultsDisplaySettings>(
    context: context,
    builder: (context) => _ResultsDisplaySettingsDialog(initial: current),
  );
}

class _ResultsDisplaySettingsDialog extends StatefulWidget {
  const _ResultsDisplaySettingsDialog({required this.initial});

  final ResultsDisplaySettings initial;

  @override
  State<_ResultsDisplaySettingsDialog> createState() =>
      _ResultsDisplaySettingsDialogState();
}

class _ResultsDisplaySettingsDialogState
    extends State<_ResultsDisplaySettingsDialog> {
  late double _fontSize;
  late String _fontFamily;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initial.fontSize;
    _fontFamily = widget.initial.fontFamily;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعدادات عرض نتائج البحث'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('حجم الخط: ${_fontSize.round()}'),
              Slider(
                value: _fontSize,
                min: 10,
                max: 34,
                divisions: 24,
                label: '${_fontSize.round()}',
                onChanged: (value) => setState(() => _fontSize = value),
              ),
              const SizedBox(height: 12),
              const Text('الخط'),
              RadioGroup<String>(
                groupValue: _fontFamily,
                onChanged: (value) => setState(() => _fontFamily = value!),
                child: Column(
                  children: [
                    for (final font in AppFonts.available)
                      RadioListTile<String>(
                        value: font.familyId,
                        title: Text(
                          '${font.label}  —  أبجد هوز حطي',
                          style: TextStyle(fontFamily: font.familyId),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ResultsDisplaySettings(
              fontSize: _fontSize,
              fontFamily: _fontFamily,
            ),
          ),
          child: const Text('تطبيق'),
        ),
      ],
    );
  }
}
