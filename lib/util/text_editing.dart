import 'package:flutter/services.dart';

/// Inserts [token] at the selection of [value] (replacing any selected text)
/// and returns the new value with a collapsed caret placed [caretBack]
/// characters before the end of the inserted text (e.g. 1 to land between an
/// inserted `[]` pair). With no valid selection the token is appended.
TextEditingValue insertToken(
  TextEditingValue value,
  String token, {
  int caretBack = 0,
}) {
  final sel = value.selection;
  final start = sel.start < 0 ? value.text.length : sel.start;
  final end = sel.end < 0 ? value.text.length : sel.end;
  final text = value.text.replaceRange(start, end, token);
  final caret = start + token.length - caretBack;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
}
