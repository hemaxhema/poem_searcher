import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/db/poet_dedup.dart';

void main() {
  group('groupPoetVariants', () {
    test('tashkeel-only variants land in the same group', () {
      final variants = [
        const PoetVariant(name: 'أبو الفرج الموفقي', count: 4, sourcePriority: 0),
        const PoetVariant(name: 'أبو الفرج المُوفَّقي', count: 1, sourcePriority: 1),
      ];
      final groups = groupPoetVariants(variants);
      expect(groups, hasLength(1));
      expect(groups.values.single, hasLength(2));
    });

    test('genuinely different names stay in separate groups', () {
      final variants = [
        const PoetVariant(name: 'المتنبي', count: 4, sourcePriority: 0),
        const PoetVariant(name: 'البحتري', count: 1, sourcePriority: 0),
      ];
      final groups = groupPoetVariants(variants);
      expect(groups, hasLength(2));
    });
  });

  group('canonicalPoetName', () {
    test('lowest sourcePriority wins even over more vocalization/count', () {
      final group = [
        const PoetVariant(name: 'آخَرُ', count: 100, sourcePriority: 3),
        const PoetVariant(name: 'آخر', count: 1, sourcePriority: 0),
      ];
      expect(canonicalPoetName(group), 'آخر');
    });

    test('ties on priority break by richer vocalization', () {
      final group = [
        const PoetVariant(name: 'السهيلي', count: 12, sourcePriority: 1),
        const PoetVariant(name: 'السُهَيلي', count: 2, sourcePriority: 1),
      ];
      expect(canonicalPoetName(group), 'السُهَيلي');
    });

    test('ties on priority and vocalization break by higher usage count', () {
      final group = [
        const PoetVariant(name: 'آخر', count: 5, sourcePriority: 0),
        const PoetVariant(name: 'اخر', count: 27, sourcePriority: 0),
      ];
      expect(canonicalPoetName(group), 'اخر');
    });

    test('full tie breaks lexicographically', () {
      final group = [
        const PoetVariant(name: 'ب', count: 1, sourcePriority: 0),
        const PoetVariant(name: 'أ', count: 1, sourcePriority: 0),
      ];
      expect(canonicalPoetName(group), 'أ');
    });

    test('a single-variant group returns that name unchanged', () {
      final group = [
        const PoetVariant(name: 'المتنبي', count: 10, sourcePriority: 2),
      ];
      expect(canonicalPoetName(group), 'المتنبي');
    });

    test('same raw name under two sources merges counts and keeps lower priority', () {
      final group = [
        const PoetVariant(name: 'المتنبي', count: 3, sourcePriority: 2),
        const PoetVariant(name: 'المتنبي', count: 5, sourcePriority: 0),
        const PoetVariant(name: 'المتنّبي', count: 1, sourcePriority: 1),
      ];
      // Merged 'المتنبي' has sourcePriority 0 (best of 2 and 0), beating
      // 'المتنّبي' at priority 1 regardless of its extra diacritic.
      expect(canonicalPoetName(group), 'المتنبي');
    });

    test('variants differing only by trailing junk clean to the same name', () {
      final group = [
        const PoetVariant(name: 'ابن الدمَينة (الأموي)', count: 4, sourcePriority: 0),
        const PoetVariant(name: 'ابن الدمَينة:', count: 1, sourcePriority: 1),
      ];
      expect(canonicalPoetName(group), 'ابن الدمَينة');
    });
  });

  group('extractPoetName', () {
    test('strips a trailing whitelisted era tag', () {
      expect(extractPoetName('ابن الدمَينة (الأموي)'), 'ابن الدمَينة');
      expect(extractPoetName('مُزاحم بن عمرو (شاعر مجهول)'), 'مُزاحم بن عمرو');
    });

    test('strips a trailing whitelisted meter/date tag', () {
      expect(extractPoetName('اسم (من الطويل)'), 'اسم');
      expect(extractPoetName('اسم (580م)'), 'اسم');
    });

    test('keeps an earlier meaningful parenthetical, only strips the '
        'trailing whitelisted tag', () {
      expect(
        extractPoetName(
            'الأَشْتَر (الأَشْتَر بنُ حجوَان بنُ فقْعَس الأسْديّ) (الجاهلية)'),
        'الأَشْتَر (الأَشْتَر بنُ حجوَان بنُ فقْعَس الأسْديّ)',
      );
    });

    test('leaves a non-whitelisted trailing parenthetical untouched', () {
      const name = 'بَلْعَاء بن قَيْس (وهو الشَّدَّاخ الليثي)';
      expect(extractPoetName(name), name);
    });

    test('unwraps a name that is entirely one parenthesized clause, '
        'regardless of its content (never intentional)', () {
      expect(extractPoetName('(المجنون)'), 'المجنون');
      expect(extractPoetName('(وقال ابن هرمة)'), 'وقال ابن هرمة');
    });

    test('does not treat sibling parenthetical groups joined by plain text '
        'as one wrapping pair', () {
      const name = '(نص) وقال (نص آخر)';
      expect(extractPoetName(name), name);
    });

    test('stripping a trailing tag can reveal a now-fully-wrapped name, '
        'which then gets unwrapped too', () {
      // Stripping "(من الوافر)" first leaves "(يشكو الحمى بمصر)", which is
      // only now fully-wrapped — must not stop after one pass.
      expect(extractPoetName('(يشكو الحمى بمصر) (من الوافر)'),
          'يشكو الحمى بمصر');
    });

    test('strips dangling trailing punctuation with nothing meaningful '
        'after it', () {
      expect(extractPoetName('أبو الحسن الشيزري:'), 'أبو الحسن الشيزري');
      expect(extractPoetName('محمد بن مسرور الجياني، '), 'محمد بن مسرور الجياني');
    });

    test('leaves a mid-string colon with real content after it untouched '
        '(cutting there could discard the actual name)', () {
      const name = 'جمال الدين ابن المكرم: ابن منظور';
      expect(extractPoetName(name), name);
    });

    test('leaves a dash clause untouched even when it looks like a note '
        '(the real name can be on either side)', () {
      const name = 'آخر - وهو أبو العتاهية';
      expect(extractPoetName(name), name);
    });

    test('trims a leading stray punctuation character', () {
      expect(extractPoetName('.عُقْبَة بن كَعْب بن زُهَيْر المزني'),
          'عُقْبَة بن كَعْب بن زُهَيْر المزني');
    });

    test('leaves a long legitimate nasab/genealogy name untouched', () {
      const name = 'الأشعث بن يزيد الباهلي ثم الصحبي من بني صحب بن قتيبة بن معن';
      expect(extractPoetName(name), name);
    });

    test('leaves delimiter-free biographical prose untouched (out of scope)', () {
      const name = 'أبو الطمحان النهشلي كان يهاجي أم الورد العجلانية وفيها يقول';
      expect(extractPoetName(name), name);
    });

    test('strips a trailing whitelisted tag wrapped in quotes instead of '
        'parens', () {
      expect(extractPoetName('دريد بن الصِّمَّة "من الطويل"'),
          'دريد بن الصِّمَّة');
      expect(extractPoetName('قطرب "من البسيط"'), 'قطرب');
    });

    test('leaves a non-whitelisted trailing quoted clause untouched', () {
      const name = 'أبو الهندي "رجل من العرب"';
      expect(extractPoetName(name), name);
    });

    test('strips a dangling trailing quote with no matching opening quote '
        '(scrape artifact)', () {
      expect(extractPoetName('عبيد اللّه بن عكراش"'), 'عبيد اللّه بن عكراش');
      expect(extractPoetName('أقسام التنوين"'), 'أقسام التنوين');
    });

    test('unwraps a name that is entirely one quoted clause, regardless of '
        'its content', () {
      expect(extractPoetName('"وقال ابن هرمة"'), 'وقال ابن هرمة');
    });

    test('does not treat sibling quoted groups joined by plain text as one '
        'wrapping pair', () {
      const name = '"نص" وقال "نص آخر"';
      expect(extractPoetName(name), name);
    });

    test('collapses a raw value with no letter at all to unknownPoetName', () {
      expect(extractPoetName('()'), unknownPoetName);
      expect(extractPoetName('- 1 -'), unknownPoetName);
      expect(extractPoetName('149)'), unknownPoetName);
    });

    test('a Latin-script name is left untouched (it has real letters)', () {
      expect(extractPoetName('Ahlam Mohammad Qasim'), 'Ahlam Mohammad Qasim');
    });
  });

  group('groupPoetVariants with punctuation/trailing-junk differences', () {
    test('a name with vs. without a trailing colon groups together', () {
      final variants = [
        const PoetVariant(name: 'أبو الحسن الشيزري', count: 4, sourcePriority: 0),
        const PoetVariant(name: 'أبو الحسن الشيزري:', count: 1, sourcePriority: 1),
      ];
      final groups = groupPoetVariants(variants);
      expect(groups, hasLength(1));
    });

    test('a name with vs. without a trailing era tag groups together', () {
      final variants = [
        const PoetVariant(name: 'ابن الدمَينة (الأموي)', count: 4, sourcePriority: 0),
        const PoetVariant(name: 'ابن الدمَينة', count: 1, sourcePriority: 1),
      ];
      final groups = groupPoetVariants(variants);
      expect(groups, hasLength(1));
    });

    test('a name with vs. without a trailing quoted meter tag groups '
        'together', () {
      final variants = [
        const PoetVariant(name: 'قطرب', count: 4, sourcePriority: 0),
        const PoetVariant(name: 'قطرب "من البسيط"', count: 1, sourcePriority: 1),
      ];
      final groups = groupPoetVariants(variants);
      expect(groups, hasLength(1));
    });

    test('distinct letter-less junk spellings all collapse into one group', () {
      final variants = [
        const PoetVariant(name: '()', count: 417, sourcePriority: 0),
        const PoetVariant(name: '- 1 -', count: 46, sourcePriority: 0),
        const PoetVariant(name: '149)', count: 7, sourcePriority: 1),
      ];
      final groups = groupPoetVariants(variants);
      expect(groups, hasLength(1));
      expect(canonicalPoetName(groups.values.single), unknownPoetName);
    });
  });

  group('bestStoredPoetName', () {
    test('picks the existing stored spelling to keep (not the cleaned name), '
        'even when neither raw spelling matches the cleaned result', () {
      final group = [
        const PoetVariant(name: 'ابن الدمَينة (الأموي)', count: 1, sourcePriority: 1),
        const PoetVariant(name: 'ابن الدمَينة:', count: 4, sourcePriority: 0),
      ];
      // Priority 0 wins, so the surviving stored row is 'ابن الدمَينة:' even
      // though the canonical (cleaned) name is 'ابن الدمَينة'.
      expect(bestStoredPoetName(group), 'ابن الدمَينة:');
      expect(canonicalPoetName(group), 'ابن الدمَينة');
    });

    test('single-variant group returns that stored name unchanged', () {
      final group = [
        const PoetVariant(name: 'المتنبي', count: 10, sourcePriority: 2),
      ];
      expect(bestStoredPoetName(group), 'المتنبي');
    });
  });
}
