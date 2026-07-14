import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'db/poem_repository.dart';
import 'platform/bootstrap_selector.dart';
import 'services/app_fonts.dart';
import 'services/memory_preset_prefs.dart';
import 'services/poem_display_prefs.dart';
import 'services/results_display_prefs.dart';
import 'services/theme_mode_prefs.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppFonts.discoverAndLoad();
  AppFonts.currentFamily.value =
      (await PoemDisplayPrefs.load()).fontFamily;
  final resultsDisplay = await ResultsDisplayPrefs.load();
  AppFonts.currentResultsFontSize.value = resultsDisplay.fontSize;
  AppFonts.currentResultsFamily.value = resultsDisplay.fontFamily;
  final savedThemeMode = await ThemeModePrefs.load();
  if (savedThemeMode != null) {
    AppTheme.currentMode.value = savedThemeMode;
  }
  runApp(const PoemSearcherApp());
}

class PoemSearcherApp extends StatelessWidget {
  const PoemSearcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.currentMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'البحث في الشعر',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.day,
          darkTheme: AppTheme.night,
          themeMode: themeMode,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const _Bootstrap(),
        );
      },
    );
  }
}

/// Opens the repository once and then shows the home page. All Arabic UI is
/// forced RTL regardless of platform locale.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  /// First-run index-build progress text, or `null` when there is no build in
  /// progress (already indexed, so startup is near-instant).
  final ValueNotifier<String?> _status = ValueNotifier<String?>(null);
  late final Future<PoemRepository> _repoFuture = _openRepo();

  Future<PoemRepository> _openRepo() async {
    final preset = await MemoryPresetPrefs.load();
    return PoemRepository.open(
      bootstrap: createDatabaseBootstrap(),
      onIndexProgress: _onIndexProgress,
      preset: preset,
    );
  }

  void _onIndexProgress(String label, int done, int total) {
    _status.value = total > 0
        ? '$label… ${(100 * done / total).floor()}٪'
        : '$label…';
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<PoemRepository>(
        future: _repoFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('تعذّر فتح قاعدة البيانات:\n${snapshot.error}'),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Scaffold(body: Center(child: _buildLoading()));
          }
          return HomePage(repo: snapshot.data!);
        },
      ),
    );
  }

  Widget _buildLoading() {
    return ValueListenableBuilder<String?>(
      valueListenable: _status,
      builder: (context, status, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (status != null) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'جارٍ تجهيز فهرس البحث، يحدث مرة واحدة، قد يستغرق بضع دقائق.\n$status',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
