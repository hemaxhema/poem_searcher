import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../search/boolean_query.dart';
import '../util/text_editing.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/global_control_shortcuts.dart';
import '../widgets/haraka_aware_backspace.dart';
import '../widgets/visual_caret_arrow_keys.dart';

/// What the boolean search window hands back to the caller when the user
/// confirms: the raw expression text (so the window can be reopened pre-filled)
/// and its parsed tree (ready to run).
class BooleanSearchResult {
  const BooleanSearchResult(this.raw, this.expr);
  final String raw;
  final BoolExpr expr;
}

/// The dedicated "boolean search" window. The user composes an expression
/// combining tashkeel-aware terms with `+` (و), `|` (أو), `-` (بدون) and `( )`
/// grouping; a live plain-Arabic preview explains what they wrote before they
/// run it. Returns a [BooleanSearchResult] via `Navigator.pop`, or nothing if
/// cancelled.
class BooleanSearchPage extends StatefulWidget {
  const BooleanSearchPage({super.key, this.initialExpression = ''});

  final String initialExpression;

  @override
  State<BooleanSearchPage> createState() => _BooleanSearchPageState();
}

class _BooleanSearchPageState extends State<BooleanSearchPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialExpression);
  final FocusNode _focusNode = FocusNode();
  late final VisualCaretArrowKeys _arrowKeys;
  late final HarakaAwareBackspace _harakaBackspace;
  late BoolParseResult _parsed = parseBoolean(widget.initialExpression);

  /// Ctrl+F works regardless of what (if anything) currently has keyboard
  /// focus — see [GlobalControlShortcuts].
  late final GlobalControlShortcuts _shortcuts = GlobalControlShortcuts(
    bindings: {
      LogicalKeyboardKey.keyF: () => _focusNode.requestFocus(),
    },
    isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
  );

  @override
  void initState() {
    super.initState();
    _arrowKeys = VisualCaretArrowKeys(
      controller: _controller,
      focusNode: _focusNode,
      styleBuilder: () => Theme.of(context).textTheme.bodyLarge!,
    )..attach();
    _harakaBackspace = HarakaAwareBackspace(
      controller: _controller,
      focusNode: _focusNode,
    )..attach();
    _shortcuts.attach();
  }

  @override
  void dispose() {
    _arrowKeys.dispose();
    _harakaBackspace.dispose();
    _shortcuts.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() => _parsed = parseBoolean(_controller.text));
  }

  /// Inserts [token] at the cursor (replacing any selection) and keeps focus.
  /// [caretBack] moves the caret left from the end of the inserted text (e.g. 1
  /// to land between an inserted `[]` pair).
  void _insert(String token, {int caretBack = 0}) {
    _controller.value =
        insertToken(_controller.value, token, caretBack: caretBack);
    _onChanged(_controller.text);
  }

  void _submit() {
    final expr = _parsed.expr;
    if (expr == null) return;
    Navigator.of(context).pop(BooleanSearchResult(_controller.text.trim(), expr));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: Text('بحث منطقي', style: theme.textTheme.titleMedium),
        actions: const [CommonAppBarActions()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اجمع بين الكلمات باستخدام العوامل التالية. كل كلمة تحتفظ بكل '
              'مزايا البحث العادي (التشكيل و * و ؟ و _ و "…").',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Focus(
              onKeyEvent: (node, event) {
                final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (event is KeyDownEvent &&
                    isEnter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _submit();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'مثال: (أرسل | أبلغ) + رسالة - شجون',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OpButton(symbol: '+', label: 'و', onTap: () => _insert(' + ')),
                _OpButton(symbol: '|', label: 'أو', onTap: () => _insert(' | ')),
                _OpButton(symbol: '-', label: 'بدون', onTap: () => _insert(' - ')),
                _OpButton(symbol: '( )', label: 'تجميع', onTap: () => _insert('()', caretBack: 1)),
                _OpButton(symbol: '[ ]', label: 'بدائل الحرف', onTap: () => _insert('[]', caretBack: 1)),
                _OpButton(symbol: '،', label: 'فاصلة', onTap: () => _insert('،')),
                _OpButton(symbol: '*', label: 'أي حروف', onTap: () => _insert('*')),
                _OpButton(symbol: '؟', label: 'حرف واحد', onTap: () => _insert('؟')),
                _OpButton(symbol: '_', label: 'أي كلمات', onTap: () => _insert('_')),
              ],
            ),
            const SizedBox(height: 20),
            _PreviewCard(parsed: _parsed),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _parsed.isValid ? _submit : null,
              icon: const Icon(Icons.search),
              label: const Text('بحث'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small operator-insert button: the symbol plus its Arabic meaning.
class _OpButton extends StatelessWidget {
  const _OpButton({
    required this.symbol,
    required this.label,
    required this.onTap,
  });

  final String symbol;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// The live preview under the input: either a plain-Arabic explanation of the
/// parsed expression, or the Arabic parse error.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.parsed});
  final BoolParseResult parsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expr = parsed.expr;
    final bool ok = expr != null;
    final Color fg =
        ok ? theme.colorScheme.onSurface : theme.colorScheme.error;
    final Color bg = ok
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.errorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ok ? 'سيبحث عن:' : 'خطأ في التعبير:',
            style: theme.textTheme.labelLarge?.copyWith(color: fg),
          ),
          const SizedBox(height: 6),
          Text(
            ok
                ? 'الأبيات التي تحتوي على ${expr.describeArabic()}'
                : (parsed.errorAr ?? 'تعبير غير صالح.'),
            style: theme.textTheme.bodyLarge?.copyWith(color: fg, height: 1.6),
          ),
        ],
      ),
    );
  }
}
