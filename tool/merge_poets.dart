// Merges poet-name spelling variants that differ in tashkeel/tatweel/
// whitespace/punctuation, and recovers the real name from a handful of known
// trailing-junk shapes (era/meter/date parenthetical tags, dangling trailing
// punctuation, leading scrape artifacts — see lib/db/poet_dedup.dart's
// `extractPoetName`). Every group with >1 distinct spelling gets merged into
// one canonical `poet` row (poems repointed, old rows dropped); a group with
// only 1 spelling whose cleaned name differs from what's stored gets renamed
// in place.
//
//     dart run tool/merge_poets.dart [path-to-db=assets/database/DB_Poems.db] [--dry-run]
//
// Run this after `tool/normalize_metadata.dart` and `tool/normalize_poet.dart`
// (it keys its source-priority tie-break off `poem.source_id` and merges rows
// in the `poet` lookup table via `poem.poet_id`).
//
// Canonical spelling per group: lowest `source_id` among the sources that use
// a spelling, then richest vocalization, then highest usage count, then
// lexicographic — see lib/db/poet_dedup.dart.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/db/poet_dedup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final dbPath =
      File(positional.isNotEmpty ? positional.first : 'assets/database/DB_Poems.db')
          .absolute
          .path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: dryRun),
  );
  try {
    final rows = await db.rawQuery(
      'SELECT po.id AS poet_id, po.name, p.source_id, COUNT(*) AS c '
      'FROM poem p JOIN poet po ON po.id = p.poet_id '
      'GROUP BY po.id, p.source_id',
    );
    final idByName = <String, int>{};
    final variants = <PoetVariant>[];
    for (final r in rows) {
      final name = r['name'] as String;
      idByName[name] = r['poet_id'] as int;
      variants.add(PoetVariant(
        name: name,
        count: r['c'] as int,
        sourcePriority: (r['source_id'] as int?) ?? 99,
      ));
    }
    final groups = groupPoetVariants(variants);

    // One plan per group that actually needs a change: which existing row
    // survives (`targetName`, chosen by `bestStoredPoetName` so it's always a
    // real `poet.name`), what it should end up named (`canonicalName`, which
    // may not match any stored row — e.g. after stripping a trailing tag),
    // and which other rows in the group get merged into it.
    final plans = <_Plan>[];
    for (final group in groups.values) {
      final distinctNames = {for (final v in group) v.name};
      final canonical = canonicalPoetName(group);
      if (distinctNames.length == 1 && distinctNames.first == canonical) {
        continue; // already correct, nothing to do
      }
      final targetName = bestStoredPoetName(group);
      plans.add(_Plan(
        targetName: targetName,
        canonicalName: canonical,
        mergedAway: distinctNames.where((n) => n != targetName).toList(),
      ));
    }

    if (dryRun) {
      var renamed = 0;
      for (final plan in plans) {
        if (plan.targetName != plan.canonicalName) {
          print('${plan.targetName}  ->  ${plan.canonicalName}');
          renamed++;
        }
        for (final old in plan.mergedAway) {
          print('$old  ->  ${plan.canonicalName}');
          renamed++;
        }
      }
      print('$renamed spelling(s) would be renamed across ${plans.length} '
          'group(s).');
      return;
    }

    var renamed = 0;
    // A temp index makes each repoint an index lookup instead of a full scan
    // of `poem` (the asset ships without idx_poem_poet_id).
    await db.execute('CREATE INDEX IF NOT EXISTS idx_poem_poet_id ON poem(poet_id)');
    await db.transaction((txn) async {
      for (final plan in plans) {
        final targetId = idByName[plan.targetName]!;
        // Merge away the other rows *before* renaming the target: one of
        // them may already hold exactly `canonicalName` (e.g. a bare "اسم"
        // variant alongside a junky "اسم:" one), and `poet.name` is UNIQUE —
        // renaming first would collide with a row that's about to be deleted
        // anyway.
        for (final old in plan.mergedAway) {
          final oldId = idByName[old]!;
          await txn.rawUpdate(
            'UPDATE poem SET poet_id = ? WHERE poet_id = ?',
            [targetId, oldId],
          );
          await txn.rawDelete('DELETE FROM poet WHERE id = ?', [oldId]);
          renamed++;
        }
        if (plan.targetName != plan.canonicalName) {
          await txn.rawUpdate(
            'UPDATE poet SET name = ? WHERE id = ?',
            [plan.canonicalName, targetId],
          );
          renamed++;
        }
      }
    });
    await db.execute('DROP INDEX IF EXISTS idx_poem_poet_id');

    print('Renamed $renamed poet spelling(s) across ${plans.length} group(s).');
  } finally {
    await db.close();
  }
}

class _Plan {
  const _Plan({
    required this.targetName,
    required this.canonicalName,
    required this.mergedAway,
  });

  /// The existing `poet.name` row that survives — poems from [mergedAway]
  /// rows get repointed to it.
  final String targetName;

  /// What [targetName]'s row should be renamed to (may equal [targetName]
  /// already, in which case no rename is needed).
  final String canonicalName;

  /// Other stored spellings in this group, merged into [targetName].
  final List<String> mergedAway;
}
