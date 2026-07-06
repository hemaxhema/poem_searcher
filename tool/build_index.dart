// Offline search-index builder for the poem database (development helper).
//
// The app builds this same index automatically on first launch from the lean
// bundled asset (see lib/db/search_index.dart, called by PoemRepository). This
// CLI is for regenerating it during development, e.g. after re-importing poems:
//
//     dart run tool/build_index.dart [path-to-db]   # defaults to assets/test.db
//     dart run tool/build_index.dart <db> --title-plain-only
//
// The heavy lifting lives in `buildSearchIndex` so the index is produced
// identically here and in the app.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/db/search_index.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  // Resolve to an absolute path: sqflite_common_ffi otherwise interprets a
  // relative path under its own `.dart_tool/.../databases` directory and would
  // silently create an empty database there instead of opening this file.
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final dbPath =
      File(positional.isNotEmpty ? positional.first : 'assets/test.db')
          .absolute
          .path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  void report(String label, int done, int total) =>
      print(total > 0 ? '  $label: $done / $total' : '$label …');
  try {
    final sw = Stopwatch()..start();
    if (flags.contains('--title-plain-only')) {
      print('Backfilling title_plain in $dbPath …');
      await buildTitlePlainOnly(db, onProgress: report);
    } else {
      print('Building search index in $dbPath …');
      await buildSearchIndex(db, onProgress: report);
      print('Compacting (VACUUM) …');
      await db.execute('VACUUM');
    }
    print('Done in ${sw.elapsed.inSeconds}s.');
  } finally {
    await db.close();
  }
}
