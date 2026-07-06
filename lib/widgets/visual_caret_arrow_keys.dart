import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Corrects Flutter's arrow-key caret movement (which moves by *logical*
/// string order) to move by *visual* screen position instead, matching
/// native text editors. This matters for RTL (Arabic) text, where Flutter's
/// default Left/Right arrow behaviour is backwards.
///
/// Works by observing arrow-key presses globally (Flutter's own key/action
/// handling can't reliably be intercepted from outside a [TextField]), then
/// correcting the [controller]'s selection in a microtask scheduled right
/// after — run unconditionally (not only when the default handling actually
/// changed the selection, since at the true start/end of the text Flutter's
/// logical-order handling can no-op even though a visual move is still
/// possible). The microtask runs before the next frame, so there's no
/// visible flicker.
class VisualCaretArrowKeys {
  VisualCaretArrowKeys({
    required this.controller,
    required this.focusNode,
    required this.styleBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle Function() styleBuilder;

  void attach() {
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!focusNode.hasFocus) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    final pending = _PendingMove(
      toLeft: key == LogicalKeyboardKey.arrowLeft,
      byWord: HardwareKeyboard.instance.isControlPressed,
      extend: HardwareKeyboard.instance.isShiftPressed,
      textBefore: controller.text,
      selectionBefore: controller.selection,
    );
    scheduleMicrotask(() => _applyCorrection(pending));
    return false;
  }

  void _applyCorrection(_PendingMove pending) {
    if (controller.text != pending.textBefore) return;
    final context = focusNode.context;
    if (context == null) return;

    final text = controller.text;
    final selBefore = pending.selectionBefore;
    if (!selBefore.isValid) return;

    final renderBox = context.findRenderObject();
    final maxWidth =
        renderBox is RenderBox ? renderBox.size.width : double.infinity;

    final painter = TextPainter(
      text: TextSpan(text: text, style: styleBuilder()),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);

    final TextBoundary boundary =
        pending.byWord ? painter.wordBoundaries.moveByWordBoundary : CharacterBoundary(text);

    final TextSelection target;
    if (!pending.extend && !selBefore.isCollapsed) {
      target = TextSelection.collapsed(
        offset: _visuallyLeftmost(
          painter,
          selBefore.start,
          selBefore.end,
          pending.toLeft,
        ),
      );
    } else {
      final current = pending.extend ? selBefore.extentOffset : selBefore.baseOffset;
      final stepped = _visualStep(
        text,
        current,
        boundary: boundary,
        toLeft: pending.toLeft,
        painter: painter,
      );
      target = pending.extend
          ? TextSelection(baseOffset: selBefore.baseOffset, extentOffset: stepped)
          : TextSelection.collapsed(offset: stepped);
    }

    if (target != controller.selection) {
      controller.selection = target;
    }
    painter.dispose();
  }
}

class _PendingMove {
  _PendingMove({
    required this.toLeft,
    required this.byWord,
    required this.extend,
    required this.textBefore,
    required this.selectionBefore,
  });

  final bool toLeft;
  final bool byWord;
  final bool extend;
  final String textBefore;
  final TextSelection selectionBefore;
}

(double, double) _visualKey(TextPainter painter, int index) {
  final o = painter.getOffsetForCaret(TextPosition(offset: index), Rect.zero);
  return (o.dy, o.dx);
}

bool _isVisuallyBefore((double, double) a, (double, double) b) =>
    a.$1 != b.$1 ? a.$1 < b.$1 : a.$2 < b.$2;

int _visuallyLeftmost(TextPainter painter, int a, int b, bool wantLeft) {
  final aIsLeft = _isVisuallyBefore(_visualKey(painter, a), _visualKey(painter, b));
  if (wantLeft) return aIsLeft ? a : b;
  return aIsLeft ? b : a;
}

/// Mirrors `EditableText._moveBeyondTextBoundary`: the closest boundary
/// location to [offset] but not including it (unless already at the very
/// start/end of the text).
int _previousBoundary(TextBoundary boundary, int offset, String text) =>
    boundary.getLeadingTextBoundaryAt(offset - 1) ?? 0;

int _nextBoundary(TextBoundary boundary, int offset, String text) =>
    boundary.getTrailingTextBoundaryAt(offset) ?? text.length;

int _visualStep(
  String text,
  int current, {
  required TextBoundary boundary,
  required bool toLeft,
  required TextPainter painter,
}) {
  final prevIdx = _previousBoundary(boundary, current, text);
  final nextIdx = _nextBoundary(boundary, current, text);
  if (prevIdx == current && nextIdx == current) return current;

  final curKey = _visualKey(painter, current);
  int leftCandidate, rightCandidate;
  if (prevIdx == current) {
    final nextIsLeft = _isVisuallyBefore(_visualKey(painter, nextIdx), curKey);
    leftCandidate = nextIsLeft ? nextIdx : current;
    rightCandidate = nextIsLeft ? current : nextIdx;
  } else if (nextIdx == current) {
    final prevIsLeft = _isVisuallyBefore(_visualKey(painter, prevIdx), curKey);
    leftCandidate = prevIsLeft ? prevIdx : current;
    rightCandidate = prevIsLeft ? current : prevIdx;
  } else {
    final prevIsLeftOfNext =
        _isVisuallyBefore(_visualKey(painter, prevIdx), _visualKey(painter, nextIdx));
    leftCandidate = prevIsLeftOfNext ? prevIdx : nextIdx;
    rightCandidate = prevIsLeftOfNext ? nextIdx : prevIdx;
  }
  return toLeft ? leftCandidate : rightCandidate;
}
