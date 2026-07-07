import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/db/poem_dedup.dart';

void main() {
  group('cleanLine', () {
    test('removes tatweel and collapses whitespace', () {
      expect(cleanLine('شـــرّ'), 'شرّ');
      expect(cleanLine('  a   b  '), 'a b');
      expect(cleanLine('a\tb\nc'), 'a b c');
    });
  });

  group('strippedLine groups poems differing only in tashkeel', () {
    test('same base letters, different harakat → identical stripped key', () {
      const a = 'قَالُوا'; // vocalized
      const b = 'قالوا'; //   bare
      expect(strippedLine(cleanLine(a)), strippedLine(cleanLine(b)));
    });

    test('different letters → different stripped key', () {
      expect(strippedLine('قالوا') == strippedLine('قالو'), isFalse);
    });
  });

  group('poemSupersets (the delete decision)', () {
    test('rule 2: vocalized is a superset of the bare copy → bare deletable', () {
      final vocalized = [cleanLine('قَالُوا لَهُ')];
      final bare = [cleanLine('قالوا له')];
      expect(poemSupersets(vocalized, bare), isTrue); // delete `bare`
      expect(poemSupersets(bare, vocalized), isFalse); // never delete `vocalized`
    });

    test('rule 3: two identical bare copies are mutual supersets → keep one', () {
      final a = [cleanLine('قالوا له')];
      final b = [cleanLine('قالوا له')];
      expect(poemSupersets(a, b), isTrue);
      expect(poemSupersets(b, a), isTrue);
    });

    test('rule 1: a line with DIFFERENT harakat → neither is a superset', () {
      // Same base letters, but the last letter carries fatha vs kasra.
      final fatha = [cleanLine('مِنَ')];
      final kasra = [cleanLine('مِنِ')];
      expect(strippedLine(fatha.first), strippedLine(kasra.first)); // same group
      expect(poemSupersets(fatha, kasra), isFalse);
      expect(poemSupersets(kasra, fatha), isFalse); // both kept
    });

    test('partial vocalization each way → neither is a superset (both kept)', () {
      // Poem A vocalizes line 1, poem B vocalizes line 2; neither dominates.
      final a = [cleanLine('قَالُوا'), cleanLine('لهم')];
      final b = [cleanLine('قالوا'), cleanLine('لَهُم')];
      expect(poemSupersets(a, b), isFalse);
      expect(poemSupersets(b, a), isFalse);
    });

    test('different line counts are never supersets', () {
      expect(poemSupersets([cleanLine('a'), cleanLine('b')], [cleanLine('a')]),
          isFalse);
    });
  });

  group('tashkeelCount', () {
    test('counts diacritics, ignores base letters and tatweel', () {
      expect(tashkeelCount(cleanLine('قالوا')), 0);
      expect(tashkeelCount(cleanLine('قَالُوا')), greaterThan(0));
    });
  });
}
