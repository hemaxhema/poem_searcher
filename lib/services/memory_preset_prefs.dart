import 'package:shared_preferences/shared_preferences.dart';

import '../db/memory_preset.dart';

/// Persists the user's chosen memory preset across app restarts.
///
/// Stored as the [MemoryPreset.id] string; an unknown or absent value falls
/// back to [MemoryPreset.high] (see [MemoryPreset.byId]).
class MemoryPresetPrefs {
  static const _key = 'memory_preset';

  /// Loads the saved preset, or [MemoryPreset.high] if none saved.
  static Future<MemoryPreset> load() async {
    final prefs = await SharedPreferences.getInstance();
    return MemoryPreset.byId(prefs.getString(_key));
  }

  static Future<void> save(MemoryPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preset.id);
  }
}
