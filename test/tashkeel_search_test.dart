import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/search/tashkeel_search.dart';

/// Helper: does [query] match the single word [text] under the tashkeel rules?
bool matches(String query, String text) {
  final index = [
    SearchEntry(original: text, lineId: 1, poemId: 1, lineNumber: 1),
  ];
  return searchEntries(index, query).isNotEmpty;
}

void main() {
  group('Rule 1 — bare letters ignore tashkeel', () {
    // Query "حمد" (no diacritics) must match all vocalizations.
    const q = 'حمد';
    for (final t in <String>['حمِدَ', 'حَمَد', 'حُمد', 'حمد']) {
      test('"$q" matches "$t"', () => expect(matches(q, t), isTrue));
    }
  });

  group('Rule 2 — a typed diacritic is required exactly', () {
    // Query "حَمد": ha+fatha required, meem/dal bare.
    const q = 'حَمد';
    for (final t in <String>['حَمَدَ', 'حَمِد', 'حَمد']) {
      test('"$q" matches "$t"', () => expect(matches(q, t), isTrue));
    }
    for (final t in <String>['حُمد', 'حمد']) {
      test('"$q" does NOT match "$t"', () => expect(matches(q, t), isFalse));
    }
    test('shadda typed alone still matches shadda+fatha', () {
      expect(matches('عليّ', 'عليَّ'), isTrue);
    });
  });

  group('Rule 3 — punctuation, = and tatweel are ignored', () {
    test('tatweel between letters is skipped ("شَر" matches "شَـرُّ")', () {
      expect(matches('شَر', 'شَـرُّ'), isTrue);
    });
    test('= separator and punctuation ignored', () {
      expect(matches('قالوا', 'قَالُوا: هَجَاكَ = قَدْ'), isTrue);
    });
  });

  group('Highlight span maps back to the original text', () {
    test('span covers the matched word', () {
      final index = [
        SearchEntry(
          original: 'قالوا هَجتكَ سَلولُ',
          lineId: 1,
          poemId: 1,
          lineNumber: 1,
        ),
      ];
      final res = searchEntries(index, 'سلول');
      expect(res, hasLength(1));
      final m = res.first;
      expect(m.start, greaterThanOrEqualTo(0));
      // The highlighted slice should start with the queried base letters.
      final slice = m.entry.original.substring(m.start, m.end);
      expect(slice.startsWith('س'), isTrue);
    });
  });

  group('Empty / punctuation-only queries yield nothing', () {
    test('empty query', () => expect(matches('', 'حمد'), isFalse));
    test('punctuation-only query', () => expect(matches('=.,', 'حمد'), isFalse));
  });

  group('Rule 4 — word boundary anchoring', () {
    test('"حمد" does not match inside "وحمد"', () {
      expect(matches('حمد', 'وحمد'), isFalse);
    });
    test('"حمد" does not match inside "حمدل"', () {
      expect(matches('حمد', 'حمدل'), isFalse);
    });
    test('"حمد" matches standalone "حمد"', () {
      expect(matches('حمد', 'حمد'), isTrue);
    });
    test('punctuation with no surrounding space still ends a word', () {
      expect(matches('قالوا', 'قالوا:هجاكَ'), isTrue);
    });
  });

  group('Rule 5 — ?/؟ wildcard matches exactly one base letter', () {
    for (final q in ['ح؟مد', 'ح?مد']) {
      for (final t in <String>['حامد', 'حومد', 'حُومِد', 'حُوُمد']) {
        test('"$q" matches "$t"', () => expect(matches(q, t), isTrue));
      }
      for (final t in <String>['حمد', 'حَمد']) {
        test('"$q" does NOT match "$t"', () => expect(matches(q, t), isFalse));
      }
    }

    test('a lone ? or ؟ matches any single letter, bare or voweled', () {
      expect(matches('؟', 'ك'), isTrue);
      expect(matches('?', 'كَ'), isTrue);
    });

    test('two wildcards require exactly two letters', () {
      expect(matches('؟؟', 'حم'), isTrue);
      expect(matches('؟؟', 'ح'), isFalse);
    });
  });

  group('Rule 6 — * wildcard (zero or more letters within the same word)', () {
    test('zero-length match: "زيد*" also matches bare "زيد"', () {
      expect(matches('زيد*', 'زيد'), isTrue);
    });
    test('suffix: "زيد*" matches "زيدلة"', () {
      expect(matches('زيد*', 'زيدلة'), isTrue);
    });
    test('"زيد* الكتاب" matches "زيدل الكتاب" (suffix + separate word)', () {
      expect(matches('زيد* الكتاب', 'زيدل الكتاب'), isTrue);
    });
    test('"زيد* الكتاب" does NOT cross a space ("زيد والكتاب")', () {
      expect(matches('زيد* الكتاب', 'زيد والكتاب'), isFalse);
    });
    test('"زيد* الكتاب" does NOT match "زيد ذو الكتاب" (extra whole word)', () {
      expect(matches('زيد* الكتاب', 'زيد ذو الكتاب'), isFalse);
    });
    test('prefix: "زيد *الكتاب" matches "زيد والكتاب"', () {
      expect(matches('زيد *الكتاب', 'زيد والكتاب'), isTrue);
    });
    test('"زيد *الكتاب" does NOT match "زيدل الكتاب" (زيد not word-ended)', () {
      expect(matches('زيد *الكتاب', 'زيدل الكتاب'), isFalse);
    });
    test('"زيد *الكتاب" does NOT match "زيد ذو الكتاب" (extra whole word)', () {
      expect(matches('زيد *الكتاب', 'زيد ذو الكتاب'), isFalse);
    });
    test('a lone * matches nothing (treated like an empty query)', () {
      expect(matches('*', 'أي نص'), isFalse);
    });
  });

  group('Rule 7 — _ wildcard (zero or more whole additional words)', () {
    test('"زيد _ الكتاب" matches "زيد ذو الكتاب"', () {
      expect(matches('زيد _ الكتاب', 'زيد ذو الكتاب'), isTrue);
    });
    test('"زيد _ الكتاب" does NOT match "زيد والكتاب" (glued, not a word)', () {
      expect(matches('زيد _ الكتاب', 'زيد والكتاب'), isFalse);
    });
    test('"زيد* _ الكتاب" matches multiple bridged whole words', () {
      expect(matches('زيد* _ الكتاب', 'زيدلون ذوو صغير الكتاب'), isTrue);
    });
    test('"زيد* _ الكتاب" matches with zero intervening words', () {
      expect(matches('زيد* _ الكتاب', 'زيد الكتاب'), isTrue);
    });
    test('"زيد* _ الكتاب" does NOT match "زيد والكتاب" (glued, not a word)', () {
      expect(matches('زيد* _ الكتاب', 'زيد والكتاب'), isFalse);
    });
    test('"زيد* _ الكتاب" does NOT match "زيد جاء والكتاب" (trailing glue)', () {
      expect(matches('زيد* _ الكتاب', 'زيد جاء والكتاب'), isFalse);
    });
  });

  group('Rule 8 — ي/ى and alif-hamza letters fold by default', () {
    test('ي and ى are interchangeable', () {
      expect(matches('رمي', 'رمى'), isTrue);
      expect(matches('رمى', 'رمي'), isTrue);
    });

    for (final t in <String>['أمن', 'إمن', 'آمن', 'ؤمن', 'ئمن', 'ءمن']) {
      test('"امن" matches "$t"', () => expect(matches('امن', t), isTrue));
    }

    group('quoting a letter with "..." requires it exactly', () {
      test('"آ"من matches آمن', () => expect(matches('"آ"من', 'آمن'), isTrue));
      test('"آ"من does NOT match أمن', () {
        expect(matches('"آ"من', 'أمن'), isFalse);
      });
      test('"آ"من does NOT match امن', () {
        expect(matches('"آ"من', 'امن'), isFalse);
      });

      test('"ى" matches only ى, not ي', () {
        expect(matches('"ى"', 'ى'), isTrue);
        expect(matches('"ى"', 'ي'), isFalse);
      });
      test('"ي" matches only ي, not ى', () {
        expect(matches('"ي"', 'ي'), isTrue);
        expect(matches('"ي"', 'ى'), isFalse);
      });

      test('quoting a whole word disables folding for every letter in it', () {
        expect(matches('"امن"', 'أمن'), isFalse);
        expect(matches('"امن"', 'امن'), isTrue);
      });
    });
  });

  group('Hard combined-feature edge cases', () {
    test('؟ then * — one required unknown letter plus an open suffix', () {
      expect(matches('ح؟مد*', 'حامدون'), isTrue);
      expect(matches('ح؟مد*', 'حمدون'), isFalse); // missing the required ؟ letter
    });
    test('* then ؟ — open prefix plus one required trailing letter', () {
      // Exactly one letter after "مد", then the word must end there.
      expect(matches('*مد؟', 'أحمدي'), isTrue);
      expect(matches('*مد؟', 'محمد'), isFalse); // no letter after د
      expect(matches('*مد؟', 'محمدين'), isFalse); // two letters follow, not one
    });
    test('consecutive ** behaves like a single *', () {
      expect(matches('زيد**', 'زيدلون'), isTrue);
      expect(matches('زيد**', 'زيد'), isTrue);
    });
    test('three consecutive ؟؟؟ requires exactly three letters', () {
      expect(matches('؟؟؟', 'حمد'), isTrue);
      expect(matches('؟؟؟', 'حم'), isFalse);
      expect(matches('؟؟؟', 'حمدل'), isFalse);
    });
    test('a diacritic with no preceding base letter anywhere is ignored', () {
      // A stray fatha before any letter contributes nothing to the pattern.
      expect(matches('َحمد', 'حمد'), isTrue);
    });
    test('a query of only diacritics/tatweel matches nothing', () {
      expect(matches('َ', 'حمد'), isFalse);
      expect(matches('ـــ', 'حمد'), isFalse);
    });
    test('unterminated quote: the rest of the query is treated as exact', () {
      // Only one '"' — dequote toggles "exact" on and never back off.
      expect(matches('"ي', 'ي'), isTrue);
      expect(matches('"ي', 'ى'), isFalse);
    });
    test('two independent quoted spans in one query', () {
      // First "ا" is exact; the middle ي (in زيد) still folds; the final "ي"
      // is exact again.
      const q = '"ا"زيد"ي"';
      expect(matches(q, 'ازيدي'), isTrue);
      expect(matches(q, 'أزيدي'), isFalse); // leading exact ا rejects أ
      expect(matches(q, 'ازىدي'), isTrue); // middle letter still folds ي/ى
      expect(matches(q, 'ازيدى'), isFalse); // trailing exact ي rejects ى
    });
    test('lazy * still reaches the full word under the boundary anchor', () {
      final index = [
        SearchEntry(original: 'رأيت زيدلة قادمة', lineId: 1, poemId: 1, lineNumber: 1),
      ];
      final res = searchEntries(index, 'زيد*');
      expect(res, hasLength(1));
      final m = res.first;
      // Despite * being lazy, the trailing word-boundary requirement forces
      // the match to extend across the whole word "زيدلة", not stop early.
      expect(m.entry.original.substring(m.start, m.end), 'زيدلة');
    });
    test('* and _ combine: open prefix then a bridge of whole words', () {
      expect(matches('*مد _ الشعر', 'محمد في وصف الشعر'), isTrue);
      expect(matches('*مد _ الشعر', 'محمد الشعر'), isTrue); // zero bridged words
    });
    test('quoting disables folding but not the diacritic-optionality rule', () {
      // Quoting only touches ي/ى and alif-hamza folding (rule 8); a bare
      // quoted letter still matches with or without a diacritic (rule 1).
      expect(matches('"علي"', 'عليّ'), isTrue);
      expect(matches('"علي"', 'علي'), isTrue);
    });
  });

  group('CoarseProbe — hard edge cases', () {
    test('a wildcard-free query probes the whole normalized text', () {
      expect(coarseProbe('حمد').probe, 'حمد');
    });
    test('an all-wildcard query yields an empty, unusable probe', () {
      final p = coarseProbe('؟؟');
      expect(p.probe, isEmpty);
      expect(p.canUseIndex, isFalse);
    });
    test('the longest literal segment between wildcards is chosen', () {
      // "زيد" (3 letters) is longer than "ب" (1 letter).
      expect(coarseProbe('زيد*ب').probe, 'زيد');
    });
    test('canUseIndex boundary: 3 chars qualifies, 2 does not', () {
      expect(const CoarseProbe('اقل').canUseIndex, isTrue); // 3 chars
      expect(const CoarseProbe('اق').canUseIndex, isFalse); // 2 chars
    });
    test('quotes are stripped from the probe key (dequoted first)', () {
      expect(coarseProbe('"آ"من').probe, 'امن'); // folded + dequoted
    });
  });

  group('matchTightness — relevance score used to rank search results', () {
    test('a full-text match scores 1.0', () {
      expect(matchTightness(0, 5, 'ابجدة'), 1.0);
    });

    test('a match covering less of the text scores lower', () {
      final tight = matchTightness(0, 3, 'ابجدة'); // 3/5
      final loose = matchTightness(0, 3, 'ابجدةوهكذا'); // 3/10, same span
      expect(tight, greaterThan(loose));
    });

    test('a tighter match ranks above a looser one containing it', () {
      // Same query substring found in a short line vs. a much longer one:
      // the short/near-exact hit should score higher.
      final short = matchTightness(0, 4, 'قالوا');
      final long = matchTightness(10, 14, 'وقفت أطلال الديار وقالوا لنا');
      expect(short, greaterThan(long));
    });

    test('empty text scores 0 (no division by zero)', () {
      expect(matchTightness(0, 0, ''), 0);
    });
  });
}
