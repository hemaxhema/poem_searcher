import 'package:flutter/foundation.dart';

import '../db/poem_repository.dart';
import '../models/poem.dart';
import '../models/poem_line.dart';
import '../services/app_fonts.dart';
import '../services/poem_display_prefs.dart';

/// Loads and holds one poem's data (metadata, sources, lines) and its display
/// settings; the detail page renders this and keeps only visual concerns
/// (scrolling, clipboard/snackbar, kashida measurement) for itself.
class PoemDetailController extends ChangeNotifier {
  PoemDetailController({required this.repo, required this.poemId});

  final PoemRepository repo;
  final int poemId;

  bool _disposed = false;

  Poem? _poem;
  List<({String name, String? url})> _sources = const [];
  List<PoemLine>? _lines;
  List<List<PoemLine>> _lineGroups = const [];
  PoemDisplaySettings _display = PoemDisplaySettings.defaults;

  /// Poem metadata for the header/title; null until it resolves.
  Poem? get poem => _poem;

  /// Every source this poem is available from (its own + any duplicates
  /// merged into it); empty until it resolves.
  List<({String name, String? url})> get sources => _sources;

  /// The poem's lines, or null while still loading.
  List<PoemLine>? get lines => _lines;

  /// [lines] grouped so alternate readings (riwayat) of the same bayt end up
  /// in one group (see [groupByLineNumber]); empty until [lines] resolves.
  List<List<PoemLine>> get lineGroups => _lineGroups;

  /// User-adjustable verse font/size/spacing, loaded from persisted prefs.
  PoemDisplaySettings get display => _display;

  /// Starts the poem/sources/lines/prefs loads, notifying as each resolves —
  /// same progressive fill-in as the old `initState` `.then` blocks.
  void load() {
    repo.poemById(poemId).then((poem) {
      if (_disposed) return;
      _poem = poem;
      notifyListeners();
    });
    repo.sourcesOfPoem(poemId).then((sources) {
      if (_disposed) return;
      _sources = sources;
      notifyListeners();
    });
    repo.linesOfPoem(poemId).then((lines) {
      if (_disposed) return;
      _lines = lines;
      _lineGroups = groupByLineNumber(lines);
      notifyListeners();
    });
    PoemDisplayPrefs.load().then((settings) {
      if (_disposed) return;
      _display = settings;
      notifyListeners();
    });
  }

  /// Reloads the display settings (font/size/spacing) — called on return from
  /// the Settings page, where they may have changed.
  Future<void> reloadDisplayPrefs() async {
    final display = await PoemDisplayPrefs.load();
    if (_disposed) return;
    _display = display;
    notifyListeners();
  }

  /// Applies new display settings, persists them, and propagates the font
  /// family to the app-wide notifier.
  Future<void> setDisplay(PoemDisplaySettings settings) async {
    _display = settings;
    notifyListeners();
    await PoemDisplayPrefs.save(settings);
    AppFonts.currentFamily.value = settings.fontFamily;
  }

  /// The poem as copyable text: one bayt per line, first reading per group,
  /// clean source wording (no kashida elongation). Empty until lines load.
  String buildCopyText() =>
      _lineGroups.map((group) => group.first.line).join('\n');

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
