import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/search/search_sort.dart';
import 'package:poem_searcher/services/search_sort_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SearchSort.byId', () {
    test('round-trips every mode id', () {
      for (final sort in SearchSort.values) {
        expect(SearchSort.byId(sort.id), sort);
      }
    });

    test('falls back to relevance for unknown or null id', () {
      expect(SearchSort.byId(null), SearchSort.relevance);
      expect(SearchSort.byId('nope'), SearchSort.relevance);
    });
  });

  group('SearchSortPrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to relevance when nothing saved', () async {
      expect(await SearchSortPrefs.load(), SearchSort.relevance);
    });

    test('save then load round-trips a mode', () async {
      await SearchSortPrefs.save(SearchSort.lineCountDesc);
      expect(await SearchSortPrefs.load(), SearchSort.lineCountDesc);
    });
  });
}
