import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/poem.dart';
import '../models/poem_line.dart';
import '../search/tashkeel_search.dart';

/// Path of the database bundled as a Flutter asset.
const String _assetDbPath = 'assets/test.db';

/// File name of the writable copy in the app-support directory.
const String _dbFileName = 'test.db';

/// Bump this whenever a new database asset ships so the previously copied
/// writable file is refreshed on next launch (see [_ensureWritableDbCopy]).
const String _dbAssetVersion = '1';

/// Upper bound on rows pulled from the coarse SQL filter before the precise
/// regex confirms them. Keeps a broad query from scanning the whole table.
const int _candidateLimit = 4000;

/// Upper bound on confirmed line results returned to the UI.
const int _resultLimit = 300;

/// One confirmed line search result, carrying the poem metadata the result
/// tiles need so they render without any further per-tile database lookup.
class LineResult {
  const LineResult({
    required this.original,
    required this.start,
    required this.end,
    required this.poemId,
    required this.lineId,
    required this.title,
    required this.poet,
    required this.lineCount,
  });

  /// Line text exactly as stored (with tashkeel and punctuation).
  final String original;

  /// Highlight span `[start, end)` into [original]; `-1` when unresolved.
  final int start;
  final int end;

  final int poemId;
  final int lineId;
  final String title;
  final String poet;

  /// Number of lines in the owning poem (from `poem.line_count`).
  final int lineCount;
}

/// Owns the SQLite connection and the (small) in-memory poet index.
///
/// Structured browsing (poets, poems, a poem's lines) goes straight to SQLite.
/// Tashkeel-aware line search runs a coarse SQL pre-filter (an FTS5 trigram
/// `LIKE` over a pre-normalized `plain` column, built by `tool/build_index.dart`)
/// and then confirms each candidate with the precise regex in Dart. Only poet
/// names — few enough to hold in memory — keep the old fully in-memory search.
class PoemRepository {
  PoemRepository._(this._db);

  final Database _db;

  final List<SearchEntry> _poetIndex = [];
  final List<String> _poets = [];

  /// Distinct poet names, sorted.
  List<String> get poets => List.unmodifiable(_poets);

  /// Opens the database (copying the asset to a writable location on first run)
  /// and loads the poet index. Call once at startup.
  static Future<PoemRepository> open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = await _ensureWritableDbCopy();
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final repo = PoemRepository._(db);
    await repo._loadPoets();
    return repo;
  }

  /// Copies the bundled asset DB into the app-support directory, but only when
  /// no up-to-date copy already exists — the copy is guarded by a version
  /// marker file so it is redone only when a new asset ships ([_dbAssetVersion]),
  /// not on every launch. Returns the writable path.
  static Future<String> _ensureWritableDbCopy() async {
    final supportDir = await getApplicationSupportDirectory();
    final target = p.join(supportDir.path, _dbFileName);
    final marker = File('$target.version');

    final upToDate = await File(target).exists() &&
        await marker.exists() &&
        (await marker.readAsString()).trim() == _dbAssetVersion;
    if (upToDate) return target;

    final bytes = await rootBundle.load(_assetDbPath);
    await File(target).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    await marker.writeAsString(_dbAssetVersion, flush: true);
    return target;
  }

  Future<void> _loadPoets() async {
    final poetRows = await _db.rawQuery(
      'SELECT DISTINCT poet FROM poem '
      "WHERE poet IS NOT NULL AND poet <> '' ORDER BY poet",
    );
    for (var i = 0; i < poetRows.length; i++) {
      final name = poetRows[i]['poet'] as String;
      _poets.add(name);
      _poetIndex.add(
        SearchEntry(original: name, lineId: i, poemId: 0, lineNumber: 0),
      );
    }
  }

  /// Poem for a given id, queried on demand.
  Future<Poem?> poemById(int id) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM poem WHERE id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : Poem.fromRow(rows.first);
  }

  /// Poems by a given poet, ordered by id.
  Future<List<Poem>> poemsByPoet(String poet) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM poem WHERE poet = ? ORDER BY id',
      [poet],
    );
    return rows.map(Poem.fromRow).toList();
  }

  /// Lines of a poem, ordered for display.
  Future<List<PoemLine>> linesOfPoem(int poemId) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM lines WHERE poem_id = ? ORDER BY line_number, id',
      [poemId],
    );
    return rows.map(PoemLine.fromRow).toList();
  }

  /// Tashkeel-aware search over all verses. When [poet] is given, results are
  /// restricted to that poet's poems (used for poet-scoped search).
  ///
  /// Runs the coarse filter in SQL (trigram FTS `LIKE`, or a bounded fallback
  /// scan for probes shorter than a trigram) and confirms each candidate with
  /// the precise regex, stopping once [_resultLimit] confirmed matches are
  /// found. Poem metadata is joined in so results render with no extra lookups.
  Future<List<LineResult>> searchLines(String query, {String? poet}) async {
    final regex = buildRegex(query);
    if (regex == null) return const [];

    final candidates = await _coarseCandidates(coarseProbe(query), poet);

    final results = <LineResult>[];
    for (final row in candidates) {
      final original = (row['line'] as String?) ?? '';
      final span = confirmSpan(original, regex);
      if (span == null) continue;
      results.add(LineResult(
        original: original,
        start: span.start,
        end: span.end,
        poemId: row['poem_id'] as int,
        lineId: row['id'] as int,
        title: (row['title'] as String?) ?? '',
        poet: (row['poet'] as String?) ?? '',
        lineCount: (row['line_count'] as int?) ?? 0,
      ));
      if (results.length >= _resultLimit) break;
    }
    return results;
  }

  /// Runs the coarse SQL pre-filter and returns candidate rows (line + poem
  /// metadata) for the precise regex to confirm.
  Future<List<Map<String, Object?>>> _coarseCandidates(
    CoarseProbe probe,
    String? poet,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    final String from;

    if (probe.canUseIndex) {
      // Trigram-accelerated substring lookup over the pre-normalized text.
      from = 'lines_fts f '
          'JOIN lines l ON l.id = f.rowid '
          'JOIN poem p ON p.id = l.poem_id';
      where.add("f.plain LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(probe.probe)}%');
    } else {
      // Probe too short for the trigram index (or empty): fall back to a
      // bounded scan on the plain column, leaning on LIMIT + regex confirm.
      from = 'lines l JOIN poem p ON p.id = l.poem_id';
      if (probe.probe.isNotEmpty) {
        where.add("l.plain LIKE ? ESCAPE '\\'");
        args.add('%${_escapeLike(probe.probe)}%');
      }
    }
    if (poet != null) {
      where.add('p.poet = ?');
      args.add(poet);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT l.id, l.poem_id, l.line, l.line_number, '
      'p.title, p.poet, p.line_count '
      'FROM $from $whereSql LIMIT ?',
      args,
    );
  }

  /// Escapes the SQL `LIKE` metacharacters (`%`, `_`, `\`) so the probe is
  /// matched literally under `ESCAPE '\'`.
  static String _escapeLike(String s) =>
      s.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

  /// Tashkeel-aware search over poet names; returns the matching poet names.
  List<String> searchPoets(String query) =>
      searchEntries(_poetIndex, query).map((m) => m.entry.original).toList();

  Future<void> close() => _db.close();
}
