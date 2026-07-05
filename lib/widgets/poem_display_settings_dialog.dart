import 'package:flutter/material.dart';

import '../services/app_fonts.dart';
import '../services/poem_display_prefs.dart';

/// Opens the "poem display settings" dialog: sliders to adjust the verse
/// font size and the vertical spacing between bayts. Returns the chosen
/// [PoemDisplaySettings], or `null` if the user cancelled/dismissed.
Future<PoemDisplaySettings?> showPoemDisplaySettingsDialog(
  BuildContext context,
  PoemDisplaySettings current,
) {
  return showDialog<PoemDisplaySettings>(
    context: context,
    builder: (context) => _PoemDisplaySettingsDialog(initial: current),
  );
}

class _PoemDisplaySettingsDialog extends StatefulWidget {
  const _PoemDisplaySettingsDialog({required this.initial});

  final PoemDisplaySettings initial;

  @override
  State<_PoemDisplaySettingsDialog> createState() =>
      _PoemDisplaySettingsDialogState();
}

class _PoemDisplaySettingsDialogState
    extends State<_PoemDisplaySettingsDialog> {
  late double _fontSize;
  late double _lineSpacing;
  late String _fontFamily;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initial.fontSize;
    _lineSpacing = widget.initial.lineSpacing;
    _fontFamily = widget.initial.fontFamily;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعدادات العرض'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('حجم الخط: ${_fontSize.round()}'),
            Slider(
              value: _fontSize,
              min: 16,
              max: 32,
              divisions: 16,
              label: '${_fontSize.round()}',
              onChanged: (value) => setState(() => _fontSize = value),
            ),
            const SizedBox(height: 12),
            Text('المسافة بين الأبيات: ${_lineSpacing.round()}'),
            Slider(
              value: _lineSpacing,
              min: 0,
              max: 20,
              divisions: 20,
              label: '${_lineSpacing.round()}',
              onChanged: (value) => setState(() => _lineSpacing = value),
            ),
            const SizedBox(height: 12),
            const Text('الخط'),
            SizedBox(
              height: 220,
              child: RadioGroup<String>(
                groupValue: _fontFamily,
                onChanged: (value) => setState(() => _fontFamily = value!),
                child: ListView(
                  shrinkWrap: true,
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
          onPressed: () => Navigator.of(context).pop(
            PoemDisplaySettings(
              fontSize: _fontSize,
              lineSpacing: _lineSpacing,
              fontFamily: _fontFamily,
            ),
          ),
          child: const Text('تطبيق'),
        ),
      ],
    );
  }
}
