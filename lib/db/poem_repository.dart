import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/poem.dart';
import '../models/poem_line.dart';
import '../models/source.dart';
import 'memory_preset.dart';
import '../search/boolean_query.dart';
import '../search/tashkeel_search.dart';
import 'search_index.dart';

/// Path of the database bundled as a Flutter asset.
const String _assetDbPath = 'assets/database/DB_Poems.db';

/// File name of the writable copy in the app-support directory.
const String _dbFileName = 'DB_Poems.db';

/// Bump this whenever a new database asset ships so the previously copied
/// writable file is refreshed on next launch (see [_ensureWritableDbCopy]).
const String _dbAssetVersion = '7';

/// Upper bound on rows pulled from the coarse SQL filter before the precise
/// regex confirms them. Keeps a broad query from scanning the whole table.
///
/// Sized to let a single source supply enough confirmed rows to fill
/// [_maxResults]. Note the trade-off: for very short (1–2 char) probes that
/// miss the trigram index and fall back to a full `LIKE` scan, a higher cap
/// means a longer scan. It stays bounded here, and the 1s search debounce plus
/// the async query keep the UI responsive; tune down if that scan gets costly.
const int _candidateLimit = 8000;

/// Upper bound on confirmed results returned to the UI per search. Generous so
/// broad queries (e.g. a single Arabic letter matching thousands of lines) are
/// reachable via pagination rather than silently truncated.
const int _maxResults = 5000;

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
    required this.source,
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

  /// Data source this poem was scraped from.
  final Source source;
}

/// One confirmed poem-title search result (as opposed to a verse-line match).
class TitleResult {
  const TitleResult({
    required this.poemId,
    required this.title,
    required this.start,
    required this.end,
    required this.poet,
    required this.lineCount,
    required this.source,
  });

  final int poemId;

  /// Title text exactly as stored.
  final String title;

  /// Highlight span `[start, end)` into [title].
  final int start;
  final int end;

  final String poet;
  final int lineCount;
  final Source source;
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

