import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/db/poem_repository.dart';
import 'package:poem_searcher/models/source.dart';
import 'package:poem_searcher/search/search_sort.dart';

LineResult _line({
  required int lineCount,
  required Source source,
  String original = 'xxxxxxxxxx', // length 10
  int start = 0,
  int end = 1,
  int id = 0,
}) =>
    LineResult(
      original: original,
      start: start,
      end: end,
      spans: [(start: start, end: end)],
      poemId: id,
      lineId: id,
      title: 't',
      poet: 'p',
      lineCount: lineCount,
      source: source,
    );

TitleResult _title({
  required int lineCount,
  required Source source,
  String title = 'xxxxxxxxxx',
  int start = 0,
  int end = 1,
  int id = 0,
}) =>
    TitleResult(
      poemId: id,
      title: title,
      start: start,
      end: end,
      spans: [(start: start, end: end)],
      poet: 'p',
      lineCount: lineCount,
      source: source,
    );

void main() {
  const order = [Source.uqu, Source.dct];

  group('sortLineResults', () {
    test('relevance mode returns the input unchanged', () {
      final input = [
        _line(lineCount: 1, source: Source.uqu),
        _line(lineCount: 9, source: Source.uqu),
      ];
      expect(
        identical(sortLineResults(input, SearchSort.relevance, order), input),
        isTrue,
      );
    });

    test('lineCountDesc orders longest-first within each source group', () {
      final input = [
        _line(lineCount: 2, source: Source.uqu, id: 1),
        _line(lineCount: 8, source: Source.uqu, id: 2),
        _line(lineCount: 3, source: Source.dct, id: 3),
        _line(lineCount: 7, source: Source.dct, id: 4),
      ];
      final out = sortLineResults(input, SearchSort.lineCountDesc, order);
      // uqu group first (longest first), then dct group (longest first).
      expect(out.map((r) => r.poemId).toList(), [2, 1, 4, 3]);
      expect(out.map((r) => r.source).toList(),
          [Source.uqu, Source.uqu, Source.dct, Source.dct]);
    });

    test('equal lineCount falls back to matchTightness (tighter first)', () {
      final input = [
        // Same source + line count; looser match (span 1/10) then tighter (8/10).
        _line(lineCount: 5, source: Source.uqu, start: 0, end: 1, id: 1),
        _line(lineCount: 5, source: Source.uqu, start: 0, end: 8, id: 2),
      ];
      final out = sortLineResults(input, SearchSort.lineCountDesc, order);
      expect(out.map((r) => r.poemId).toList(), [2, 1]);
    });
  });

  group('sortTitleResults', () {
    test('relevance mode returns the input unchanged', () {
      final input = [_title(lineCount: 1, source: Source.uqu)];
      expect(
        identical(sortTitleResults(input, SearchSort.relevance, order), input),
        isTrue,
      );
    });

    test('lineCountDesc orders longest-first within each source group', () {
      final input = [
        _title(lineCount: 4, source: Source.dct, id: 1),
        _title(lineCount: 6, source: Source.uqu, id: 2),
        _title(lineCount: 9, source: Source.dct, id: 3),
        _title(lineCount: 5, source: Source.uqu, id: 4),
      ];
      final out = sortTitleResults(input, SearchSort.lineCountDesc, order);
      expect(out.map((r) => r.poemId).toList(), [2, 4, 3, 1]);
    });
  });
}
