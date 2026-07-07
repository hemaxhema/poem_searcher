// Measures real search-query latency against a built (fully-indexed) database,
// so the effect of the lines_fts `detail=none` change and the mmap_size /
// cache_size bump (see lib/db/poem_repository.dart) can be compared with real
// numbers instead of guesswork.
//
// Mirrors the exact coarse-query shape PoemRepository._coarseCandidates runs
// (same FTS-vs-fallback branch, same source filter across all 4 sources, same
// LIMIT), so the timings reflect what a real search in the app does.
//
//     dart run tool/benchmark_search.dart <path-to-db> [--mmap=BYTES] [--cache=KB]
//
// Run once against the OLD writable copy (before relaunching the app) for a
// baseline, then again against the NEW one (after the app rebuilds it, or
// after `dart run tool/build_index.dart` on a fresh copy) to compare.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:poem_searcher/models/source.dart';
import 'package:poem_searcher/search/tashkeel_search.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Representative probes: short (fallback full-scan, <3 chars), threshold
/// (exactly 3 chars, the trigram floor), a common word, and a longer phrase.
const _queries = <String>['في', 'قال', 'محمد', 'قلب', 'يا ليل الصب'];

const int _candidateLimit = 8000;

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
        'Usage: dart run tool/benchmark_search.dart <path-to-db> [--mmap=BYTES] [--cache=KB]');
    exitCode = 1;
    return;
  }
  final dbPath = File(positional.first).absolute.path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Database not found: $dbPath');
    exitCode = 1;
    return;
  }

  int flagInt(String name, int fallback) {
    final flag = args.firstWhere((a) => a.startsWith('--$name='),
        orElse: () => '');
    return flag.isEmpty ? fallback : int.parse(flag.split('=')[1]);
  }

  final mmap = flagInt('mmap', 4294967296); // matches current _tuneForReads
  final cacheKb = flagInt('cache', -262144);

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true),
  );
  await db.execute('PRAGMA mmap_size=$mmap;');
  await db.execute('PRAGMA cache_size=$cacheKb;');
  await db.execute('PRAGMA temp_store=MEMORY;');
  await db.execute('PRAGMA query_only=ON;');

  print('DB: $dbPath');
  print('mmap_size=$mmap  cache_size=$cacheKb\n');
  print(
      '${"query".padRight(16)}${"probe".padRight(10)}${"index?".padRight(8)}'
      '${"cold ms".padRight(10)}${"warm ms".padRight(10)}rows');

  for (final query in _queries) {
    final probe = coarseProbe(query);
    var rows = 0;
    var cold = 0;
    var warm = 0;
    for (var pass = 0; pass < 2; pass++) {
      final sw = Stopwatch()..start();
      rows = 0;
      for (final source in Source.values) {
        rows += await _runCoarseQuery(db, probe, source);
      }
      sw.stop();
      if (pass == 0) {
        cold = sw.elapsedMilliseconds;
      } else {
        warm = sw.elapsedMilliseconds;
      }
    }
    print('${query.padRight(16)}${probe.probe.padRight(10)}'
        '${probe.canUseIndex.toString().padRight(8)}'
        '${cold.toString().padRight(10)}${warm.toString().padRight(10)}$rows');
  }

  await db.close();
}

Future<int> _runCoarseQuery(
    Database db, CoarseProbe probe, Source source) async {
  final where = <String>[];
  final args = <Object?>[];
  final String from;

  if (probe.canUseIndex) {
    from = 'lines_fts f '
        'JOIN lines l ON l.id = f.rowid '
        'JOIN poem p ON p.id = l.poem_id';
    // No ESCAPE clause — mirrors the fix in poem_repository.dart (ESCAPE
    // silently defeats the trigram index; see _coarseCandidates there).
    where.add('f.plain LIKE ?');
    args.add('%${probe.probe}%');
  } else {
    from = 'lines l JOIN poem p ON p.id = l.poem_id';
    if (probe.probe.isNotEmpty) {
      where.add("l.plain LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(probe.probe)}%');
    }
  }
  where.add('(p.source_name = ? OR EXISTS (SELECT 1 FROM poem_alias a '
      'WHERE a.poem_id = p.id AND a.source_name = ?))');
  args.add(source.displayName);
  args.add(source.displayName);

  final whereSql = 'WHERE ${where.join(' AND ')}';
  args.add(_candidateLimit);
  final rows = await db.rawQuery(
    'SELECT l.id FROM $from $whereSql LIMIT ?',
    args,
  );
  return rows.length;
}

String _escapeLike(String s) =>
    s.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
