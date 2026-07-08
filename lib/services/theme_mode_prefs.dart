import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's explicit day/night override from the AppBar toggle.
/// Returns `null` from [load] until the user has tapped the toggle once, so
/// the app keeps following the OS brightness until they opt in.
class ThemeModePrefs {
  static const _key = 'theme_mode';

  static Future<ThemeMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'day':
        return ThemeMode.light;
      case 'night':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.dark ? 'night' : 'day');
  }
}
