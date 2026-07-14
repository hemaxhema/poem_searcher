import 'package:flutter_test/flutter_test.dart';

import 'package:poem_searcher/search/search_sort.dart';

void main() {
  group('sortPoetsByCount', () {
    const counts = {'جرير': 5, 'الفرزدق': 9, 'الأخطل': 5};

    test('orders by poem count descending, then name ascending', () {
      final sorted = sortPoetsByCount(
        ['جرير', 'الفرزدق', 'الأخطل'],
        (poet) => counts[poet] ?? 0,
      );
      expect(sorted, ['الفرزدق', 'الأخطل', 'جرير']);
    });

    test('returns a new list, leaving the input untouched', () {
      final input = ['جرير', 'الفرزدق'];
      final sorted = sortPoetsByCount(input, (poet) => counts[poet] ?? 0);
      expect(input, ['جرير', 'الفرزدق']);
      expect(sorted, isNot(same(input)));
    });
  });
}
