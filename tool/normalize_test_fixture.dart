// One-time migration for the small integration-test fixture
// (test_database.db) to match the normalized production schema: `poet`/
// `book`/`type`/`source` lookup tables + `poem.poet_id`/`book_id`/`type_id`/
// `source_id`, with `source_url` storing only the per-source suffix.
//
// The fixture predates even the *old* production schema — it has no
// `source_name` column and no `poem_alias` table — so
// `tool/normalize_metadata.dart`/`tool/normalize_poet.dart`/
// `tool/add_source_table.dart` don't apply to it as-is (they assume those
// already exist). This script folds the equivalent steps into one pass
// tailored to the fixture's actual (simpler) starting shape.
//
//     dart run tool/normalize_test_fixture.dart [path-to-db=test_database.db]
//
// All 20 rows in the fixture are from Source.uqu (source_url starts with its
// urlPrefix); source_id is backfilled by matching that prefix.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/models/source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final dbPath =
      File(args.isNotEmpty ? args.first : 'test_database.db').absolute.path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    if (await _hasColumn(db, 'poem', 'poet_id')) {
      stderr.writeln(
          'poem.poet_id already exists — fixture looks already migrated. Aborting.');
      exitCode = 1;
      return;
    }

    final poemsBefore =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final linesBefore =
        (await db.rawQuery('SELECT COUNT(*) c FROM lines')).first['c'] as int;

    print('Creating poet/book/type/source lookup tables …');
    await db.execute(
        'CREATE TABLE poet (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute(
        'CREATE TABLE book (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute(
        'CREATE TABLE type (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute(
        'CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, url_prefix TEXT)');

    await db.execute(
        "INSERT INTO poet(name) SELECT DISTINCT poet FROM poem WHERE poet IS NOT NULL AND poet <> ''");
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

    print('Adding poet_id/book_id/type_id/source_id columns …');
    await db
        .execute('ALTER TABLE poem ADD COLUMN poet_id INTEGER REFERENCES poet(id)');
    await db
        .execute('ALTER TABLE poem ADD COLUMN book_id INTEGER REFERENCES book(id)');
    await db
        .execute('ALTER TABLE poem ADD COLUMN type_id INTEGER REFERENCES type(id)');
    await db.execute(
        'ALTER TABLE poem ADD COLUMN source_id INTEGER REFERENCES source(id)');

    print('Backfilling poet_id/book_id/type_id …');
    await db.execute('''
      UPDATE poem SET poet_id = (SELECT po.id FROM poet po WHERE po.name = poem.poet)
      WHERE poem.poet IS NOT NULL AND poem.poet <> ''
    ''');
    await db.execute('''
      UPDATE poem SET book_id = (SELECT b.id FROM book b WHERE b.name = poem.book)
      WHERE poem.book IS NOT NULL AND poem.book <> ''
    ''');
    await db.execute('''
      UPDATE poem SET type_id = (SELECT t.id FROM type t WHERE t.name = poem.type)
      WHERE poem.type IS NOT NULL AND poem.type <> ''
    ''');

    print('Backfilling source_id from source_url prefix …');
    for (final source in Source.values) {
      final prefix = source.urlPrefix;
      if (prefix == null) continue;
      await db.rawUpdate(
        "UPDATE poem SET source_id = ? WHERE source_url LIKE ? || '%'",
        [source.index, prefix],
      );
    }

    final unresolved = (await db.rawQuery(
      'SELECT COUNT(*) c FROM poem WHERE source_id IS NULL',
    )).first['c'] as int;
    if (unresolved > 0) {
      stderr.writeln(
          '$unresolved poem(s) did not match any Source.urlPrefix. Aborting.');
      exitCode = 1;
      return;
    }

    print('Rewriting source_url to suffix-only …');
    for (final source in Source.values) {
      final prefix = source.urlPrefix;
      if (prefix == null) continue;
      await db.rawUpdate(
        'UPDATE poem SET source_url = substr(source_url, ?) '
        'WHERE source_id = ? AND source_url IS NOT NULL',
        [prefix.length + 1, source.index],
      );
    }

    print('Dropping old poet/book/type columns …');
    await db.execute('ALTER TABLE poem DROP COLUMN poet');
    await db.execute('ALTER TABLE poem DROP COLUMN book');
    await db.execute('ALTER TABLE poem DROP COLUMN type');

    print('Creating empty poem_alias table (matches production shape) …');
    await db.execute('''
      CREATE TABLE poem_alias (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id    INTEGER NOT NULL REFERENCES poem(id),
        source_url TEXT, source_id INTEGER REFERENCES source(id),
        poet TEXT, book TEXT, page TEXT, type TEXT
      )''');

    final poemsAfter =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final linesAfter =
        (await db.rawQuery('SELECT COUNT(*) c FROM lines')).first['c'] as int;
    if (poemsAfter != poemsBefore || linesAfter != linesBefore) {
      stderr.writeln('Row count mismatch: '
          'poem $poemsBefore -> $poemsAfter, lines $linesBefore -> $linesAfter.');
      exitCode = 1;
      return;
    }

    print('Done. poem rows: $poemsAfter, lines rows: $linesAfter.');
  } finally {
    await db.close();
  }
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}
