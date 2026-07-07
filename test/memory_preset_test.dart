import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/db/memory_preset.dart';
import 'package:poem_searcher/services/memory_preset_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every preset has a distinct id, non-empty Arabic label, positive '
      'mmapSize, and negative cacheSizeKb', () {
    for (final preset in MemoryPreset.values) {
      expect(preset.id, isNotEmpty);
      expect(preset.label, isNotEmpty);
      expect(preset.mmapSize, greaterThan(0));
      expect(preset.cacheSizeKb, lessThan(0));
    }
    expect(
      MemoryPreset.values.map((p) => p.id).toSet(),
      hasLength(MemoryPreset.values.length),
    );
  });

  test('byId resolves each real id and falls back to high otherwise', () {
    expect(MemoryPreset.byId('low'), MemoryPreset.low);
    expect(MemoryPreset.byId('balanced'), MemoryPreset.balanced);
    expect(MemoryPreset.byId('high'), MemoryPreset.high);
    expect(MemoryPreset.byId(null), MemoryPreset.high);
    expect(MemoryPreset.byId('unknown'), MemoryPreset.high);
  });

  group('MemoryPresetPrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to high when nothing saved', () async {
      expect(await MemoryPresetPrefs.load(), MemoryPreset.high);
    });

    test('save then load round-trips every preset', () async {
      for (final preset in MemoryPreset.values) {
        await MemoryPresetPrefs.save(preset);
        expect(await MemoryPresetPrefs.load(), preset);
      }
    });
  });
}
