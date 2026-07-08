import 'package:flutter/material.dart';

/// Renders [text] with the character ranges in [spans] highlighted.
///
/// [spans] may be empty (text shown plain), unsorted, or overlapping/invalid —
/// [build] sorts, clamps, and merges them defensively before rendering. The
/// widget is direction-agnostic; wrap it in a `Directionality` or rely on the
/// ambient RTL direction for Arabic.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.spans,
    this.style,
    this.highlightStyle,
    this.textAlign,
  });

  final String text;

  /// Character ranges `[start, end)` into [text] to highlight.
  final List<({int start, int end})> spans;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final TextAlign? textAlign;

  /// Valid spans clamped to [text], sorted, and merged where overlapping.
  List<({int start, int end})> _mergedSpans() {
    final valid = spans
        .where((s) => s.start >= 0 && s.end > s.start && s.start < text.length)
        .map((s) =>
            (start: s.start, end: s.end > text.length ? text.length : s.end))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final merged = <({int start, int end})>[];
    for (final s in valid) {
      if (merged.isNotEmpty && s.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add((start: last.start, end: s.end > last.end ? s.end : last.end));
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final highlight = highlightStyle ??
        base.copyWith(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        );

    final merged = _mergedSpans();
    if (merged.isEmpty) {
      return Text(text, style: base, textAlign: textAlign);
    }

    final children = <TextSpan>[];
    var cursor = 0;
    for (final s in merged) {
      if (s.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, s.start)));
      }
      children.add(TextSpan(text: text.substring(s.start, s.end), style: highlight));
      cursor = s.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: base, children: children),
      textAlign: textAlign,
    );
  }
}
