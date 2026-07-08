import 'package:shared_preferences/shared_preferences.dart';

/// Font size for search-result tiles on the home page — independent of
/// `PoemDisplaySettings.fontSize`, which only affects the poem detail page.
class ResultsDisplayPrefs {
  static const _fontSizeKey = 'results_font_size';
  static const double defaultFontSize = 22.0;

  static Future<double> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_fontSizeKey) ?? defaultFontSize;
  }

  static Future<void> save(double fontSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, fontSize);
  }
}
