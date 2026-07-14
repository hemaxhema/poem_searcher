import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poem_searcher/controllers/search_controller.dart';
import 'package:poem_searcher/db/poem_repository.dart';
import 'package:poem_searcher/db/poem_search_api.dart';
import 'package:poem_searcher/models/source.dart';
import 'package:poem_searcher/search/boolean_query.dart';
import 'package:poem_searcher/search/search_sort.dart';

LineResult line(int id, {int lineCount = 1, String text = 'بيت'}) => LineResult(
      original: text,
      start: 0,
      end: 1,
      spans: const [],
      poemId: id,
      lineId: id,
      title: 'عنوان',
      poet: 'شاعر',
      lineCount: lineCount,
      source: Source.uqu,
    );

/// Fake search API: every call records itself and returns a future the test
/// completes by hand, so slow/fast interleavings can be simulated.
class FakeSearchApi implements PoemSearchApi {
  final List<Completer<List<LineResult>>> lineCalls = [];
  final List<Completer<List<TitleResult>>> titleCalls = [];
  final List<String?> poets = [];

  @override
  Future<List<LineResult>> searchLines(
    String query, {
    String? poet,
    List<Source>? sourceOrder,
  }) {
    poets.add(poet);
    final completer = Completer<List<LineResult>>();
    lineCalls.add(completer);
    return completer.future;
  }

  @override
  Future<List<LineResult>> searchLinesBoolean(
    BoolExpr expr, {
    String? poet,
    List<Source>? sourceOrder,
  }) {
    final completer = Completer<List<LineResult>>();
    lineCalls.add(completer);
    return completer.future;
  }

  @override
  Future<List<TitleResult>> searchTitles(
    String query, {
    String? poet,
    List<Source>? sourceOrder,
  }) {
    final completer = Completer<List<TitleResult>>();
    titleCalls.add(completer);
    return completer.future;
  }

  @override
  Future<List<TitleResult>> searchTitlesBoolean(
    BoolExpr expr, {
    String? poet,
    List<Source>? sourceOrder,
  }) {
    final completer = Completer<List<TitleResult>>();
    titleCalls.add(completer);
    return completer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PoemSearchController — stale-result guard', () {
    test('a slow search resolving after a newer one is discarded', () async {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api);

      controller.onQueryChanged('شمس'); // search #1 (will resolve late)
      controller.onQueryChanged('شمس'); // search #2 (same text, newer token)
      expect(api.lineCalls, hasLength(2));

      api.lineCalls[1].complete([line(2)]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.sortedLines.single.poemId, 2);
      expect(controller.isSearching, isFalse);

      api.lineCalls[0].complete([line(1)]);
      await Future<void>.delayed(Duration.zero);
      // The stale #1 result must not overwrite #2's.
      expect(controller.sortedLines.single.poemId, 2);
    });

    test('results arriving after the box was emptied are discarded', () async {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api);

      controller.onQueryChanged('قمر');
      controller.onQueryChanged('');
      expect(controller.hasActiveSearch, isFalse);

      api.lineCalls.single.complete([line(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.sortedLines, isEmpty);
      expect(controller.isSearching, isFalse);
      expect(controller.page, 0);
    });
  });

  group('PoemSearchController — plain/boolean mode takeover', () {
    test('boolean search clears the plain query and vice versa', () async {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api);
      final expr = parseBoolean('شمس + قمر').expr!;

      controller.runBooleanSearch('شمس + قمر', expr);
      expect(controller.boolExpr, same(expr));
      expect(controller.boolRaw, 'شمس + قمر');
      expect(controller.boolDescription, isNotNull);
      expect(controller.query, isEmpty);

      controller.onQueryChanged('نجم');
      expect(controller.boolExpr, isNull);
      expect(controller.boolRaw, isEmpty);
      expect(controller.query, 'نجم');
    });

    test('clearBooleanSearch resets to the empty state', () async {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api);
      final expr = parseBoolean('شمس').expr!;

      controller.runBooleanSearch('شمس', expr);
      api.lineCalls.single.complete([line(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.sortedLines, isNotEmpty);

      controller.clearBooleanSearch();
      expect(controller.boolExpr, isNull);
      expect(controller.hasActiveSearch, isFalse);
      expect(controller.sortedLines, isEmpty);
      expect(controller.lineGroups, isEmpty);
    });
  });

  group('PoemSearchController — sorting and paging', () {
    test('setSortMode reorders in memory without a new API call', () async {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api);

      controller.onQueryChanged('شمس');
      api.lineCalls.single
          .complete([line(1, lineCount: 2), line(2, lineCount: 9)]);
      await Future<void>.delayed(Duration.zero);

      // Default lineCountDesc: longest poem first.
      expect(controller.sortedLines.map((l) => l.poemId), [2, 1]);
      final callsBefore = api.lineCalls.length;

      await controller.setSortMode(SearchSort.relevance);
      // Relevance keeps the repository (raw) order.
      expect(controller.sortedLines.map((l) => l.poemId), [1, 2]);
      expect(api.lineCalls.length, callsBefore);
    });

    test('a completed search resets the page to 0', () async {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api);

      controller.goToPage(3);
      expect(controller.page, 3);

      controller.onQueryChanged('شمس');
      api.lineCalls.single.complete([line(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.page, 0);
    });
  });

  group('PoemSearchController — scoping', () {
    test('a poet-scoped controller passes its poet to every search', () {
      final api = FakeSearchApi();
      final controller = PoemSearchController(
        api: api,
        poet: 'المتنبي',
        useTitlesPref: false,
      );

      controller.onQueryChanged('شمس');
      expect(api.poets.single, 'المتنبي');
      // useTitlesPref: false → titles are always searched.
      expect(api.titleCalls, hasLength(1));
    });

    test('home controller skips titles while the pref is off', () {
      final api = FakeSearchApi();
      final controller = PoemSearchController(api: api); // default pref: off

      controller.onQueryChanged('شمس');
      expect(api.titleCalls, isEmpty);
      expect(api.lineCalls, hasLength(1));
    });
  });
}
