// Deduplicates poems: merges poems that are the same text differing only in
// tashkeel, keeping the best-vocalized copy and recording every deleted poem's
// provenance in `poem_alias` so no source metadata is lost and the survivor is
// still found when searching a source whose copy was removed.
//
//     dart run tool/dedup_poems.dart [path-to-db=assets/database/DB_Poems.db]
//
// Then rebuild the search index (the app does this automatically on first run):
//     dart run tool/build_index.dart <db>
//
// Grouping key: each poem's lines with tashkeel + tatweel stripped and
// whitespace collapsed — so a group holds poems with identical base letters
// differing only in harakat. Survivor rule (per the 3 tashkeel rules): a poem
// is deleted only if another poem in its group is a *haraka-superset* of it
// (same text, more-or-equal diacritics at every position, no disagreement);
// genuinely different vocalizations are all kept.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/db/poem_dedup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Poems scanned per DB query window (keyed by poem_id so each poem's lines
/// stay within one window).
const int _scanChunk = 20000;

/// Deletions applied per write transaction. Kept under SQLite's 999-variable
/// limit for the metadata `IN (...)` lookup.
const int _applyChunk = 500;

/// A poem in a duplicate group: its id and its cleaned lines.
class _GroupPoem {
  _GroupPoem(this.id, this.clean)
      : dia = clean.fold(0, (n, l) => n + tashkeelCount(l));
  final int id;
  final List<String> clean;
  final int dia; // total diacritics — richer vocalization wins ties for survivor
}

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
    final sw = Stopwatch()..start();

    // Needed for fast ordered scans and, crucially, fast per-poem line deletes.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_lines_poem ON lines(poem_id)');
    await _ensureAliasTable(db);

    final poemsBefore =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final linesBefore =
        (await db.rawQuery('SELECT COUNT(*) c FROM lines')).first['c'] as int;

    // Source label -> priority for survivor tie-breaks (lower wins).
    const priority = {
      'موسوعة أم القرى': 0,
      'الموسوعة الشعرية': 1,
      'الديوان': 2,
      'موسوعة آل مكتوم': 3,
    };
    final poemSource = <int, String?>{};
    for (final r in await db.rawQuery('SELECT id, source_name FROM poem')) {
      poemSource[r['id'] as int] = r['source_name'] as String?;
    }

    final range = (await db.rawQuery('SELECT MIN(id) lo, MAX(id) hi FROM poem'))
        .first;
    final minId = (range['lo'] as int?) ?? 0;
    final maxId = (range['hi'] as int?) ?? -1;

    // Pass 1: a stable hash of each poem's stripped signature; find hashes that
    // occur more than once (candidate duplicate groups).
    print('Pass 1/2: hashing poems …');
    final poemHash = <int, int>{};
    final hashCount = <int, int>{};
    await _streamPoems(db, minId, maxId, (poemId, clean) {
      final h = Object.hashAll(clean.map(strippedLine));
      poemHash[poemId] = h;
      hashCount[h] = (hashCount[h] ?? 0) + 1;
    });
    final dupHashes = <int>{
      for (final e in hashCount.entries)
        if (e.value > 1) e.key
    };

    // Pass 2: materialize only the candidate poems, bucketed by their *exact*
    // stripped signature string (so a hash collision can't merge non-duplicates).
    print('Pass 2/2: grouping ${dupHashes.length} candidate signatures …');
    final groups = <String, List<_GroupPoem>>{};
    await _streamPoems(db, minId, maxId, (poemId, clean) {
      if (!dupHashes.contains(poemHash[poemId])) return;
      final sig = clean.map(strippedLine).join('');
      (groups[sig] ??= []).add(_GroupPoem(poemId, clean));
    });

    // Resolve survivors and collect deletions (deletedId -> survivor id).
    final deletions = <int, int>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;
      // Richest first, then source priority, then lowest id — so the preferred
      // survivor is considered before the poems it might supersede.
      group.sort((a, b) {
        if (a.dia != b.dia) return b.dia - a.dia;
        final pa = priority[poemSource[a.id]] ?? 99;
        final pb = priority[poemSource[b.id]] ?? 99;
        if (pa != pb) return pa - pb;
        return a.id - b.id;
      });
      final survivors = <_GroupPoem>[];
      for (final p in group) {
        _GroupPoem? target;
        for (final s in survivors) {
          if (poemSupersets(s.clean, p.clean)) {
            target = s;
            break;
          }
        }
        if (target != null) {
          deletions[p.id] = target.id;
        } else {
          survivors.add(p);
        }
      }
    }

    print('Deleting ${deletions.length} duplicate poems …');
    await _applyDeletions(db, deletions);

    print('Dropping scan index and compacting (VACUUM) …');
    await db.execute('DROP INDEX IF EXISTS idx_lines_poem');
    await db.execute('VACUUM');

    final poemsAfter =
        (await db.rawQuery('SELECT COUNT(*) c FROM poem')).first['c'] as int;
    final linesAfter =
        (await db.rawQuery('SELECT COUNT(*) c FROM lines')).first['c'] as int;
    print('Done in ${sw.elapsed.inSeconds}s.');
    print('Poems: $poemsBefore -> $poemsAfter  (-${poemsBefore - poemsAfter})');
    print('Lines: $linesBefore -> $linesAfter  (-${linesBefore - linesAfter})');
    print('Aliases created: ${deletions.length}');
  } finally {
    await db.close();
  }
}

