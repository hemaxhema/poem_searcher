import 'package:flutter/services.dart';

import '../platform/input_capabilities.dart';

/// Fires bindings for key presses observed globally via [HardwareKeyboard],
/// bypassing Flutter's Focus/Shortcuts chain entirely.
///
/// [controlBindings] fire for Ctrl+`key` presses; [plainBindings] fire for the
/// same keys pressed with no Ctrl held (e.g. Escape).
///
/// `CallbackShortcuts`/`Shortcuts` only fire while keyboard focus sits
/// somewhere inside their subtree — in this app that's unreliable, since
/// nothing may be focused at all (or focus may have moved to a widget
/// outside the subtree). [VisualCaretArrowKeys] and [HarakaAwareBackspace]
/// hit the same problem for arrow-key/backspace handling and work around it
/// the same way: observe key events globally instead of depending on the
/// focus tree.
class GlobalKeyboardShortcuts {
  GlobalKeyboardShortcuts({
    this.controlBindings = const {},
    this.plainBindings = const {},
    required this.isActive,
  });

  /// Ctrl+`key` bindings to fire on key-down.
  final Map<LogicalKeyboardKey, VoidCallback> controlBindings;

  /// Unmodified `key` bindings to fire on key-down (no Ctrl held), e.g. Escape.
  final Map<LogicalKeyboardKey, VoidCallback> plainBindings;

  /// Whether this page should currently react to its bindings (e.g. it's the
  /// topmost route) — prevents an offstage/backgrounded page from also
  /// reacting to a shortcut meant for the page now on top.
  final bool Function() isActive;

  /// No-op on platforms without a hardware keyboard (see
  /// [hasHardwareKeyboard]); [dispose] stays safe to call regardless. This is
  /// what keeps every binding here desktop-only and inert on Android/iOS.
  void attach() {
    if (!hasHardwareKeyboard) return;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  void dispose() => HardwareKeyboard.instance.removeHandler(_onKeyEvent);

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!isActive()) return false;
    final action = HardwareKeyboard.instance.isControlPressed
        ? controlBindings[event.logicalKey]
        : plainBindings[event.logicalKey];
    if (action == null) return false;
    action();
    return false;
  }
}
