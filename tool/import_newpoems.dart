// One-off importer: copies the poems from `newpoems.db` into the bundled
// `DB_Poems.db`, tagging them as a fourth data source ("موسوعة آل مكتوم").
//
// Run once:
//
//     dart run tool/import_newpoems.dart \
//         [target=assets/database/DB_Poems.db] [source=assets/database/newpoems.db]
//
// Then rebuild the search index so the new rows get `plain` / `title_plain` /
// `line_count` / FTS entries exactly like every other row:
//
//     dart run tool/build_index.dart assets/database/DB_Poems.db
//
// What it does:
//   Streams every non-empty `poems` row from the source DB, splits its single
//   `text` blob into per-verse `lines`, and inserts a `poem` row (source_url
//   NULL, source_id = Source.moktoum.index, poet_id resolved/created in the
//   `poet` lookup table, title = first hemistich) plus its lines.
//   `plain`/`title_plain`/`line_count` are left NULL here and filled by
//   build_index.dart. Requires the `poet` lookup table to already exist (see
//   tool/normalize_poet.dart).
//
// Verse transformation mirrors the existing "شطر = شطر" line shape: the source
// separates the two hemistiches of a verse with ` ... ` (and, in some poems, `_`);
// both are replaced with `=`, then whitespace is collapsed.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/models/source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Poems pulled from the source DB per streamed batch.
const int _batchSize = 5000;

final RegExp _whitespaceRe = RegExp(r'\s+');

/// Turns one raw verse line from the source `text` into the stored `line` shape:
/// replace the hemistich separators (`...` / `_`) with `=` and collapse
/// whitespace. Returns an empty string for blank/whitespace-only lines.
String transformVerse(String raw) => raw
    .replaceAll('...', '=')
    .replaceAll('_', '=')
    .replaceAll(_whitespaceRe, ' ')
    .trim();

/// Splits a poem's `text` blob into transformed, non-empty verse lines.
List<String> splitVerses(String text) => text
    .split('\n')
    .map(transformVerse)
    .where((v) => v.isNotEmpty)
    .toList();

/// Title = first hemistich (text before the first ` = `) of the first verse,
/// matching the existing poems' convention.
String titleFromVerses(List<String> verses) => verses.first.split(' = ').first;

Future<void> main(List<String> args) async {
  final targetPath = File(args.isNotEmpty ? args[0] : 'assets/database/DB_Poems.db')
      .absolute
      .path;
  final sourcePath =
      File(args.length > 1 ? args[1] : 'assets/database/newpoems.db')
          .absolute
          .path;

  for (final path in [targetPath, sourcePath]) {
    if (!File(path).existsSync()) {
      stderr.writeln('Database not found: $path');
      exitCode = 1;
      return;
    }
  }

  sqfliteFfiInit();
  final target = await databaseFactoryFfi.openDatabase(targetPath);
  final source = await databaseFactoryFfi.openDatabase(
    sourcePath,
    options: OpenDatabaseOptions(readOnly: true),
  );

  try {
    final sw = Stopwatch()..start();

    final imported = await _importPoems(source, target);

    print('Imported $imported poems in ${sw.elapsed.inSeconds}s.');
    print('Next: dart run tool/build_index.dart $targetPath');
  } finally {
    await source.close();
    await target.close();
  }
}

/// Resolves [poet] (normalizing '' to null, like the app renders "غير مسجل"
/// for a missing poet) to its `poet.id`, inserting a new lookup row if this
/// spelling hasn't been seen before.
Future<int?> _poetIdFor(Transaction txn, String? poet) async {
  if (poet == null || poet.isEmpty) return null;
  final existing = await txn.rawQuery('SELECT id FROM poet WHERE name = ?', [poet]);
  if (existing.isNotEmpty) return existing.first['id'] as int;
  return txn.insert('poet', {'name': poet});
}

/// Streams source poems and inserts them (plus their lines) into [target].
/// Returns the number of poems inserted.
Future<int> _importPoems(Database source, Database target) async {
  final total = (await source
      .rawQuery("SELECT COUNT(*) AS c FROM poems WHERE text IS NOT NULL AND text <> ''"))
      .first['c'] as int;
  print('Importing $total poems from source …');

  var lastId = 0;
  var inserted = 0;
  while (true) {
    final rows = await source.rawQuery(
      "SELECT id, poet_name, text FROM poems "
      "WHERE id > ? AND text IS NOT NULL AND text <> '' "
      "ORDER BY id LIMIT ?",
      [lastId, _batchSize],
    );
    if (rows.isEmpty) break;

    await target.transaction((txn) async {
      for (final row in rows) {
        lastId = row['id'] as int;
        final verses = splitVerses(row['text'] as String);
        if (verses.isEmpty) continue;

        final poet = row['poet_name'] as String?;
        final poemId = await txn.insert('poem', {
          'poet_id': await _poetIdFor(txn, poet),
          'source_url': null,
          'title': titleFromVerses(verses),
          'book_id': null,
          'page': null,
          'type_id': null,
          'source_id': Source.moktoum.index,
        });

        final batch = txn.batch();
        for (var i = 0; i < verses.length; i++) {
          batch.insert('lines', {
            'poem_id': poemId,
            'line': verses[i],
            'line_number': i + 1,
            'line_type': '',
          });
        }
        await batch.commit(noResult: true);
        inserted++;
      }
    });

    print('  $inserted / $total');
  }
  return inserted;
}
