import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../search/arabic_normalizer.dart';

/// Makes Backspace remove one trailing diacritic (haraka) at a time instead
/// of deleting the base letter and all its diacritics together in a single
/// press. Flutter's default Backspace handling deletes by grapheme cluster,
/// which fuses a base letter with its combining tashkeel marks into one
/// unit — so e.g. "حَ" (ح + fatha) is removed entirely on one press. Native
/// Arabic text editors instead peel the haraka off first.
///
/// Works the same way as [VisualCaretArrowKeys]: [HardwareKeyboard] handlers
/// can't consume/block a [TextField]'s built-in key handling, only observe
/// it, so this lets the default deletion happen and then corrects the
/// resulting value — restoring everything except the last character of the
/// deleted span when that character was a diacritic.
class HarakaAwareBackspace {
  HarakaAwareBackspace({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  _PendingDelete? _pending;

  void attach() {
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    controller.addListener(_onValueChanged);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    controller.removeListener(_onValueChanged);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!focusNode.hasFocus) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return false;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    _pending = _PendingDelete(
      textBefore: controller.text,
      caretBefore: selection.baseOffset,
    );
    return false;
  }

  void _onValueChanged() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;

    final newText = controller.text;
    final removed = pending.textBefore.length - newText.length;
    if (removed <= 1) return; // no deletion, or already a single char

    final selection = controller.selection;
    if (!selection.isCollapsed) return;
    final caretAfter = selection.baseOffset;
    if (caretAfter != pending.caretBefore - removed) return;
    if (caretAfter < 0 || caretAfter + removed > pending.textBefore.length) {
      return;
    }

    // Confirm this was a plain deletion at the caret (text on either side
    // of the removed span is unchanged), not some other kind of edit.
    if (pending.textBefore.substring(0, caretAfter) !=
            newText.substring(0, caretAfter) ||
        pending.textBefore.substring(caretAfter + removed) !=
            newText.substring(caretAfter)) {
      return;
    }

    final deletedSpan =
        pending.textBefore.substring(caretAfter, caretAfter + removed);
    if (!isDiacritic(deletedSpan[deletedSpan.length - 1])) return;

    final keep = deletedSpan.substring(0, deletedSpan.length - 1);
    final restored = newText.replaceRange(caretAfter, caretAfter, keep);
    controller.value = TextEditingValue(
      text: restored,
      selection: TextSelection.collapsed(offset: caretAfter + keep.length),
    );
  }
}

class _PendingDelete {
  _PendingDelete({required this.textBefore, required this.caretBefore});

  final String textBefore;
  final int caretBefore;
}
