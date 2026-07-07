// Shrinks the database to the "lean" form that ships with the app: drops the
// derived search structures — `lines.plain`, `poem.title_plain`, the
// `lines_fts` trigram index, and the secondary indexes — all of which the app
// rebuilds locally on first launch (see lib/db/search_index.dart). This more
// than halves the bundled asset. (The UNIQUE index on `poem.source_url` is
// intrinsic to the table constraint and is kept.)
//
//     dart run tool/make_lean_db.dart [path-to-db=assets/database/DB_Poems.db]
//
// Destructive but recoverable: the dropped data is fully regenerable with
// `dart run tool/build_index.dart <db>`. VACUUM at the end reclaims the freed
// pages so the file actually shrinks.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final dbPath =
      File(args.isNotEmpty ? args.first : 'assets/database/DB_Poems.db')
          .absolute
          .path;
  final file = File(dbPath);
  if (!file.existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  final beforeMb = file.lengthSync() / 1048576.0;
  print('Leaning $dbPath (${beforeMb.toStringAsFixed(0)} MB) …');

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    final sw = Stopwatch()..start();

    // Dropping the FTS virtual table removes all its shadow tables too.
    await db.execute('DROP TABLE IF EXISTS lines_fts');

    if (await _hasColumn(db, 'lines', 'plain')) {
      print('Dropping lines.plain …');
      await db.execute('ALTER TABLE lines DROP COLUMN plain');
    }
    if (await _hasColumn(db, 'poem', 'title_plain')) {
      print('Dropping poem.title_plain …');
      await db.execute('ALTER TABLE poem DROP COLUMN title_plain');
    }

    // Secondary indexes are rebuilt on first launch by _ensureIndexes; drop
    // them here so they don't bloat the shipped asset. (sqlite_autoindex_* for
    // the UNIQUE source_url constraint cannot be dropped and is left intact.)
    print('Dropping secondary indexes …');
    for (final idx in const [
      'idx_lines_poem',
      'idx_poem_poet',
      'idx_poem_source_name',
      'idx_poem_alias_poem',
      'idx_poem_alias_source',
    ]) {
      await db.execute('DROP INDEX IF EXISTS $idx');
    }

    print('Compacting (VACUUM) …');
    await db.execute('VACUUM');
    print('Done in ${sw.elapsed.inSeconds}s.');
  } finally {
    await db.close();
  }

  final afterMb = File(dbPath).lengthSync() / 1048576.0;
  print('Size: ${beforeMb.toStringAsFixed(0)} MB -> '
      '${afterMb.toStringAsFixed(0)} MB');
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}
