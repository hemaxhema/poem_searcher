import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/models/source.dart';
import 'package:poem_searcher/services/source_filter_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every source has a non-empty prefix and Arabic display name', () {
    for (final source in Source.values) {
      expect(source.urlPrefix, isNotEmpty);
      expect(source.displayName, isNotEmpty);
    }
    // Prefixes must be distinct or the per-source SQL filter would overlap.
    expect(Source.values.map((s) => s.urlPrefix).toSet(), hasLength(3));
  });

  group('SourceFilterPrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to all sources in declared order when nothing saved',
        () async {
      expect(await SourceFilterPrefs.load(), Source.values);
    });

    test('save then load round-trips a custom order/subset', () async {
      const order = [Source.aldiwan, Source.uqu];
      await SourceFilterPrefs.save(order);
      expect(await SourceFilterPrefs.load(), order);
    });

    test('falls back to all sources if the saved list is empty', () async {
      await SourceFilterPrefs.save(const []);
      expect(await SourceFilterPrefs.load(), Source.values);
    });
  });
}
