import 'dart:io';

/// Whether the current platform has a physical keyboard whose key events the
/// global [HardwareKeyboard]-based helpers should observe.
///
/// True on desktop (Windows/Linux/macOS). False on mobile (Android/iOS),
/// where the soft keyboard / IME edits text without emitting hardware key
/// events — so the global shortcut, RTL-caret, and haraka-backspace handlers
/// would never fire and must not attach. On mobile the platform's own soft
/// keyboard provides the native backspace/caret behaviour instead.
bool get hasHardwareKeyboard =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Whether the current platform has a device orientation worth toggling
/// (Android/iOS). False on desktop, where `SystemChrome.setPreferredOrientations`
/// is a no-op — so orientation controls are hidden there.
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
