import 'package:shared_preferences/shared_preferences.dart';

import 'app_fonts.dart';

/// Font size and font family for search-result tiles on the home page —
/// independent of `PoemDisplaySettings`, which only affects the poem detail
/// page.
class ResultsDisplaySettings {
  const ResultsDisplaySettings({
    required this.fontSize,
    required this.fontFamily,
  });

  static const double defaultFontSize = 22.0;
  static const String defaultFontFamily = AppFonts.defaultFamily;

  static const ResultsDisplaySettings defaults = ResultsDisplaySettings(
    fontSize: defaultFontSize,
    fontFamily: defaultFontFamily,
  );

  final double fontSize;
  final String fontFamily;
}

/// Persists [ResultsDisplaySettings] across app restarts.
class ResultsDisplayPrefs {
  static const _fontSizeKey = 'results_font_size';
  static const _fontFamilyKey = 'results_font_family';

  static Future<ResultsDisplaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ResultsDisplaySettings(
      fontSize: prefs.getDouble(_fontSizeKey) ??
          ResultsDisplaySettings.defaultFontSize,
      fontFamily: prefs.getString(_fontFamilyKey) ??
          ResultsDisplaySettings.defaultFontFamily,
    );
  }

  static Future<void> save(ResultsDisplaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, settings.fontSize);
    await prefs.setString(_fontFamilyKey, settings.fontFamily);
  }
}
