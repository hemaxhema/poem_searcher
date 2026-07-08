import 'package:shared_preferences/shared_preferences.dart';

import '../search/search_sort.dart';

/// Persists the user's chosen result sort mode across app restarts.
///
/// Stored as the [SearchSort.id] string; an unknown or absent value falls back
/// to [SearchSort.lineCountDesc] (see [SearchSort.byId]).
class SearchSortPrefs {
  static const _key = 'search_sort_mode';

  /// Loads the saved sort mode, or [SearchSort.lineCountDesc] if none saved.
  static Future<SearchSort> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchSort.byId(prefs.getString(_key));
  }

  static Future<void> save(SearchSort sort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, sort.id);
  }
}
