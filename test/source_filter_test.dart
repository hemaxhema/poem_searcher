import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/models/source.dart';
import 'package:poem_searcher/services/source_filter_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every source has an Arabic display name, unique across sources', () {
    for (final source in Source.values) {
      expect(source.displayName, isNotEmpty);
    }
    // Display names are the stored `poem.source_name` filter key, so they must
    // be distinct across all sources.
    expect(
      Source.values.map((s) => s.displayName).toSet(),
      hasLength(Source.values.length),
    );
  });

  test('the three web sources have distinct non-empty URL prefixes', () {
    final prefixed =
        Source.values.where((s) => s.urlPrefix != null).map((s) => s.urlPrefix!);
    for (final prefix in prefixed) {
      expect(prefix, isNotEmpty);
    }
    // Prefixes must be distinct or fromUrl would be ambiguous.
    expect(prefixed.toSet(), hasLength(3));
  });

  test('moktoum has no URL prefix (its poems carry no source_url)', () {
    expect(Source.moktoum.urlPrefix, isNull);
  });

  test('fromName maps a stored display name back to its Source', () {
    expect(Source.fromName('موسوعة آل مكتوم'), Source.moktoum);
    expect(Source.fromName('الديوان'), Source.aldiwan);
    expect(Source.fromName(null), isNull);
    expect(Source.fromName('unknown'), isNull);
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
