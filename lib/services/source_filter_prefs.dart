import 'package:shared_preferences/shared_preferences.dart';

import '../models/source.dart';

/// Persists the user's selected/ordered search sources across app restarts.
///
/// Stored as the list of [Source.name] values, in priority order; a source
/// absent from the stored list is excluded from search.
class SourceFilterPrefs {
  static const _key = 'source_filter_order';

  /// Loads the saved order, or all sources in declared order if none saved.
  static Future<List<Source>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key);
    if (saved == null) return Source.values;
    final bySource = {for (final s in Source.values) s.name: s};
    final order = saved.map((name) => bySource[name]).whereType<Source>().toList();
    return order.isEmpty ? Source.values : order;
  }

  static Future<void> save(List<Source> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final s in order) s.name]);
  }
}