  /// Opens the database and loads the poet index. Call once at startup.
  ///
  /// The bundled asset is "lean" (verse text + metadata only). The first launch
  /// — and any launch after a [_dbAssetVersion] bump — copies it to a writable
  /// location and builds the `plain` / `title_plain` / trigram-FTS search index
  /// there. That is a one-time, multi-minute step whose progress is reported via
  /// [onIndexProgress]; later launches reuse the built copy and open instantly.
  static Future<PoemRepository> open({
    IndexProgress? onIndexProgress,
    MemoryPreset preset = MemoryPreset.high,
  }) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = await _prepareDatabase(onIndexProgress);
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    await _tuneForReads(db, preset);
    final repo = PoemRepository._(db);
    await repo._loadPoets();
    return repo;
  }

  /// Applies read-tuning PRAGMAs to a freshly opened connection. These are
  /// per-connection (not persisted in the file) so they run on every [open].
  ///
  /// The database is a large read-only asset, and search is dominated by I/O
  /// over the trigram `LIKE` scans (and the short-probe fallback full scan). A
  /// memory-mapped window sized well past the file lets the OS page the whole
  /// file into virtual memory instead of round-tripping through SQLite's own
  /// page cache. [preset] lets a user on a constrained machine turn this down
  /// from the generous desktop-sized default (mmap is a virtual reservation,
  /// not committed RAM, so over-sizing it past the file is normally cheap).
  /// In-memory temp storage speeds any transient sort. No schema change, so no
  /// [_dbAssetVersion] bump is needed. Best-effort: a rejected PRAGMA must not
  /// stop the app from opening.
  static Future<void> _tuneForReads(Database db, MemoryPreset preset) async {
    try {
      await db.execute('PRAGMA mmap_size=${preset.mmapSize};');
      await db.execute('PRAGMA cache_size=${preset.cacheSizeKb};');
      await db.execute('PRAGMA temp_store=MEMORY;');
      await db.execute('PRAGMA query_only=ON;');
    } catch (_) {
      // Tuning is an optimization only; ignore if the platform rejects a PRAGMA.
    }
  }

  /// Ensures a fully-indexed, writable copy of the database exists and returns
  /// its path. The version marker is written only *after* a successful index
  /// build, so an interrupted first run re-copies and rebuilds on the next
  /// launch instead of leaving a half-built database in use.
  static Future<String> _prepareDatabase(IndexProgress? onProgress) async {
    final supportDir = await getApplicationSupportDirectory();
    final target = p.join(supportDir.path, _dbFileName);
    final marker = File('$target.version');

    final ready = await File(target).exists() &&
        await marker.exists() &&
        (await marker.readAsString()).trim() == _dbAssetVersion;
    if (ready) return target;

    await _copyAssetTo(target);

    // Build the search index in the writable copy (opened read-write).
    final db = await databaseFactory.openDatabase(target);
    try {
      await buildSearchIndex(db, onProgress: onProgress);
    } finally {
      await db.close();
    }
    await marker.writeAsString(_dbAssetVersion, flush: true);
    return target;
  }

  /// Copies the bundled (lean) asset DB to [target]. Prefers a streaming file
  /// copy of the on-disk asset — Flutter unpacks declared assets to real files
  /// under the executable's `data/flutter_assets/`, so this never holds the
  /// whole database in memory. Falls back to loading it through the asset
  /// bundle only for unusual packaging where that file can't be located.
  static Future<void> _copyAssetTo(String target) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final assetOnDisk = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      _assetDbPath,
    );
    if (await File(assetOnDisk).exists()) {
      await File(assetOnDisk).copy(target);
      return;
    }
    final bytes = await rootBundle.load(_assetDbPath);
    await File(target).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
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

  /// Every data source this poem is available from — its own, plus those of any
  /// duplicate poems merged into it (see `poem_alias`) — as `(name, url)` pairs,
  /// deduplicated by source name (preferring an entry that carries a URL). Lets
  /// the detail page link out to each source that held a copy of the poem.
  Future<List<({String name, String? url})>> sourcesOfPoem(int poemId) async {
    final byName = <String, String?>{};
    void add(String? name, String? url) {
      if (name == null || name.isEmpty) return;
      final hasUrl = url != null && url.isNotEmpty;
      if (!byName.containsKey(name) || (byName[name] == null && hasUrl)) {
        byName[name] = hasUrl ? url : byName[name];
      }
    }

    final own = await _db.rawQuery(
      'SELECT source_name, source_url FROM poem WHERE id = ?',
      [poemId],
    );
    for (final r in own) {
      add(r['source_name'] as String?, r['source_url'] as String?);
    }
    // poem_alias is guaranteed to exist by the first-run index build, but guard
    // anyway so a pre-dedup DB still works.
    try {
      final aliases = await _db.rawQuery(
        'SELECT source_name, source_url FROM poem_alias WHERE poem_id = ?',
        [poemId],
      );
      for (final r in aliases) {
        add(r['source_name'] as String?, r['source_url'] as String?);
      }
    } catch (_) {
      // poem_alias absent (DB predates dedup) — own source is enough.
    }
    return [for (final e in byName.entries) (name: e.key, url: e.value)];
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
  /// [sourceOrder] selects and orders which data sources to search;
  /// each source is queried in turn so results are grouped by source in that
  /// priority order, stopping once [_resultLimit] confirmed matches are found
  /// overall. Defaults to all sources in declared order when omitted.
  ///
  /// Runs the coarse filter in SQL (trigram FTS `LIKE`, or a bounded fallback
  /// scan for probes shorter than a trigram) and confirms each candidate with
  /// the precise regex. Within each source, confirmed matches are ranked by
  /// [matchTightness] (tighter/more-exact matches first) before the next
  /// source is considered. Poem metadata is joined in so results render with
  /// no extra lookups.
  Future<List<LineResult>> searchLines(
    String query, {
    String? poet,
    List<Source>? sourceOrder,
  }) async {
    final regex = buildRegex(query);
    if (regex == null) return const [];
    final probe = coarseProbe(query);
    return _searchLinesCore(
      sourceOrder ?? Source.values,
      (source) => _coarseCandidates(probe, poet, source),
      (original) => confirmSpan(original, regex),
    );
  }

  /// Boolean line search: same coarse-filter + Dart-confirm pipeline as
  /// [searchLines], but the candidate filter and per-row confirmation come from
  /// a parsed [BoolExpr] (AND / OR / NOT with grouping). Returns nothing when
  /// the expression has no positive term to anchor the results.
  Future<List<LineResult>> searchLinesBoolean(
    BoolExpr expr, {
    String? poet,
    List<Source>? sourceOrder,
  }) async {
    if (!expr.hasPositive) return const [];
    return _searchLinesCore(
      sourceOrder ?? Source.values,
      (source) => _coarseCandidatesBoolean(expr, poet, source),
      expr.match,
    );
  }

  /// Shared driver for the line search: iterates [order] source-by-source,
  /// pulls candidate rows from [coarse], confirms each with [confirm] (a span or
  /// `null`), ranks confirmed rows within the source by [matchTightness], and
  /// stops at [_maxResults]. Used by both the plain and boolean line searches.
  Future<List<LineResult>> _searchLinesCore(
    List<Source> order,
    Future<List<Map<String, Object?>>> Function(Source) coarse,
    ({int start, int end})? Function(String) confirm,
  ) async {
    if (order.isEmpty) return const [];
    final results = <LineResult>[];
    for (final source in order) {
      if (results.length >= _maxResults) break;
      final candidates = await coarse(source);
      final confirmed = <LineResult>[];
      var scanned = 0;
      for (final row in candidates) {
        // Yield periodically so the CPU-bound regex confirm doesn't block a
        // frame for too long, keeping the UI responsive during a broad search.
        if (++scanned % 512 == 0) await Future<void>.delayed(Duration.zero);
        final original = (row['line'] as String?) ?? '';
        final span = confirm(original);
        if (span == null) continue;
        confirmed.add(LineResult(
          original: original,
          start: span.start,
          end: span.end,
          poemId: row['poem_id'] as int,
          lineId: row['id'] as int,
          title: (row['title'] as String?) ?? '',
          poet: (row['poet'] as String?) ?? '',
          lineCount: (row['line_count'] as int?) ?? 0,
          source: source,
        ));
      }
      confirmed.sort((a, b) => matchTightness(b.start, b.end, b.original)
          .compareTo(matchTightness(a.start, a.end, a.original)));
      results.addAll(confirmed.take(_maxResults - results.length));
    }
    return results;
  }

  /// Tashkeel-aware search over poem titles (as opposed to verse lines).
  /// When [poet] is given, results are restricted to that poet's poems (used
  /// for poet-scoped search). Same source ordering/priority-grouping and
  /// within-source relevance ranking as [searchLines].
  Future<List<TitleResult>> searchTitles(
    String query, {
    String? poet,
    List<Source>? sourceOrder,
  }) async {
    final regex = buildRegex(query);
    if (regex == null) return const [];
    final probe = coarseProbe(query);
    return _searchTitlesCore(
      sourceOrder ?? Source.values,
      (source) => _coarseTitleCandidates(probe, poet, source),
      (title) => confirmSpan(title, regex),
    );
  }

  /// Boolean title search — the [searchTitles] counterpart of
  /// [searchLinesBoolean].
  Future<List<TitleResult>> searchTitlesBoolean(
    BoolExpr expr, {
    String? poet,
    List<Source>? sourceOrder,
  }) async {
    if (!expr.hasPositive) return const [];
    return _searchTitlesCore(
      sourceOrder ?? Source.values,
      (source) => _coarseTitleCandidatesBoolean(expr, poet, source),
      expr.match,
    );
  }

  /// Shared driver for the title search (see [_searchLinesCore]).
  Future<List<TitleResult>> _searchTitlesCore(
    List<Source> order,
    Future<List<Map<String, Object?>>> Function(Source) coarse,
    ({int start, int end})? Function(String) confirm,
  ) async {
    if (order.isEmpty) return const [];
    final results = <TitleResult>[];
    for (final source in order) {
      if (results.length >= _maxResults) break;
      final candidates = await coarse(source);
      final confirmed = <TitleResult>[];
      var scanned = 0;
      for (final row in candidates) {
        // Yield periodically so the CPU-bound regex confirm doesn't block a
        // frame for too long, keeping the UI responsive during a broad search.
        if (++scanned % 512 == 0) await Future<void>.delayed(Duration.zero);
        final title = (row['title'] as String?) ?? '';
        final span = confirm(title);
        if (span == null) continue;
        confirmed.add(TitleResult(
          poemId: row['id'] as int,
          title: title,
          start: span.start,
          end: span.end,
          poet: (row['poet'] as String?) ?? '',
          lineCount: (row['line_count'] as int?) ?? 0,
          source: source,
        ));
      }
      confirmed.sort((a, b) => matchTightness(b.start, b.end, b.title)
          .compareTo(matchTightness(a.start, a.end, a.title)));
      results.addAll(confirmed.take(_maxResults - results.length));
    }
    return results;
  }

  /// Runs the coarse title pre-filter (scoped to a single [source]): a direct
  /// bounded `LIKE` scan over `poem.title_plain` — no FTS index needed since
  /// `poem` (hundreds of thousands of rows) is small enough for this to stay
  /// fast on its own, unlike the multi-million-row `lines` table.
  Future<List<Map<String, Object?>>> _coarseTitleCandidates(
    CoarseProbe probe,
    String? poet,
    Source source,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    if (probe.probe.isNotEmpty) {
      where.add("title_plain LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(probe.probe)}%');
    }
    if (poet != null) {
      where.add('poet = ?');
      args.add(poet);
    }
    where.add('(source_name = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = poem.id AND a.source_name = ?))');
    args.add(source.displayName);
    args.add(source.displayName);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT id, title, poet, line_count FROM poem $whereSql LIMIT ?',
      args,
    );
  }

  /// Runs the coarse SQL pre-filter (scoped to a single [source]) and returns
  /// candidate rows (line + poem metadata) for the precise regex to confirm.
  Future<List<Map<String, Object?>>> _coarseCandidates(
    CoarseProbe probe,
    String? poet,
    Source source,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    final String from;

    if (probe.canUseIndex) {
      // Trigram-accelerated substring lookup over the pre-normalized text.
      // Deliberately no `ESCAPE` clause: confirmed empirically (EXPLAIN QUERY
      // PLAN) that adding one — even with the pattern otherwise identical —
      // makes SQLite silently fall back to a full virtual-table scan instead
      // of using the trigram index (tens of times slower on this database).
      // Safe without it: this is only a coarse pre-filter that the precise
      // Dart regex confirms exactly afterward, so a probe that happened to
      // contain a literal `%`/`_` would just make this filter a bit more
      // permissive — never cause a true match to be missed.
      from = 'lines_fts f '
          'JOIN lines l ON l.id = f.rowid '
          'JOIN poem p ON p.id = l.poem_id';
      where.add('f.plain LIKE ?');
      args.add('%${probe.probe}%');
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
    where.add('(p.source_name = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = p.id AND a.source_name = ?))');
    args.add(source.displayName);
    args.add(source.displayName);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT l.id, l.poem_id, l.line, l.line_number, '
      'p.title, p.poet, p.line_count '
      'FROM $from $whereSql LIMIT ?',
      args,
    );
  }

  /// Boolean counterpart of [_coarseCandidates]: drives the FTS trigram index
  /// off the expression's [BoolExpr.mandatoryDriver] (a probe present in every
  /// match) when one exists, else a bounded fallback scan, and adds the
  /// expression's superset predicate ([BoolExpr.toSql]) as the extra filter.
  Future<List<Map<String, Object?>>> _coarseCandidatesBoolean(
    BoolExpr expr,
    String? poet,
    Source source,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    final String from;

    final driver = expr.mandatoryDriver();
    if (driver != null) {
      // No `ESCAPE` clause — see _coarseCandidates for why.
      from = 'lines_fts f '
          'JOIN lines l ON l.id = f.rowid '
          'JOIN poem p ON p.id = l.poem_id';
      where.add('f.plain LIKE ?');
      args.add('%$driver%');
    } else {
      from = 'lines l JOIN poem p ON p.id = l.poem_id';
    }
    final predicate = expr.toSql('l.plain', args, _escapeLike);
    if (predicate != null) where.add(predicate);
    if (poet != null) {
      where.add('p.poet = ?');
      args.add(poet);
    }
    where.add('(p.source_name = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = p.id AND a.source_name = ?))');
    args.add(source.displayName);
    args.add(source.displayName);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT l.id, l.poem_id, l.line, l.line_number, '
      'p.title, p.poet, p.line_count '
      'FROM $from $whereSql LIMIT ?',
      args,
    );
  }

  /// Boolean counterpart of [_coarseTitleCandidates]: a bounded `LIKE` scan over
  /// `poem.title_plain` filtered by the expression's superset predicate.
  Future<List<Map<String, Object?>>> _coarseTitleCandidatesBoolean(
    BoolExpr expr,
    String? poet,
    Source source,
  ) async {
    final where = <String>[];
    final args = <Object?>[];

    final predicate = expr.toSql('title_plain', args, _escapeLike);
    if (predicate != null) where.add(predicate);
    if (poet != null) {
      where.add('poet = ?');
      args.add(poet);
    }
    where.add('(source_name = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = poem.id AND a.source_name = ?))');
    args.add(source.displayName);
    args.add(source.displayName);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT id, title, poet, line_count FROM poem $whereSql LIMIT ?',
      args,
    );
  }

  /// Escapes the SQL `LIKE` metacharacters (`%`, `_`, `\`) so the probe is
  /// matched literally under `ESCAPE '\'`. Only used for `LIKE` against a
  /// plain column (never the trigram FTS table — see _coarseCandidates for
  /// why `ESCAPE` must not be added there).
  static String _escapeLike(String s) =>
      s.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

  /// Tashkeel-aware search over poet names; returns the matching poet names.
  List<String> searchPoets(String query) =>
      searchEntries(_poetIndex, query).map((m) => m.entry.original).toList();

  Future<void> close() => _db.close();
}
