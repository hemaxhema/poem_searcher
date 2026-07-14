import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poem_searcher/util/text_editing.dart';

void main() {
  group('insertToken', () {
    test('inserts at a collapsed caret', () {
      const value = TextEditingValue(
        text: 'شمس قمر',
        selection: TextSelection.collapsed(offset: 3),
      );
      final result = insertToken(value, ' +');
      expect(result.text, 'شمس + قمر');
      expect(result.selection.baseOffset, 5);
    });

    test('replaces the selected range', () {
      const value = TextEditingValue(
        text: 'شمس قمر',
        selection: TextSelection(baseOffset: 4, extentOffset: 7),
      );
      final result = insertToken(value, 'نجم');
      expect(result.text, 'شمس نجم');
      expect(result.selection.baseOffset, 7);
    });

    test('caretBack lands the caret inside an inserted pair', () {
      const value = TextEditingValue(
        text: 'شمس',
        selection: TextSelection.collapsed(offset: 3),
      );
      final result = insertToken(value, '()', caretBack: 1);
      expect(result.text, 'شمس()');
      expect(result.selection.baseOffset, 4);
    });

    test('appends when there is no valid selection', () {
      const value = TextEditingValue(text: 'شمس');
      final result = insertToken(value, ' | ');
      expect(result.text, 'شمس | ');
      expect(result.selection.baseOffset, 6);
    });
  });
}
