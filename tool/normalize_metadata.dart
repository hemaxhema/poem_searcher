// Normalizes repeated-text metadata columns on `poem` (and, where actually
// read, `poem_alias`) into id-referenced lookup tables / small integers, to
// shrink the shipped asset:
//
//   * `poem.book` TEXT, `poem.type` TEXT  -> `book`/`type` lookup tables +
//     `poem.book_id`/`poem.type_id` INTEGER.
//   * `poem.source_name` TEXT (only 4 distinct values) -> a `source` lookup
//     table + `poem.source_id` INTEGER REFERENCES source(id), with
//     `source.id` fixed to `Source.values`' index (not autoincrement) since
//     the mapping is already a fixed Dart enum.
//   * `poem.source_url` TEXT keeps its name, but stores only the suffix after
//     that row's `Source.urlPrefix` from here on; the app expands it back to
//     a full URL at read time.
//
// `poem_alias.source_name`/`source_url` get the same `source_id`/suffix
// treatment (they're the only `poem_alias` columns actually read, by
// `sourcesOfPoem`); `poem_alias.poet`/`book`/`page`/`type` are write-only
// provenance and are left untouched.
//
//     dart run tool/normalize_metadata.dart [path-to-db=assets/database/DB_Poems.db]
//
// Run once, before `tool/merge_poets.dart` (which keys off `source_id`) and
// before re-running `tool/make_lean_db.dart` to reclaim the freed bytes.
// Back up the database first — this uses `DROP COLUMN` and is not undoable
// in place (though it is logically lossless: book_id/type_id/source_id plus
// `Source.urlPrefix` can reconstruct every dropped value exactly).
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/models/source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final dbPath =
      File(args.isNotEmpty ? args.first : 'assets/database/DB_Poems.db')
          .absolute
          .path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    if (await _hasColumn(db, 'poem', 'source_id')) {
      stderr.writeln(
          'poem.source_id already exists — DB looks already migrated. Aborting.');
      exitCode = 1;
      return;
    }

    final sw = Stopwatch()..start();

    print('Creating book/type/source lookup tables …');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS book (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS type (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS source (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, url_prefix TEXT)');
    await db.execute(
        "INSERT INTO book(name) SELECT DISTINCT book FROM poem WHERE book IS NOT NULL AND book <> ''");
    await db.execute(
        "INSERT INTO type(name) SELECT DISTINCT type FROM poem WHERE type IS NOT NULL AND type <> ''");
    final sourceBatch = db.batch();
    for (final source in Source.values) {
      sourceBatch.insert('source', {
        'id': source.index,
        'name': source.displayName,
        'url_prefix': source.urlPrefix,
      });
    }
    await sourceBatch.commit(noResult: true);
    final bookCount =
        (await db.rawQuery('SELECT COUNT(*) c FROM book')).first['c'] as int;
    final typeCount =
        (await db.rawQuery('SELECT COUNT(*) c FROM type')).first['c'] as int;

    print('Adding book_id/type_id/source_id columns …');
    await db.execute('ALTER TABLE poem ADD COLUMN book_id INTEGER REFERENCES book(id)');
    await db.execute('ALTER TABLE poem ADD COLUMN type_id INTEGER REFERENCES type(id)');
    await db.execute('ALTER TABLE poem ADD COLUMN source_id INTEGER REFERENCES source(id)');
    await db.execute('ALTER TABLE poem_alias ADD COLUMN source_id INTEGER REFERENCES source(id)');

    print('Backfilling book_id/type_id …');
    await db.execute('''
      UPDATE poem SET book_id = (SELECT b.id FROM book b WHERE b.name = poem.book)
      WHERE poem.book IS NOT NULL AND poem.book <> ''
    ''');
    await db.execute('''
      UPDATE poem SET type_id = (SELECT t.id FROM type t WHERE t.name = poem.type)
      WHERE poem.type IS NOT NULL AND poem.type <> ''
    ''');

    print('Backfilling source_id …');
    for (final source in Source.values) {
      await db.rawUpdate(
        'UPDATE poem SET source_id = ? WHERE source_name = ?',
        [source.index, source.displayName],
      );
      await db.rawUpdate(
        'UPDATE poem_alias SET source_id = ? WHERE source_name = ?',
        [source.index, source.displayName],
      );
    }

    await _verifyBackfill(db);
    await _checkSourceUrlCollisions(db);

    print('Rewriting source_url to suffix-only …');
    for (final source in Source.values) {
      final prefix = source.urlPrefix;
      if (prefix == null) continue;
      await db.rawUpdate(
        'UPDATE poem SET source_url = substr(source_url, ?) '
        'WHERE source_id = ? AND source_url IS NOT NULL',
        [prefix.length + 1, source.index],
      );
      await db.rawUpdate(
        'UPDATE poem_alias SET source_url = substr(source_url, ?) '
        'WHERE source_id = ? AND source_url IS NOT NULL',
        [prefix.length + 1, source.index],
      );
    }

    print('Dropping old columns …');
    await db.execute('DROP INDEX IF EXISTS idx_poem_source_name');
    await db.execute('DROP INDEX IF EXISTS idx_poem_alias_source');
    await db.execute('ALTER TABLE poem DROP COLUMN book');
    await db.execute('ALTER TABLE poem DROP COLUMN type');
    await db.execute('ALTER TABLE poem DROP COLUMN source_name');
    await db.execute('ALTER TABLE poem_alias DROP COLUMN source_name');

    print('Compacting (VACUUM) …');
    await db.execute('VACUUM');

    final poemCount =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final aliasCount =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem_alias')).first['c'] as int;
    print('Done in ${sw.elapsed.inSeconds}s.');
    print('book: $bookCount entries, type: $typeCount entries');
    print('poem rows: $poemCount, poem_alias rows: $aliasCount');
  } finally {
    await db.close();
  }
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}

