import 'package:flutter/material.dart';

/// Renders [text] with the character range `[start, end)` highlighted.
///
/// When the range is invalid (e.g. `start < 0`) the text is shown plain. The
/// widget is direction-agnostic; wrap it in a `Directionality` or rely on the
/// ambient RTL direction for Arabic.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.start,
    required this.end,
    this.style,
    this.highlightStyle,
    this.textAlign,
  });

  final String text;
  final int start;
  final int end;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final highlight = highlightStyle ??
        base.copyWith(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        );

    final bool valid =
        start >= 0 && end > start && start < text.length && end <= text.length;
    if (!valid) {
      return Text(text, style: base, textAlign: textAlign);
    }

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(text: text.substring(start, end), style: highlight),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
