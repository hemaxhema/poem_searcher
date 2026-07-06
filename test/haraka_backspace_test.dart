// Arabic characters are written with `\u` escapes so the exact code points
// are unambiguous (same convention as lib/search/arabic_normalizer.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/widgets/search_field.dart';

const String _haa = 'ح'; // ح
const String _baa = 'ب'; // ب
const String _fatha = 'َ'; // َ
const String _shadda = 'ّ'; // ّ

void main() {
  Future<TextEditingController> pumpSearchField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchField(onChanged: (_) {})),
      ),
    );
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.tap(find.byType(TextField));
    await tester.pump();
    return controller;
  }

  testWidgets('backspace removes only the trailing haraka first',
      (tester) async {
    final controller = await pumpSearchField(tester);
    controller.text = '$_haa$_fatha';
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, _haa);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, '');
  });

  testWidgets('peels multiple stacked diacritics one at a time',
      (tester) async {
    final controller = await pumpSearchField(tester);
    controller.text = '$_haa$_fatha$_shadda';
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, '$_haa$_fatha');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, _haa);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, '');
  });

  testWidgets('a plain letter with no diacritic deletes normally',
      (tester) async {
    final controller = await pumpSearchField(tester);
    controller.text = '$_haa$_baa';
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, _haa);
  });
}
