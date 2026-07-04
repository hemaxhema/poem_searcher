// Offline search-index builder for the bundled poem database.
//
// Run once whenever `assets/test.db` is regenerated:
//
//     dart run tool/build_index.dart [path-to-db]   # defaults to assets/test.db
//
// It adds everything the app's scaled search needs, reusing the exact same
// Arabic normalizer the runtime search uses so the index and the queries
// normalize identically:
//
//   * `lines.plain`      — stripAll(line): diacritic/punctuation-free, folded
//                          text used as the coarse-filter key.
//   * `lines_fts`        — an FTS5 *trigram* index over `lines.plain` (external
//                          content) enabling fast substring `LIKE` lookups.
//   * `poem.line_count`  — per-poem line count, so counts are a column read.
//   * indexes on `lines(poem_id)` and `poem(poet)`.
//
// Requires the bundled SQLite (via sqflite_common_ffi, already a dependency) to
// have FTS5 + the trigram tokenizer, which the desktop build does.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/search/arabic_normalizer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Rows processed per write transaction when populating `lines.plain`.
const int _batchSize = 20000;

Future<void> main(List<String> args) async {
  // Resolve to an absolute path: sqflite_common_ffi otherwise interprets a
  // relative path under its own `.dart_tool/.../databases` directory and would
  // silently create an empty database there instead of opening this file.
  final dbPath = File(args.isNotEmpty ? args.first : 'assets/test.db').absolute.path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    final sw = Stopwatch()..start();
    print('Building search index in $dbPath …');

    await _addPlainColumn(db);
    await _populatePlain(db);
    await _buildFts(db);
    await _populateLineCounts(db);
    await _ensureIndexes(db);

    print('Compacting (VACUUM + ANALYZE) …');
    await db.execute('VACUUM');
    await db.execute('ANALYZE');

    print('Done in ${sw.elapsed.inSeconds}s.');
  } finally {
    await db.close();
  }
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

Future<void> _populatePlain(Database db) async {
  final total =
      (await db.rawQuery('SELECT COUNT(*) AS c FROM lines')).first['c'] as int;
  print('Normalizing $total lines into `plain` …');

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
    print('  $done / $total');
  }
}

Future<void> _buildFts(Database db) async {
  print('Building FTS5 trigram index …');
  await db.execute('DROP TABLE IF EXISTS lines_fts');
  await db.execute(
    "CREATE VIRTUAL TABLE lines_fts USING fts5("
    "plain, content='lines', content_rowid='id', tokenize='trigram')",
  );
  await db.execute("INSERT INTO lines_fts(lines_fts) VALUES('rebuild')");
}

Future<void> _populateLineCounts(Database db) async {
  print('Computing per-poem line counts …');
  if (!await _hasColumn(db, 'poem', 'line_count')) {
    await db.execute('ALTER TABLE poem ADD COLUMN line_count INTEGER');
  }
  await db.execute(
    'UPDATE poem SET line_count = '
    '(SELECT COUNT(*) FROM lines WHERE lines.poem_id = poem.id)',
  );
}

Future<void> _ensureIndexes(Database db) async {
  print('Ensuring indexes …');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lines_poem ON lines(poem_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_poem_poet ON poem(poet)',
  );
}
