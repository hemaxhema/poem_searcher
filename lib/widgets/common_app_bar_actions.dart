import 'package:flutter/material.dart';

import '../services/theme_mode_prefs.dart';
import '../theme/app_theme.dart';
import '../ui/settings_page.dart';
import 'help_dialog.dart';

/// The day/night toggle, settings, and help buttons shown at the end of every
/// page's AppBar, so quick access to them is consistent across screens.
class CommonAppBarActions extends StatelessWidget {
  const CommonAppBarActions({
    super.key,
    this.showSettings = true,
    this.onOpenSettings,
  });

  /// Hidden on the Settings page itself, where opening it again is pointless.
  final bool showSettings;

  /// Overrides the default "push SettingsPage" behavior for pages that need
  /// to reload their own state (source order, sort mode, display settings…)
  /// once the user returns from Settings.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ThemeModeToggle(),
        if (showSettings)
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
            onPressed: onOpenSettings ?? () => _openSettings(context),
          ),
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: 'مساعدة',
          onPressed: () => showHelpDialog(context),
        ),
      ],
    );
  }

  static void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }
}

class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.currentMode,
      builder: (context, mode, _) {
        final isNight = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        return IconButton(
          icon: Icon(isNight ? Icons.light_mode : Icons.dark_mode),
          tooltip: isNight ? 'الوضع النهاري' : 'الوضع الليلي',
          onPressed: () {
            final newMode = isNight ? ThemeMode.light : ThemeMode.dark;
            AppTheme.currentMode.value = newMode;
            ThemeModePrefs.save(newMode);
          },
        );
      },
    );
  }
}
