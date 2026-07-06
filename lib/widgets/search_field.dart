import 'dart:async';

import 'package:flutter/material.dart';

import 'haraka_aware_backspace.dart';
import 'visual_caret_arrow_keys.dart';

/// A search text field that debounces changes and reports the query via
/// [onChanged]. RTL-friendly; suitable for Arabic input.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hintText = 'ابحث…',
    this.autofocus = true,
    this.debounce = const Duration(milliseconds: 250),
    this.focusNode,
    this.onSubmitted,
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;
  final Duration debounce;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final TextEditingController _controller = TextEditingController();
  FocusNode? _internalFocusNode;
  Timer? _timer;
  late final VisualCaretArrowKeys _arrowKeys;
  late final HarakaAwareBackspace _harakaBackspace;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _arrowKeys = VisualCaretArrowKeys(
      controller: _controller,
      focusNode: _effectiveFocusNode,
      styleBuilder: () => Theme.of(context).textTheme.bodyLarge!,
    )..attach();
    _harakaBackspace = HarakaAwareBackspace(
      controller: _controller,
      focusNode: _effectiveFocusNode,
    )..attach();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _arrowKeys.dispose();
    _harakaBackspace.dispose();
    _controller.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(value));
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        hintText: widget.hintText,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clear,
                  tooltip: 'مسح',
                ),
        ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
