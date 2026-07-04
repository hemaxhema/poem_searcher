import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/search/arabic_normalizer.dart';
import 'package:poem_searcher/search/tashkeel_search.dart';

/// These tests protect the SQL-backed line search. That search finds candidate
/// lines with a coarse pre-filter (`plain LIKE '%probe%'`, where `plain` is
/// `stripAll(line)`) and then confirms each with the precise regex. For this to
/// be correct the coarse probe MUST be a *necessary condition*: every line the
/// regex accepts must also contain the probe, or the SQL filter would wrongly
/// drop a real match before the regex ever sees it.
void main() {
  group('coarseProbe basics', () {
    test('wildcard-free query → the whole normalized (folded) key', () {
      expect(coarseProbe('حمد').probe, 'حمد');
      // ي/ى and alif-hamza fold; quotes are deleted, not word-separated.
      expect(coarseProbe('رمى').probe, 'رمي');
      expect(coarseProbe('"آ"من').probe, 'امن');
    });

    test('wildcard query → the longest literal segment, normalized', () {
      expect(coarseProbe('زيد* الكتاب').probe, 'الكتاب');
      expect(coarseProbe('قا*وا').probe, 'قا'); // both halves len 2; first wins
      expect(coarseProbe('سلو*').probe, 'سلو');
    });

    test('all-wildcard query → empty probe (no usable filter)', () {
      expect(coarseProbe('؟؟').probe, isEmpty);
      expect(coarseProbe('*').probe, isEmpty);
    });

    test('canUseIndex reflects the 3-char trigram floor', () {
      expect(coarseProbe('حمد').canUseIndex, isTrue); // 3 chars
      expect(coarseProbe('من').canUseIndex, isFalse); // 2 chars
      expect(coarseProbe('قا*وا').canUseIndex, isFalse); // longest segment = 2
    });
  });

  // Every (query, text) pair that must MATCH under the rules. Mirrors the cases
  // in tashkeel_search_test.dart so the coarse filter is proven against the same
  // ground truth the precise search is.
  const matching = <(String, String)>[
    ('حمد', 'حمد'),
    ('حَمد', 'حَمَدَ'),
    ('شَر', 'شَـرُّ'),
    ('قالوا', 'قَالُوا: هَجَاكَ = قَدْ'),
    ('قالوا', 'قالوا:هجاكَ'),
    ('ح؟مد', 'حامد'),
    ('ح?مد', 'حُومِد'),
    ('زيد*', 'زيدلة'),
    ('زيد* الكتاب', 'زيدل الكتاب'),
    ('زيد *الكتاب', 'زيد والكتاب'),
    ('زيد _ الكتاب', 'زيد ذو الكتاب'),
    ('زيد* _ الكتاب', 'زيدلون ذوو صغير الكتاب'),
    ('رمي', 'رمى'),
    ('امن', 'أمن'),
    ('امن', 'آمن'),
    ('"آ"من', 'آمن'),
  ];

  group('coarse probe never excludes a true match (superset property)', () {
    for (final (query, text) in matching) {
      test('"$query" ⊆ "$text"', () {
        final probe = coarseProbe(query).probe;
        // The SQL row for [text] is kept iff its plain text contains the probe
        // (or the probe is empty, i.e. no filter). A true match must survive.
        final kept = probe.isEmpty || stripAll(text).contains(probe);
        expect(kept, isTrue,
            reason: 'probe "$probe" not found in "${stripAll(text)}"');
        // …and the precise regex, run on the survivor, confirms it.
        final regex = buildRegex(query)!;
        expect(confirmSpan(text, regex), isNotNull);
      });
    }
  });
}
