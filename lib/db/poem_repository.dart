import 'package:sqflite_common/sqlite_api.dart';

import '../models/poem.dart';
import '../models/poem_line.dart';
import '../models/source.dart';
import '../platform/database_bootstrap.dart';
import 'database_preparer.dart';
import 'memory_preset.dart';
import '../search/boolean_query.dart';
import '../search/tashkeel_search.dart';
import 'search_index.dart';

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
    required this.spans,
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
  /// Equal to `spans.first` when [spans] is non-empty.
  final int start;
  final int end;

  /// Every positive-term span confirmed for this line (a boolean AND query can
  /// match more than one term); empty when none could be resolved.
  final List<({int start, int end})> spans;

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
    required this.spans,
    required this.poet,
    required this.lineCount,
    required this.source,
  });

  final int poemId;

  /// Title text exactly as stored.
  final String title;

  /// Highlight span `[start, end)` into [title]. Equal to `spans.first` when
  /// [spans] is non-empty.
  final int start;
  final int end;

  /// Every positive-term span confirmed for this title (a boolean AND query
  /// can match more than one term); empty when none could be resolved.
  final List<({int start, int end})> spans;

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
  final Map<String, int> _poemCounts = {};

  /// Distinct poet names, sorted.
  List<String> get poets => List.unmodifiable(_poets);

  /// Number of poems attributed to [poet] (0 if unknown).
  int poemCountFor(String poet) => _poemCounts[poet] ?? 0;

  /// Opens the database and loads the poet index. Call once at startup.
  ///
  /// The bundled asset is "lean" (verse text + metadata only). The first launch
  /// — and any launch after a [dbAssetVersion] bump — copies it to a writable
  /// location and builds the `plain` / `title_plain` / trigram-FTS search index
  /// there (see [prepareDatabase]). That is a one-time, multi-minute step whose
  /// progress is reported via [onIndexProgress]; later launches reuse the built
  /// copy and open instantly. [bootstrap] supplies the platform-specific SQLite
  /// factory and file locations.
  static Future<PoemRepository> open({
    required DatabaseBootstrap bootstrap,
    IndexProgress? onIndexProgress,
    MemoryPreset preset = MemoryPreset.balanced,
  }) async {
    final dbPath =
        await prepareDatabase(bootstrap, onProgress: onIndexProgress);
    final db = await bootstrap.databaseFactory.openDatabase(
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

  Future<void> _loadPoets() async {
    final poetRows = await _db.rawQuery('''
      SELECT po.name AS name, COUNT(p.id) AS cnt
      FROM poet po
      LEFT JOIN poem p ON p.poet_id = po.id
      GROUP BY po.id
      ORDER BY po.name
    ''');
    for (var i = 0; i < poetRows.length; i++) {
      final name = poetRows[i]['name'] as String;
      _poets.add(name);
      _poemCounts[name] = poetRows[i]['cnt'] as int;
      _poetIndex.add(
        SearchEntry(original: name, lineId: i, poemId: 0, lineNumber: 0),
      );
    }
  }

  /// Columns + joins shared by [poemById]/[poemsByPoet]: resolves `poet_id`/
  /// `book_id`/`type_id` to display names via the lookup tables so
  /// `Poem.fromRow` sees the same shape it always has, and includes
  /// `source_id` for URL/source derivation.
  static const String _poemSelect = '''
    SELECT p.id, po.name AS poet, p.title, p.page, p.source_url, p.source_id, p.line_count,
           b.name AS book, t.name AS type
    FROM poem p
    LEFT JOIN poet po ON po.id = p.poet_id
    LEFT JOIN book b ON b.id = p.book_id
    LEFT JOIN type t ON t.id = p.type_id
  ''';

  /// Poem for a given id, queried on demand.
  Future<Poem?> poemById(int id) async {
    final rows = await _db.rawQuery(
      '$_poemSelect WHERE p.id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : Poem.fromRow(rows.first);
  }

  /// Poems by a given poet, ordered by id.
  Future<List<Poem>> poemsByPoet(String poet) async {
    final rows = await _db.rawQuery(
      '$_poemSelect WHERE po.name = ? ORDER BY p.id',
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
    void add(int? sourceId, String? urlSuffix) {
      if (sourceId == null || sourceId < 0 || sourceId >= Source.values.length) {
        return;
      }
      final source = Source.values[sourceId];
      final hasUrl = urlSuffix != null && urlSuffix.isNotEmpty;
      final url = hasUrl ? '${source.urlPrefix ?? ''}$urlSuffix' : null;
      if (!byName.containsKey(source.displayName) ||
          (byName[source.displayName] == null && hasUrl)) {
        byName[source.displayName] = hasUrl ? url : byName[source.displayName];
      }
    }

    final own = await _db.rawQuery(
      'SELECT source_id, source_url FROM poem WHERE id = ?',
      [poemId],
    );
    for (final r in own) {
      add(r['source_id'] as int?, r['source_url'] as String?);
    }
    // poem_alias is guaranteed to exist by the first-run index build, but guard
    // anyway so a pre-dedup DB still works.
    try {
      final aliases = await _db.rawQuery(
        'SELECT source_id, source_url FROM poem_alias WHERE poem_id = ?',
        [poemId],
      );
      for (final r in aliases) {
        add(r['source_id'] as int?, r['source_url'] as String?);
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
      (original) {
        final span = confirmSpan(original, regex);
        return span == null ? null : [span];
      },
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
  /// pulls candidate rows from [coarse], confirms each with [confirm] (a list
  /// of positive-term spans, or `null` when unmatched), ranks confirmed rows
  /// within the source by [matchTightness], and stops at [_maxResults]. Used
  /// by both the plain and boolean line searches.
  Future<List<LineResult>> _searchLinesCore(
    List<Source> order,
    Future<List<Map<String, Object?>>> Function(Source) coarse,
    List<({int start, int end})>? Function(String) confirm,
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
        final spans = confirm(original);
        if (spans == null) continue;
        final primary = spans.isEmpty ? (start: -1, end: -1) : spans.first;
        confirmed.add(LineResult(
          original: original,
          start: primary.start,
          end: primary.end,
          spans: spans,
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
      (title) {
        final span = confirmSpan(title, regex);
        return span == null ? null : [span];
      },
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
    List<({int start, int end})>? Function(String) confirm,
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
        final spans = confirm(title);
        if (spans == null) continue;
        final primary = spans.isEmpty ? (start: -1, end: -1) : spans.first;
        confirmed.add(TitleResult(
          poemId: row['id'] as int,
          title: title,
          start: primary.start,
          end: primary.end,
          spans: spans,
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
      where.add('poet_id = (SELECT id FROM poet WHERE name = ?)');
      args.add(poet);
    }
    where.add('(source_id = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = poem.id AND a.source_id = ?))');
    args.add(source.index);
    args.add(source.index);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT poem.id, poem.title, po.name AS poet, poem.line_count '
      'FROM poem LEFT JOIN poet po ON po.id = poem.poet_id '
      '$whereSql LIMIT ?',
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
          'JOIN poem p ON p.id = l.poem_id '
          'LEFT JOIN poet po ON po.id = p.poet_id';
      where.add('f.plain LIKE ?');
      args.add('%${probe.probe}%');
    } else {
      // Probe too short for the trigram index (or empty): fall back to a
      // bounded scan on the plain column, leaning on LIMIT + regex confirm.
      from = 'lines l JOIN poem p ON p.id = l.poem_id '
          'LEFT JOIN poet po ON po.id = p.poet_id';
      if (probe.probe.isNotEmpty) {
        where.add("l.plain LIKE ? ESCAPE '\\'");
        args.add('%${_escapeLike(probe.probe)}%');
      }
    }
    if (poet != null) {
      where.add('p.poet_id = (SELECT id FROM poet WHERE name = ?)');
      args.add(poet);
    }
    where.add('(p.source_id = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = p.id AND a.source_id = ?))');
    args.add(source.index);
    args.add(source.index);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT l.id, l.poem_id, l.line, l.line_number, '
      'p.title, po.name AS poet, p.line_count '
      'FROM $from $whereSql LIMIT ?',
      args,
    );
  }

  /// Boolean counterpart of [_coarseCandidates]: drives the FTS trigram index
  /// off the expression's [BoolExpr.mandatoryDriver] (a probe present in every
  /// match) when one exists; else, when [BoolExpr.driverCandidates] supplies a
  /// disjunctive set (a top-level OR whose branches each have their own
  /// driver), runs one indexed FTS query per driver and merges/de-dupes the
  /// results by line id; else falls back to a bounded scan. Always adds the
  /// expression's superset predicate ([BoolExpr.toSql]) as an extra filter.
  Future<List<Map<String, Object?>>> _coarseCandidatesBoolean(
    BoolExpr expr,
    String? poet,
    Source source,
  ) async {
    final driver = expr.mandatoryDriver();
    if (driver != null) {
      return _ftsCandidatesForDriver(driver, expr, poet, source);
    }

    final drivers = expr.driverCandidates();
    if (drivers != null) {
      // One known-good indexed FTS query per branch, merged + de-duped by
      // line id in Dart — deliberately not combined into one OR'd LIKE (see
      // _coarseCandidates for why an unverified SQL shape against lines_fts
      // is risky). Correct because each branch's own mandatoryDriver is
      // guaranteed present in every match of *that* branch, so the union of
      // per-branch supersets is a superset of the whole OR's true matches.
      final merged = <int, Map<String, Object?>>{};
      for (final d in drivers) {
        for (final row in await _ftsCandidatesForDriver(d, expr, poet, source)) {
          merged.putIfAbsent(row['id'] as int, () => row);
        }
      }
      final rows = merged.values.toList(growable: false);
      return rows.length > _candidateLimit
          ? rows.sublist(0, _candidateLimit)
          : rows;
    }

    final where = <String>[];
    final args = <Object?>[];
    const from = 'lines l JOIN poem p ON p.id = l.poem_id '
        'LEFT JOIN poet po ON po.id = p.poet_id';
    final predicate = expr.toSql('l.plain', args, _escapeLike);
    if (predicate != null) where.add(predicate);
    if (poet != null) {
      where.add('p.poet_id = (SELECT id FROM poet WHERE name = ?)');
      args.add(poet);
    }
    where.add('(p.source_id = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = p.id AND a.source_id = ?))');
    args.add(source.index);
    args.add(source.index);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT l.id, l.poem_id, l.line, l.line_number, '
      'p.title, po.name AS poet, p.line_count '
      'FROM $from $whereSql LIMIT ?',
      args,
    );
  }

  /// Runs the FTS-trigram-indexed coarse query for a single [driver] literal —
  /// the exact known-good `f.plain LIKE '%driver%'` shape (no `ESCAPE`; see
  /// [_coarseCandidates] for why), reused once for [BoolExpr.mandatoryDriver]
  /// and once per branch when [BoolExpr.driverCandidates] supplies several.
  Future<List<Map<String, Object?>>> _ftsCandidatesForDriver(
    String driver,
    BoolExpr expr,
    String? poet,
    Source source,
  ) async {
    final where = <String>['f.plain LIKE ?'];
    final args = <Object?>['%$driver%'];
    const from = 'lines_fts f '
        'JOIN lines l ON l.id = f.rowid '
        'JOIN poem p ON p.id = l.poem_id '
        'LEFT JOIN poet po ON po.id = p.poet_id';
    final predicate = expr.toSql('l.plain', args, _escapeLike);
    if (predicate != null) where.add(predicate);
    if (poet != null) {
      where.add('p.poet_id = (SELECT id FROM poet WHERE name = ?)');
      args.add(poet);
    }
    where.add('(p.source_id = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = p.id AND a.source_id = ?))');
    args.add(source.index);
    args.add(source.index);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT l.id, l.poem_id, l.line, l.line_number, '
      'p.title, po.name AS poet, p.line_count '
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
      where.add('poet_id = (SELECT id FROM poet WHERE name = ?)');
      args.add(poet);
    }
    where.add('(source_id = ? OR EXISTS (SELECT 1 FROM poem_alias a '
        'WHERE a.poem_id = poem.id AND a.source_id = ?))');
    args.add(source.index);
    args.add(source.index);

    final whereSql = 'WHERE ${where.join(' AND ')}';
    args.add(_candidateLimit);
    return _db.rawQuery(
      'SELECT poem.id, poem.title, po.name AS poet, poem.line_count '
      'FROM poem LEFT JOIN poet po ON po.id = poem.poet_id '
      '$whereSql LIMIT ?',
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
