/// Builds the offline search index the scaled search needs, on top of a "lean"
/// database that ships with only `lines.line` + `poem` metadata (no `plain`,
/// no `title_plain`, no `lines_fts`).
///
/// Shipping the derived structures roughly doubles the asset size, so instead
/// they are generated once, on the user's machine, the first time the app runs
/// (see [PoemRepository]) — and by `tool/build_index.dart` during development.
/// Both call [buildSearchIndex] so the index is produced identically either way,
/// reusing the exact same Arabic normalizer the runtime search uses.
///
/// Produces:
///   * `lines.plain`      — stripAll(line): the coarse-filter key.
///   * `lines_fts`        — FTS5 *trigram* index over `lines.plain`.
///   * `poem.title_plain` — stripAll(title), the title coarse-filter key.
///   * `poem.line_count`  — per-poem line count (only if missing/incomplete).
///   * indexes on `lines(poem_id)`, `poem(poet)`, `poem(source_name)`.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../search/arabic_normalizer.dart';

/// Rows processed per write transaction when normalizing text columns.
const int _batchSize = 20000;

/// Progress reporter: [label] names the current stage; [done]/[total] track
/// row progress within it, with `total == 0` meaning indeterminate.
typedef IndexProgress = void Function(String label, int done, int total);

/// Builds the full search index in [db] (opened read-write). Idempotent: safe
/// to re-run; already-present pieces are refreshed rather than duplicated.
Future<void> buildSearchIndex(Database db, {IndexProgress? onProgress}) async {
  await _addPlainColumn(db);
  await _populatePlain(db, onProgress);
  await _buildFts(db, onProgress);
  // Indexes (notably lines(poem_id)) must exist before the per-poem count
  // query, or that correlated subquery falls back to a full scan of `lines`.
  await _ensureIndexes(db);
  await _populateLineCountsIfNeeded(db, onProgress);
  await _populateTitlePlain(db, onProgress);
  onProgress?.call('إنهاء', 0, 0);
  await db.execute('ANALYZE');
}

/// Fast path: rebuild only `poem.title_plain` (used by the `--title-plain-only`
/// CLI flag when a DB was indexed by a build that predated title search).
Future<void> buildTitlePlainOnly(Database db, {IndexProgress? onProgress}) async {
  await _populateTitlePlain(db, onProgress);
  await db.execute('ANALYZE');
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}

Future<void> _addPlainColumn(Database db) async {
  if (!await _hasColumn(db, 'lines', 'plain')) {
    await db.execute('ALTER TABLE lines ADD COLUMN plain TEXT');
  }
}

Future<void> _populatePlain(Database db, IndexProgress? onProgress) async {
  final total =
      (await db.rawQuery('SELECT COUNT(*) AS c FROM lines')).first['c'] as int;

  var lastId = 0;
  var done = 0;
  while (true) {
    final rows = await db.rawQuery(
      'SELECT id, line FROM lines WHERE id > ? ORDER BY id LIMIT ?',
      [lastId, _batchSize],
    );
    if (rows.isEmpty) break;

    final batch = db.batch();
    for (final row in rows) {
      final id = row['id'] as int;
      final plain = stripAll((row['line'] as String?) ?? '');
      batch.rawUpdate('UPDATE lines SET plain = ? WHERE id = ?', [plain, id]);
      lastId = id;
    }
    await batch.commit(noResult: true);

    done += rows.length;
    onProgress?.call('تجهيز نصوص البحث', done, total);
  }
}

Future<void> _buildFts(Database db, IndexProgress? onProgress) async {
  onProgress?.call('بناء فهرس البحث', 0, 0);
  await db.execute('DROP TABLE IF EXISTS lines_fts');
  await db.execute(
    "CREATE VIRTUAL TABLE lines_fts USING fts5("
    "plain, content='lines', content_rowid='id', tokenize='trigram')",
  );
  await db.execute("INSERT INTO lines_fts(lines_fts) VALUES('rebuild')");
}

Future<void> _populateLineCountsIfNeeded(
    Database db, IndexProgress? onProgress) async {
  if (!await _hasColumn(db, 'poem', 'line_count')) {
    await db.execute('ALTER TABLE poem ADD COLUMN line_count INTEGER');
  }
  // The lean asset ships `line_count` already; only recompute if it's missing
  // for some rows (avoids a slow correlated update over every poem on launch).
  final missing = (await db.rawQuery(
    'SELECT COUNT(*) AS c FROM poem WHERE line_count IS NULL',
  )).first['c'] as int;
  if (missing == 0) return;

  onProgress?.call('حساب عدد الأبيات', 0, 0);
  await db.execute(
    'UPDATE poem SET line_count = '
    '(SELECT COUNT(*) FROM lines WHERE lines.poem_id = poem.id) '
    'WHERE line_count IS NULL',
  );
}

Future<void> _populateTitlePlain(Database db, IndexProgress? onProgress) async {
  if (!await _hasColumn(db, 'poem', 'title_plain')) {
    await db.execute('ALTER TABLE poem ADD COLUMN title_plain TEXT');
  }

  final total =
      (await db.rawQuery('SELECT COUNT(*) AS c FROM poem')).first['c'] as int;
  var lastId = 0;
  var done = 0;
  while (true) {
    final rows = await db.rawQuery(
      'SELECT id, title FROM poem WHERE id > ? ORDER BY id LIMIT ?',
      [lastId, _batchSize],
    );
    if (rows.isEmpty) break;

    final batch = db.batch();
    for (final row in rows) {
      final id = row['id'] as int;
      final plain = stripAll((row['title'] as String?) ?? '');
      batch.rawUpdate(
          'UPDATE poem SET title_plain = ? WHERE id = ?', [plain, id]);
      lastId = id;
    }
    await batch.commit(noResult: true);

    done += rows.length;
    onProgress?.call('تجهيز عناوين البحث', done, total);
  }
}

Future<void> _ensureIndexes(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lines_poem ON lines(poem_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_poem_poet ON poem(poet)',
  );
  // Per-source search groups results by `source_name`; this lets each source's
  // title-search query restrict to that source's rows instead of scanning all
  // poems (the role the UNIQUE `source_url` index played for the old
  // prefix-range filter).
  if (await _hasColumn(db, 'poem', 'source_name')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poem_source_name ON poem(source_name)',
    );
  }
}