Future<void> _ensureAliasTable(Database db) async {
  final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='poem_alias'");
  if (existing.isNotEmpty) {
    final n = (await db.rawQuery('SELECT COUNT(*) c FROM poem_alias'))
        .first['c'] as int;
    if (n > 0) {
      stderr.writeln(
          'poem_alias already has $n rows — the DB looks already deduped. Aborting.');
      exit(1);
    }
    return;
  }
  await db.execute('''
    CREATE TABLE poem_alias (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      poem_id    INTEGER NOT NULL REFERENCES poem(id),
      source_url TEXT, source_name TEXT,
      poet TEXT, book TEXT, page TEXT, type TEXT
    )''');
}

/// Streams poems in poem_id windows, invoking [onPoem] once per poem with its
/// cleaned lines (in reading order). Keeps memory bounded to one window.
Future<void> _streamPoems(
  Database db,
  int minId,
  int maxId,
  void Function(int poemId, List<String> clean) onPoem,
) async {
  for (var lo = minId; lo <= maxId; lo += _scanChunk) {
    final hi = lo + _scanChunk - 1;
    final rows = await db.rawQuery(
      'SELECT poem_id, line FROM lines WHERE poem_id BETWEEN ? AND ? '
      'ORDER BY poem_id, line_number, id',
      [lo, hi],
    );
    var curId = -1;
    var curLines = <String>[];
    for (final r in rows) {
      final pid = r['poem_id'] as int;
      if (pid != curId) {
        if (curId != -1) onPoem(curId, curLines);
        curId = pid;
        curLines = <String>[];
      }
      curLines.add(cleanLine((r['line'] as String?) ?? ''));
    }
    if (curId != -1) onPoem(curId, curLines);
  }
}

/// Applies the deletions: writes a `poem_alias` row (with the deleted poem's
/// metadata) pointing at its survivor, then deletes the poem and its lines.
Future<void> _applyDeletions(Database db, Map<int, int> deletions) async {
  final entries = deletions.entries.toList();
  for (var i = 0; i < entries.length; i += _applyChunk) {
    final slice = entries.sublist(i, (i + _applyChunk).clamp(0, entries.length));
    final ids = slice.map((e) => e.key).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final metaRows = await db.rawQuery(
      'SELECT id, poet, source_url, source_name, book, page, type '
      'FROM poem WHERE id IN ($placeholders)',
      ids,
    );
    final meta = {for (final m in metaRows) m['id'] as int: m};

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in slice) {
        final m = meta[e.key];
        batch.insert('poem_alias', {
          'poem_id': e.value,
          'source_url': m?['source_url'],
          'source_name': m?['source_name'],
          'poet': m?['poet'],
          'book': m?['book'],
          'page': m?['page'],
          'type': m?['type'],
        });
        batch.delete('lines', where: 'poem_id = ?', whereArgs: [e.key]);
        batch.delete('poem', where: 'id = ?', whereArgs: [e.key]);
      }
      await batch.commit(noResult: true);
    });
  }
}

