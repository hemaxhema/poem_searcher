import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A font discovered under `assets/fonts/`: [familyId] is what gets passed to
/// [FontLoader] and used as `TextStyle.fontFamily`; [label] is the
/// human-readable name shown in the font picker.
class AppFont {
  const AppFont({required this.familyId, required this.label});

  final String familyId;
  final String label;
}

/// Discovers and dynamically loads every font file bundled under
/// `assets/fonts/`, so dropping a new file in that folder (and rebuilding)
/// makes it available with no other code change — Flutter otherwise requires
/// every font family to be declared individually in `pubspec.yaml`.
class AppFonts {
  AppFonts._();

  /// Family id used for the app's original bundled font, kept as the default
  /// selection.
  static const String defaultFamily = 'calibre';

  /// Nice labels for the popular Arabic fonts this app ships with. Any font
  /// file not listed here still loads and appears in the picker, just
  /// labeled with its (title-cased) filename instead.
  static const Map<String, String> _knownLabels = {
    'calibre': 'كاليبري (Calibre)',
    'amiri': 'أميري (Amiri)',
    'scheherazadenew': 'شهرزاد الجديد (Scheherazade New)',
    'notonaskharabic': 'نوتو نسخ (Noto Naskh Arabic)',
    'cairo': 'القاهرة (Cairo)',
    'tajawal': 'تجوال (Tajawal)',
    'almarai': 'المرعي (Almarai)',
  };

  /// Populated by [discoverAndLoad]; empty until then.
  static List<AppFont> available = const [];

  /// Currently selected font family, kept in sync with the persisted
  /// [PoemDisplaySettings] so pages other than the one that opened the
  /// settings dialog (e.g. the home page search results, sitting underneath
  /// it in the nav stack) update immediately without a route callback.
  static final ValueNotifier<String> currentFamily =
      ValueNotifier<String>(defaultFamily);

  /// Currently selected home-page results font size, kept in sync the same
  /// way as [currentFamily] — independent of the poem-detail page's font
  /// size (`PoemDisplaySettings.fontSize`).
  static final ValueNotifier<double> currentResultsFontSize =
      ValueNotifier<double>(22.0);

  /// Currently selected home-page results font family, kept in sync the same
  /// way as [currentResultsFontSize] — independent of [currentFamily], which
  /// only affects the poem-detail page.
  static final ValueNotifier<String> currentResultsFamily =
      ValueNotifier<String>(defaultFamily);

  /// Derives a display label for a font's [familyId] (its filename stem).
  static String labelFor(String familyId) {
    final known = _knownLabels[familyId];
    if (known != null) return known;
    return familyId
        .split(RegExp(r'[_\-\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  /// Extracts the family id (filename without extension) from an asset path
  /// such as `assets/fonts/amiri.ttf`.
  static String familyIdFor(String assetPath) {
    final fileName = assetPath.split('/').last;
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? fileName : fileName.substring(0, dot);
  }

  static const _fontExtensions = {'ttf', 'otf'};

  /// Scans the asset manifest for files under `assets/fonts/`, registers
  /// each with [FontLoader] under a family id derived from its filename, and
  /// returns the discovered fonts (labeled, sorted by label).
  static Future<List<AppFont>> discoverAndLoad() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final fontPaths = manifest
        .listAssets()
        .where((path) => path.startsWith('assets/fonts/'))
        .where((path) {
          final dot = path.lastIndexOf('.');
          if (dot == -1) return false;
          return _fontExtensions.contains(path.substring(dot + 1).toLowerCase());
        })
        .toList();

    final fonts = <AppFont>[];
    for (final path in fontPaths) {
      final familyId = familyIdFor(path);
      final loader = FontLoader(familyId)..addFont(rootBundle.load(path));
      await loader.load();
      fonts.add(AppFont(familyId: familyId, label: labelFor(familyId)));
    }
    fonts.sort((a, b) => a.label.compareTo(b.label));

    available = fonts;
    return fonts;
  }
}
