// Normalizes `poem.poet` TEXT into a `poet(id, name)` lookup table + a
// `poem.poet_id` INTEGER column, mirroring the book/type treatment in
// tool/normalize_metadata.dart. Every distinct `poem.poet` spelling gets its
// own row here — tool/merge_poets.dart is what actually merges spelling
// variants down to one row per real poet, and it runs *after* this (it keys
// off `poem.poet_id`/`poet.id`, which only exist post-migration).
//
//     dart run tool/normalize_poet.dart [path-to-db=assets/database/DB_Poems.db]
//
// Run before tool/merge_poets.dart. Back up the database first — this uses
// `DROP COLUMN` and is not undoable in place (though logically lossless:
// poet_id + the poet table can reconstruct every dropped value exactly).
//
// ignore_for_file: avoid_print
import 'dart:io';

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
    if (await _hasColumn(db, 'poem', 'poet_id')) {
      stderr.writeln(
          'poem.poet_id already exists — DB looks already migrated. Aborting.');
      exitCode = 1;
      return;
    }

    final sw = Stopwatch()..start();

    print('Creating poet lookup table …');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS poet (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)');
    await db.execute(
        "INSERT INTO poet(name) SELECT DISTINCT poet FROM poem WHERE poet IS NOT NULL AND poet <> ''");
    final poetCount =
        (await db.rawQuery('SELECT COUNT(*) c FROM poet')).first['c'] as int;

    print('Adding poem.poet_id column …');
    await db.execute('ALTER TABLE poem ADD COLUMN poet_id INTEGER REFERENCES poet(id)');

    print('Backfilling poet_id …');
    await db.execute('''
      UPDATE poem SET poet_id = (SELECT po.id FROM poet po WHERE po.name = poem.poet)
      WHERE poem.poet IS NOT NULL AND poem.poet <> ''
    ''');

    final missing = (await db.rawQuery('''
      SELECT COUNT(*) c FROM poem
      WHERE poet IS NOT NULL AND poet <> '' AND poet_id IS NULL
    ''')).first['c'] as int;
    if (missing > 0) {
      stderr.writeln('poem.poet_id: $missing row(s) failed to backfill. Aborting.');
      exit(1);
    }

    print('Dropping old poet column …');
    await db.execute('DROP INDEX IF EXISTS idx_poem_poet');
    await db.execute('ALTER TABLE poem DROP COLUMN poet');

    print('Compacting (VACUUM) …');
    await db.execute('VACUUM');

    final poemCount =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    print('Done in ${sw.elapsed.inSeconds}s.');
    print('poet: $poetCount entries, poem rows: $poemCount');
  } finally {
    await db.close();
  }
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}
