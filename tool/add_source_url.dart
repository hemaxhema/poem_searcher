// Adds `source.url_prefix`, mirroring `Source.values[i].urlPrefix` into the
// `source` lookup table (see tool/add_source_table.dart) the same way
// `source.name` mirrors `Source.values[i].displayName`. `null` for `moktoum`,
// which has no source URL.
//
//     dart run tool/add_source_url.dart [path-to-db=assets/database/DB_Poems.db]
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
    if (await _hasColumn(db, 'source', 'url_prefix')) {
      stderr.writeln(
          'source.url_prefix already exists — DB looks already migrated. Aborting.');
      exitCode = 1;
      return;
    }

    print('Adding source.url_prefix column …');
    await db.execute('ALTER TABLE source ADD COLUMN url_prefix TEXT');

    print('Backfilling url_prefix …');
    final batch = db.batch();
    for (final source in Source.values) {
      batch.update('source', {'url_prefix': source.urlPrefix},
          where: 'id = ?', whereArgs: [source.index]);
    }
    await batch.commit(noResult: true);

    final rows = await db.rawQuery('SELECT id, name, url_prefix FROM source ORDER BY id');
    for (final row in rows) {
      print('  ${row['id']}: ${row['name']} -> ${row['url_prefix']}');
    }
  } finally {
    await db.close();
  }
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}
