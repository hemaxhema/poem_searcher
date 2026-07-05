import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/ui/results_pagination.dart';

void main() {
  group('PageWindow.compute', () {
    test('fewer than one page: everything on a single page', () {
      final w = PageWindow.compute(
        titleCount: 5,
        lineCount: 20,
        page: 0,
        pageSize: 100,
      );
      expect(w.totalPages, 1);
      expect(w.page, 0);
      expect(w.titleStart, 0);
      expect(w.titleEnd, 5);
      expect(w.lineStart, 0);
      expect(w.lineEnd, 20);
      expect(w.titleCountOnPage, 5);
      expect(w.lineCountOnPage, 20);
    });

    test('no results still yields one (empty) page', () {
      final w = PageWindow.compute(
        titleCount: 0,
        lineCount: 0,
        page: 0,
        pageSize: 100,
      );
      expect(w.totalPages, 1);
      expect(w.titleCountOnPage, 0);
      expect(w.lineCountOnPage, 0);
    });

    test('exact page boundary: 200 tiles across two full pages', () {
      final first = PageWindow.compute(
        titleCount: 0,
        lineCount: 200,
        page: 0,
        pageSize: 100,
      );
      expect(first.totalPages, 2);
      expect(first.lineStart, 0);
      expect(first.lineEnd, 100);

      final second = PageWindow.compute(
        titleCount: 0,
        lineCount: 200,
        page: 1,
        pageSize: 100,
      );
      expect(second.lineStart, 100);
      expect(second.lineEnd, 200);
      expect(second.titleCountOnPage, 0);
    });

    test('page straddling the titles→lines split', () {
      // 40 titles + 500 lines. Page 0 = 40 titles + first 60 lines.
      final w = PageWindow.compute(
        titleCount: 40,
        lineCount: 500,
        page: 0,
        pageSize: 100,
      );
      expect(w.totalPages, 6); // ceil(540 / 100)
      expect(w.titleStart, 0);
      expect(w.titleEnd, 40);
      expect(w.lineStart, 0);
      expect(w.lineEnd, 60);
      expect(w.titleCountOnPage + w.lineCountOnPage, 100);
    });

    test('page after the split shows only lines', () {
      // 40 titles + 500 lines, page 1 = global [100, 200) = lines [60, 160).
      final w = PageWindow.compute(
        titleCount: 40,
        lineCount: 500,
        page: 1,
        pageSize: 100,
      );
      expect(w.titleCountOnPage, 0);
      expect(w.lineStart, 60);
      expect(w.lineEnd, 160);
    });

    test('last page is partial', () {
      // 40 titles + 500 lines = 540 tiles. Last page (5) = global [500, 540).
      final w = PageWindow.compute(
        titleCount: 40,
        lineCount: 500,
        page: 5,
        pageSize: 100,
      );
      expect(w.page, 5);
      expect(w.titleCountOnPage, 0);
      expect(w.lineStart, 460); // 500 - 40
      expect(w.lineEnd, 500); // 540 - 40
      expect(w.lineCountOnPage, 40);
    });

    test('requested page beyond the end is clamped to the last page', () {
      final w = PageWindow.compute(
        titleCount: 0,
        lineCount: 150,
        page: 99,
        pageSize: 100,
      );
      expect(w.totalPages, 2);
      expect(w.page, 1);
      expect(w.lineStart, 100);
      expect(w.lineEnd, 150);
    });

    test('negative page is clamped to zero', () {
      final w = PageWindow.compute(
        titleCount: 0,
        lineCount: 150,
        page: -3,
        pageSize: 100,
      );
      expect(w.page, 0);
      expect(w.lineStart, 0);
      expect(w.lineEnd, 100);
    });
  });
}
