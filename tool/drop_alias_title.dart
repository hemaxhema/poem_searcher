// Drops the dead `poem_alias.title` column: leftover from before
// `tool/dedup_poems.dart`'s current schema (which never writes it), holding
// the original title text of each merged-away duplicate poem. Nothing in the
// app or any tool reads or writes it (see `tool/normalize_metadata.dart`,
// which normalizes every other `poem_alias` column that's actually read but
// deliberately left `title`/`poet`/`book`/`page`/`type` untouched).
//
//     dart run tool/drop_alias_title.dart [path-to-db=assets/database/DB_Poems.db]
//
// Back up the database first — this uses DROP COLUMN and is not undoable in
// place, and unlike the other normalize_metadata.dart drops, this data is not
// reconstructible (the deleted poem's exact original title text is gone).
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
    if (!await _hasColumn(db, 'poem_alias', 'title')) {
      stderr.writeln('poem_alias.title already gone — nothing to do.');
      exitCode = 1;
      return;
    }

    final sw = Stopwatch()..start();
    final before =
        (await db.rawQuery('SELECT SUM(LENGTH(title)) c FROM poem_alias'))
            .first['c'] as int?;

    print('Dropping poem_alias.title ($before bytes) …');
    await db.execute('ALTER TABLE poem_alias DROP COLUMN title');

    print('Compacting (VACUUM) …');
    await db.execute('VACUUM');

    final rows =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem_alias')).first['c']
            as int;
    print('Done in ${sw.elapsed.inSeconds}s. poem_alias rows: $rows');
  } finally {
    await db.close();
  }
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}
