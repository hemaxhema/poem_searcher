import 'package:shared_preferences/shared_preferences.dart';

import 'app_fonts.dart';

/// Verse font size, inter-bayt vertical spacing, and font family on the poem
/// detail page, all user-adjustable via [PoemDisplaySettings].
class PoemDisplaySettings {
  const PoemDisplaySettings({
    required this.fontSize,
    required this.lineSpacing,
    required this.fontFamily,
  });

  static const double defaultFontSize = 22.0;
  static const double defaultLineSpacing = 0.0;
  static const String defaultFontFamily = AppFonts.defaultFamily;

  static const PoemDisplaySettings defaults = PoemDisplaySettings(
    fontSize: defaultFontSize,
    lineSpacing: defaultLineSpacing,
    fontFamily: defaultFontFamily,
  );

  final double fontSize;
  final double lineSpacing;
  final String fontFamily;
}

/// Persists [PoemDisplaySettings] across app restarts.
class PoemDisplayPrefs {
  static const _fontSizeKey = 'poem_font_size';
  static const _lineSpacingKey = 'poem_line_spacing';
  static const _fontFamilyKey = 'poem_font_family';

  static Future<PoemDisplaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PoemDisplaySettings(
      fontSize: prefs.getDouble(_fontSizeKey) ??
          PoemDisplaySettings.defaultFontSize,
      lineSpacing: prefs.getDouble(_lineSpacingKey) ??
          PoemDisplaySettings.defaultLineSpacing,
      fontFamily: prefs.getString(_fontFamilyKey) ??
          PoemDisplaySettings.defaultFontFamily,
    );
  }

  static Future<void> save(PoemDisplaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, settings.fontSize);
    await prefs.setDouble(_lineSpacingKey, settings.lineSpacing);
    await prefs.setString(_fontFamilyKey, settings.fontFamily);
  }
}
