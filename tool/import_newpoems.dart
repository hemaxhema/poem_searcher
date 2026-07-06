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
//   1. Adds a `poem.source_name` TEXT column (if missing).
//   2. Backfills `source_name` for the existing three URL-based sources.
//   3. Streams every non-empty `poems` row from the source DB, splits its single
//      `text` blob into per-verse `lines`, and inserts a `poem` row (source_url
//      NULL, source_name "موسوعة آل مكتوم", title = first hemistich) plus its
//      lines. `plain`/`title_plain`/`line_count` are left NULL here and filled by
//      build_index.dart.
//
// Verse transformation mirrors the existing "شطر = شطر" line shape: the source
// separates the two hemistiches of a verse with ` ... ` (and, in some poems, `_`);
// both are replaced with `=`, then whitespace is collapsed.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Poems pulled from the source DB per streamed batch.
const int _batchSize = 5000;

/// Source-name label for the imported poems (the fourth data source).
const String _moktoumSourceName = 'موسوعة آل مكتوم';

/// The existing three URL-based sources: `source_url` prefix → display name.
const Map<String, String> _urlSourceNames = {
  'https://uqu.edu.sa/%': 'موسوعة أم القرى',
  'https://poetry.dct.gov.ae/%': 'الموسوعة الشعرية',
  'https://www.aldiwan.net/%': 'الديوان',
};

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

    await _addSourceNameColumn(target);
    await _backfillUrlSources(target);
    final imported = await _importPoems(source, target);

    print('Imported $imported poems in ${sw.elapsed.inSeconds}s.');
    print('Next: dart run tool/build_index.dart $targetPath');
  } finally {
    await source.close();
    await target.close();
  }
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((r) => r['name'] == column);
}

Future<void> _addSourceNameColumn(Database db) async {
  if (!await _hasColumn(db, 'poem', 'source_name')) {
    print('Adding poem.source_name column …');
    await db.execute('ALTER TABLE poem ADD COLUMN source_name TEXT');
  }
}

Future<void> _backfillUrlSources(Database db) async {
  print('Backfilling source_name for existing URL-based sources …');
  for (final entry in _urlSourceNames.entries) {
    await db.rawUpdate(
      "UPDATE poem SET source_name = ? "
      "WHERE source_url LIKE ? ESCAPE '\\' AND source_name IS NULL",
      [entry.value, entry.key],
    );
  }
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
          // Normalize '' → null so the app renders "غير مسجل" consistently.
          'poet': (poet == null || poet.isEmpty) ? null : poet,
          'source_url': null,
          'title': titleFromVerses(verses),
          'book': null,
          'page': null,
          'type': null,
          'source_name': _moktoumSourceName,
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
