import 'package:shared_preferences/shared_preferences.dart';

/// Whether search also runs over poem titles (the "عناوين" results section).
/// When off, titles are neither searched nor shown — only the verse-line
/// ("أبيات") section appears. Defaults to off.
class SearchTitlesPrefs {
  static const _key = 'search_in_titles';
  static const bool defaultEnabled = false;

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? defaultEnabled;
  }

  static Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