/// Aborts (leaving the DB untouched beyond this point) if any row failed to
/// get a `source_id`, or a non-empty `book`/`type` failed to get its `_id`.
Future<void> _verifyBackfill(Database db) async {
  final checks = <String, String>{
    'poem.source_id':
        'SELECT COUNT(*) c FROM poem WHERE source_id IS NULL',
    'poem_alias.source_id':
        'SELECT COUNT(*) c FROM poem_alias WHERE source_id IS NULL',
    'poem.book_id':
        "SELECT COUNT(*) c FROM poem WHERE book IS NOT NULL AND book <> '' AND book_id IS NULL",
    'poem.type_id':
        "SELECT COUNT(*) c FROM poem WHERE type IS NOT NULL AND type <> '' AND type_id IS NULL",
  };
  for (final entry in checks.entries) {
    final n = (await db.rawQuery(entry.value)).first['c'] as int;
    if (n > 0) {
      stderr.writeln('${entry.key}: $n row(s) failed to backfill. Aborting.');
      exit(1);
    }
  }
}

/// Aborts if truncating `source_url` to a per-source suffix would collide
/// (two rows of the same source ending up with the same suffix) — reports the
/// offending poem ids instead of letting the later `UNIQUE` constraint fail
/// with no context.
Future<void> _checkSourceUrlCollisions(Database db) async {
  for (final source in Source.values) {
    final prefix = source.urlPrefix;
    if (prefix == null) continue;
    final collisions = await db.rawQuery('''
      SELECT substr(source_url, ?) AS suffix, COUNT(*) c, GROUP_CONCAT(id) ids
      FROM poem WHERE source_id = ? AND source_url IS NOT NULL
      GROUP BY suffix HAVING c > 1
    ''', [prefix.length + 1, source.index]);
    if (collisions.isNotEmpty) {
      stderr.writeln(
          'source_url suffix collisions for source_id=${source.index}:');
      for (final row in collisions) {
        stderr.writeln('  ${row['suffix']}: poem ids ${row['ids']}');
      }
      exit(1);
    }
  }
}
