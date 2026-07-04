import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/util/kashida.dart';

/// Tatweel / kashida character (U+0640).
const String tatweel = 'ـ';

void main() {
  group('kashidaInsertionPoints', () {
    test('finds the joinable gaps in a fully-connecting word', () {
      // "بحر": ب→ح joinable, ح→ر joinable, ر is a dead-end (no left join).
      final points = kashidaInsertionPoints('بحر');
      // A tatweel may go before ح (index 1) and before ر (index 2).
      expect(points, [1, 2]);
    });

    test('no point follows a dead-end letter', () {
      // "ورد": و, ر and د are all dead-end (no left join), so a tatweel can
      // never follow any of them → no legal insertion points at all.
      expect(kashidaInsertionPoints('ورد'), isEmpty);
    });

    test('does not cross spaces or the "=" separator', () {
      final points = kashidaInsertionPoints('سلم = علم');
      // Every returned index must sit between two letters of the same word,
      // never adjacent to a space or the "=".
      for (final p in points) {
        expect(p > 0, isTrue);
        final before = 'سلم = علم'[p - 1];
        final at = 'سلم = علم'[p];
        expect(before == ' ' || before == '=', isFalse);
        expect(at == ' ' || at == '=', isFalse);
      }
    });

    test('empty and whitespace input yield no points', () {
      expect(kashidaInsertionPoints(''), isEmpty);
      expect(kashidaInsertionPoints('   '), isEmpty);
    });
  });

  group('insertKashida', () {
    test('inserts exactly the requested number of tatweels', () {
      const word = 'بحر';
      final points = kashidaInsertionPoints(word);
      final out = insertKashida(word, points, 4);
      final count = tatweel.allMatches(out).length;
      expect(count, 4);
    });

    test('spreads tatweels across the available points, not all in one gap', () {
      const word = 'بحر'; // two insertion points
      final points = kashidaInsertionPoints(word);
      final out = insertKashida(word, points, 2);
      // One tatweel per gap: "بـحـر".
      expect(out, 'بـحـر');
    });

    test('is a no-op for zero count or no points', () {
      expect(insertKashida('بحر', kashidaInsertionPoints('بحر'), 0), 'بحر');
      expect(insertKashida('ورد', const [], 5), 'ورد');
    });

    test('output still contains the original letters in order', () {
      const word = 'مدرسة';
      final points = kashidaInsertionPoints(word);
      final out = insertKashida(word, points, 3);
      final stripped = out.replaceAll(tatweel, '');
      expect(stripped, word);
    });
  });
}
