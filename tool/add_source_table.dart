// Adds a `source` lookup table (mirroring `book`/`type`) and retrofits
// `poem.source_id` / `poem_alias.source_id` — until now bare `INTEGER`
// columns that only meant something via the Dart `Source` enum's index — to
// properly `REFERENCES source(id)`.
//
//     dart run tool/add_source_table.dart [path-to-db=assets/database/DB_Poems.db]
//
// `source.id` intentionally equals `Source.values[i].index` (0-based, not
// `AUTOINCREMENT`) since every reader (`Poem.fromRow`, the dedup/merge tools)
// already treats `source_id` as a `Source.values` index.
//
// SQLite can't add a column constraint via `ALTER TABLE`, so `poem` and
// `poem_alias` are rebuilt (create-copy-drop-rename) to attach the
// constraint to their existing `source_id` column, preserving every other
// column/constraint as-is. Back up the database first.
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
    if (await _hasTable(db, 'source')) {
      stderr.writeln(
          'source table already exists — DB looks already migrated. Aborting.');
      exitCode = 1;
      return;
    }
    await _expectColumns(db, 'poem', const {
      'id', 'poet_id', 'source_url', 'title', 'page', 'line_count', 'book_id',
      'type_id', 'source_id', //
    });
    await _expectColumns(db, 'poem_alias', const {
      'id', 'poem_id', 'source_url', 'poet', 'title', 'book', 'page', 'type',
      'source_id', //
    });

    final sw = Stopwatch()..start();

    print('Creating source lookup table …');
    await db.execute(
        'CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, url_prefix TEXT)');
    final batch = db.batch();
    for (final source in Source.values) {
      batch.insert('source', {
        'id': source.index,
        'name': source.displayName,
        'url_prefix': source.urlPrefix,
      });
    }
    await batch.commit(noResult: true);

    final poemsBefore =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final aliasesBefore = (await db.rawQuery('SELECT COUNT(*) c FROM poem_alias'))
        .first['c'] as int;

    print('Rebuilding poem with source_id REFERENCES source(id) …');
    await db.execute('''
      CREATE TABLE poem_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poet_id INTEGER REFERENCES poet(id),
        source_url TEXT UNIQUE,
        title TEXT,
        page TEXT,
        line_count INTEGER,
        book_id INTEGER REFERENCES book(id),
        type_id INTEGER REFERENCES type(id),
        source_id INTEGER REFERENCES source(id)
      )''');
    await db.execute('''
      INSERT INTO poem_new (id, poet_id, source_url, title, page, line_count,
                             book_id, type_id, source_id)
      SELECT id, poet_id, source_url, title, page, line_count,
             book_id, type_id, source_id FROM poem
    ''');
    await db.execute('DROP TABLE poem');
    await db.execute('ALTER TABLE poem_new RENAME TO poem');

    print('Rebuilding poem_alias with source_id REFERENCES source(id) …');
    await db.execute('''
      CREATE TABLE poem_alias_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL REFERENCES poem(id),
        source_url TEXT,
        poet TEXT,
        title TEXT,
        book TEXT,
        page TEXT,
        type TEXT,
        source_id INTEGER REFERENCES source(id)
      )''');
    await db.execute('''
      INSERT INTO poem_alias_new (id, poem_id, source_url, poet, title, book,
                                   page, type, source_id)
      SELECT id, poem_id, source_url, poet, title, book, page, type, source_id
      FROM poem_alias
    ''');
    await db.execute('DROP TABLE poem_alias');
    await db.execute('ALTER TABLE poem_alias_new RENAME TO poem_alias');

    final poemsAfter =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final aliasesAfter = (await db.rawQuery('SELECT COUNT(*) c FROM poem_alias'))
        .first['c'] as int;
    if (poemsAfter != poemsBefore || aliasesAfter != aliasesBefore) {
      stderr.writeln('Row count mismatch after rebuild: '
          'poem $poemsBefore -> $poemsAfter, poem_alias $aliasesBefore -> $aliasesAfter. '
          'Aborting before VACUUM.');
      exit(1);
    }

    print('Compacting (VACUUM) …');
    await db.execute('VACUUM');
    print('Done in ${sw.elapsed.inSeconds}s.');
    print('source: ${Source.values.length} entries');
    print('poem rows: $poemsAfter, poem_alias rows: $aliasesAfter');
  } finally {
    await db.close();
  }
}

Future<bool> _hasTable(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
    [table],
  );
  return rows.isNotEmpty;
}

/// Aborts if [table]'s actual columns don't match [expected] exactly — this
/// script hardcodes the rebuilt `CREATE TABLE` statements, so a schema drift
/// since this was written must fail loudly rather than silently drop data.
Future<void> _expectColumns(
    Database db, String table, Set<String> expected) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  final actual = {for (final r in rows) r['name'] as String};
  if (actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    stderr.writeln('$table columns changed since this script was written.');
    stderr.writeln('  expected: $expected');
    stderr.writeln('  actual:   $actual');
    exit(1);
  }
}
