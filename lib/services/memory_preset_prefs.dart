import 'package:shared_preferences/shared_preferences.dart';

import '../db/memory_preset.dart';

/// Persists the user's chosen memory preset across app restarts.
///
/// Stored as the [MemoryPreset.id] string; when nothing is saved it falls back
/// to [MemoryPreset.defaultForPlatform] (mobile gets [MemoryPreset.low],
/// desktop [MemoryPreset.balanced]).
class MemoryPresetPrefs {
  static const _key = 'memory_preset';

  /// Loads the saved preset, or [MemoryPreset.defaultForPlatform] if none saved.
  static Future<MemoryPreset> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved == null
        ? MemoryPreset.defaultForPlatform
        : MemoryPreset.byId(saved);
  }

  static Future<void> save(MemoryPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preset.id);
  }
}
