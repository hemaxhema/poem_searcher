import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/db/poem_repository.dart';
import 'package:poem_searcher/models/source.dart';
import 'package:poem_searcher/search/result_dedup.dart';

LineResult _line({
  required int id,
  required Source source,
  String original = 'xxxxxxxxxx',
  int lineCount = 8,
}) =>
    LineResult(
      original: original,
      start: 0,
      end: 1,
      poemId: id,
      lineId: id,
      title: 't',
      poet: 'p',
      lineCount: lineCount,
      source: source,
    );

TitleResult _title({
  required int id,
  required Source source,
  String title = 'xxxxxxxxxx',
  String poet = 'p',
  int lineCount = 8,
}) =>
    TitleResult(
      poemId: id,
      title: title,
      start: 0,
      end: 1,
      poet: poet,
      lineCount: lineCount,
      source: source,
    );

void main() {
  group('groupByKey', () {
    test('no duplicates: each item is its own group with no duplicates', () {
      final result = groupByKey([1, 2, 3], (v) => v);
      expect(result.map((g) => g.shown), [1, 2, 3]);
      expect(result.every((g) => g.duplicates.isEmpty), isTrue);
    });

    test('keeps the first occurrence of a key as shown, rest as duplicates',
        () {
      final result = groupByKey(['a1', 'b1', 'a2', 'a3', 'b2'], (s) => s[0]);
      expect(result.map((g) => g.shown), ['a1', 'b1']);
      expect(result[0].duplicates, ['a2', 'a3']);
      expect(result[1].duplicates, ['b2']);
    });
  });

  group('groupTitleResults', () {
    test(
        'same title + poem length under different poemIds/poets/sources '
        'collapse: first source in order wins, rest hidden', () {
      final input = [
        _title(id: 1, source: Source.uqu, poet: 'فضل جارية المتوكل'),
        _title(id: 2, source: Source.uqu, poet: 'فضل الشاعرة'),
      ];
      final result = groupTitleResults(input);
      expect(result, hasLength(1));
      expect(result.single.shown.poemId, 1);
      expect(result.single.shown.source, Source.uqu);
      expect(result.single.duplicates.single.poemId, 2);
    });

    test('same title collapses even when the poems differ in length', () {
      // Classical verses/titles are often reused across poems of different
      // length (imitation, quotation) — still treated as one duplicated
      // result rather than kept apart by poem length.
      final input = [
        _title(id: 1, source: Source.uqu, lineCount: 8),
        _title(id: 2, source: Source.dct, lineCount: 12),
      ];
      final result = groupTitleResults(input);
      expect(result, hasLength(1));
      expect(result.single.shown.poemId, 1);
    });

    test('tashkeel-only differences in title still collapse', () {
      final input = [
        _title(id: 1, source: Source.uqu, title: 'عِلْمُ الجَمالِ'),
        _title(id: 2, source: Source.dct, title: 'علم الجمال'),
      ];
      final result = groupTitleResults(input);
      expect(result, hasLength(1));
      expect(result.single.shown.poemId, 1);
    });
  });

  group('groupLineResults', () {
    test('same verse + poem length across sources collapses to one tile', () {
      final input = [
        _line(id: 1, source: Source.uqu),
        _line(id: 2, source: Source.dct),
        _line(id: 3, source: Source.aldiwan),
      ];
      final result = groupLineResults(input);
      expect(result, hasLength(1));
      expect(result.single.shown.lineId, 1);
      expect(result.single.duplicates.map((r) => r.lineId), [2, 3]);
    });

    test('same verse text collapses even when the owning poems differ in '
        'length', () {
      final input = [
        _line(id: 1, source: Source.uqu, lineCount: 8),
        _line(id: 2, source: Source.dct, lineCount: 20),
      ];
      final result = groupLineResults(input);
      expect(result, hasLength(1));
      expect(result.single.shown.lineId, 1);
    });
  });
}
