import 'package:flutter_test/flutter_test.dart';

import 'package:poem_searcher/models/poem_line.dart';

PoemLine line(int id, int lineNumber) =>
    PoemLine(id: id, poemId: 1, line: 'بيت $id', lineNumber: lineNumber);

void main() {
  group('groupByLineNumber', () {
    test('consecutive rows with the same line number form one group', () {
      final groups =
          groupByLineNumber([line(1, 1), line(2, 1), line(3, 2)]);
      expect(groups, hasLength(2));
      expect(groups[0].map((l) => l.id), [1, 2]);
      expect(groups[1].map((l) => l.id), [3]);
    });

    test('non-consecutive repeats of a line number are not merged', () {
      final groups =
          groupByLineNumber([line(1, 1), line(2, 2), line(3, 1)]);
      expect(groups, hasLength(3));
    });

    test('empty input yields no groups', () {
      expect(groupByLineNumber(const []), isEmpty);
    });
  });
}
