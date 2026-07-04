@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/search/tashkeel_search.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integration test against the real bundled database file. It reproduces the
/// index-building the repository does (minus the asset copy, which is plain IO)
/// and asserts search behavior end-to-end on real data.
void main() {
  late Database db;
  late List<SearchEntry> lineIndex;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = File('test_database.db').absolute.path;
    db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final rows =
        await db.rawQuery('SELECT id, poem_id, line, line_number FROM lines');
    lineIndex = [
      for (final r in rows)
        SearchEntry(
          original: (r['line'] as String?) ?? '',
          lineId: r['id'] as int,
          poemId: r['poem_id'] as int,
          lineNumber: (r['line_number'] as int?) ?? 0,
        ),
    ];
  });

  tearDownAll(() => db.close());

  test('database has the expected shape', () async {
    final poemCount =
        (await db.rawQuery('SELECT COUNT(*) AS c FROM poem')).first['c'] as int;
    final lineCount =
        (await db.rawQuery('SELECT COUNT(*) AS c FROM lines')).first['c'] as int;
    expect(poemCount, 20);
    expect(lineCount, 205);
    expect(lineIndex, hasLength(205));
  });

  test('search counts match the validated prototype', () {
    expect(searchEntries(lineIndex, 'قالوا'), hasLength(2));
    // Was 3 before word-boundary anchoring (rule 4) was added: 2 of those 3
    // lines only contain "سلول" as a prefix of a longer word ("سلولي",
    // "سلولا"), which must no longer count as a match.
    expect(searchEntries(lineIndex, 'سلول'), hasLength(1));
    // Was 10 before rule 4: the other 9 lines only contain "شر" as a
    // substring of a longer word ("شراب", "مشرب", "تشرب", ...); only one
    // line has "شَرّ" ("evil") as a standalone word.
    expect(searchEntries(lineIndex, 'شَر'), hasLength(1));
  });

  test('wildcard queries against the real bundled DB', () {
    // "سل?ل"/"سل؟ل": exactly one letter between "سل" and "ل" — only "سَلولُ"
    // (the standalone-word occurrence found above) qualifies; "سَلُولِيٌّ" and
    // "سَلُـولاَ" don't since neither has exactly one letter in that gap.
    expect(searchEntries(lineIndex, 'سل?ل'), hasLength(1));
    expect(searchEntries(lineIndex, 'سل؟ل'), hasLength(1));
    // "سلو*": any suffix after "سلو" — matches all 3 words built on that root.
    expect(searchEntries(lineIndex, 'سلو*'), hasLength(3));
    // "*لول": leading wildcard finds "لول" as a word-ending suffix.
    expect(searchEntries(lineIndex, '*لول'), hasLength(1));
    // "قا*وا": wildcard spanning the interior of "قالوا"/"قَالُوا".
    expect(searchEntries(lineIndex, 'قا*وا'), hasLength(2));
  });

  test('bare query is a superset of the voweled query', () {
    final bare = searchEntries(lineIndex, 'سلول').length;
    final voweled = searchEntries(lineIndex, 'سَلول').length;
    expect(voweled, lessThanOrEqualTo(bare));
    expect(voweled, greaterThan(0));
  });

  test('every match resolves a highlight span in the original line', () {
    for (final m in searchEntries(lineIndex, 'قالوا')) {
      expect(m.start, greaterThanOrEqualTo(0));
      expect(m.end, greaterThan(m.start));
      expect(m.end, lessThanOrEqualTo(m.entry.original.length));
    }
  });
}
