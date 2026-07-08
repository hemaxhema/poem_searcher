import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/search/boolean_query.dart';
import 'package:poem_searcher/search/tashkeel_search.dart';

/// Helper: does the boolean [query] (as a parsed expression) match [text]?
/// Fails the test if the query does not parse.
bool matches(String query, String text) {
  final result = parseBoolean(query);
  expect(result.isValid, isTrue, reason: 'expected "$query" to parse: ${result.errorAr}');
  return result.expr!.match(text) != null;
}

void main() {
  group('AND (+)', () {
    test('both terms present (any order) matches', () {
      expect(matches('محمد + رسول', 'محمد هو رسول الله'), isTrue);
      expect(matches('محمد + رسول', 'رسول اسمه محمد'), isTrue);
    });
    test('one term missing does not match', () {
      expect(matches('محمد + رسول', 'محمد بن عبدالله'), isFalse);
      expect(matches('محمد + رسول', 'جاء الرسول'), isFalse);
    });
  });

  group('OR (| primary; , and ، accepted synonyms)', () {
    test('any term present matches', () {
      expect(matches('حب | هوى', 'في قلبي حب'), isTrue);
      expect(matches('حب | هوى', 'ذاك هوى قديم'), isTrue);
    });
    test('no term present does not match', () {
      expect(matches('حب | هوى', 'كلام آخر'), isFalse);
    });
    test('comma and Arabic comma are also accepted as OR', () {
      expect(matches('حب , هوى', 'ذاك هوى'), isTrue);
      expect(matches('حب ، هوى', 'ذاك هوى'), isTrue);
    });
  });

  group('NOT (-)', () {
    test('excluded term present hides the line', () {
      expect(matches('حب - فراق', 'حب فراق دائم'), isFalse);
    });
    test('excluded term absent keeps the line', () {
      expect(matches('حب - فراق', 'حب ووصال'), isTrue);
    });
  });

  group('Grouping and group negation', () {
    // A - (B + C): has A, but NOT (B and C together).
    const q = 'أحمد - (سعيد + خالد)';
    test('"A B D" shows (only one of the group present)', () {
      expect(matches(q, 'أحمد و سعيد و بكر'), isTrue);
    });
    test('"A B C" hidden (whole group present)', () {
      expect(matches(q, 'أحمد و سعيد و خالد'), isFalse);
    });
    test('A absent hides regardless', () {
      expect(matches(q, 'سعيد وحده'), isFalse);
    });
  });

  group('Precedence: OR lowest, AND next', () {
    // "A , B + C" == "A OR (B AND C)".
    const q = 'نور , شمس + قمر';
    test('A alone matches', () => expect(matches(q, 'نور ساطع'), isTrue));
    test('B and C together matches',
        () => expect(matches(q, 'شمس و قمر'), isTrue));
    test('B alone does not match',
        () => expect(matches(q, 'شمس فقط'), isFalse));
  });

  group('Per-term features are preserved', () {
    test('wildcard * inside an AND term', () {
      expect(matches('كتا* + قلم', 'كتاب و قلم'), isTrue);
      expect(matches('كتا* + قلم', 'كتاب فقط'), isFalse);
    });
    test('phrase (spaces) inside a term stays a phrase', () {
      expect(matches('يا ليل + طويل', 'يا ليل كم أنت طويل'), isTrue);
      // Words present but not as the adjacent phrase "يا ليل".
      expect(matches('يا ليل + طويل', 'ليل يا طويل'), isFalse);
    });
    test('tashkeel on a boolean term is honored', () {
      expect(matches('حَمد + خير', 'حَمد و خير'), isTrue);
      expect(matches('حَمد + خير', 'حُمد و خير'), isFalse);
    });
  });

  group('Backward compatibility (no operators)', () {
    test('a plain query is a single term', () {
      final r = parseBoolean('محمد');
      expect(r.expr, isA<TermLeaf>());
      expect(matches('محمد', 'جاء محمد'), isTrue);
    });
  });

  group('Parse errors (Arabic)', () {
    test('empty input', () {
      expect(parseBoolean('   ').errorAr, isNotNull);
    });
    test('unbalanced open paren', () {
      expect(parseBoolean('(محمد + رسول').errorAr, isNotNull);
    });
    test('extra close paren', () {
      expect(parseBoolean('محمد)').errorAr, isNotNull);
    });
    test('dangling operator', () {
      expect(parseBoolean('محمد +').errorAr, isNotNull);
    });
    test('NOT-only expression has no positive term', () {
      final r = parseBoolean('- فراق');
      expect(r.isValid, isFalse);
      expect(r.errorAr, isNotNull);
    });
  });

  group('describeArabic', () {
    test('AND', () {
      // The conjunction و attaches to the following word, per Arabic writing.
      expect(parseBoolean('محمد + رسول').expr!.describeArabic(),
          'محمد ورسول');
    });
    test('OR', () {
      expect(parseBoolean('حب , هوى').expr!.describeArabic(), 'حب أو هوى');
    });
    test('NOT', () {
      expect(parseBoolean('حب - فراق').expr!.describeArabic(),
          'حب وبدون فراق');
    });
    test('grouped negation wraps in parens', () {
      expect(parseBoolean('أحمد - (سعيد + خالد)').expr!.describeArabic(),
          'أحمد وبدون (سعيد وخالد)');
    });
    test('bracket group is glossed, empty slot reads «لا شيء»', () {
      final d = parseBoolean('مسلم[ين,ون,]').expr!.describeArabic();
      expect(d, contains('لا شيء'));
      expect(d, 'مسلم(ين أو ون أو لا شيء)');
    });
    test('bracket exclusion reads «عدا»', () {
      expect(parseBoolean('[ين,ون,!يَن]').expr!.describeArabic(),
          '(ين أو ون عدا يَن)');
    });
  });

  group('Highlight span', () {
    test('every positive term contributes its own span, in parts order', () {
      final expr = parseBoolean('رسول + محمد').expr!;
      const text = 'محمد هو رسول الله';
      final spans = expr.match(text);
      expect(spans, isNotNull);
      expect(spans, hasLength(2));
      expect(text.substring(spans![0].start, spans[0].end), 'رسول');
      expect(text.substring(spans[1].start, spans[1].end), 'محمد');
    });
  });

  group('Character class [...]', () {
    test('[و,ي] matches either letter, rejects a third', () {
      expect(matches('[و,ي]', 'و'), isTrue);
      expect(matches('[و,ي]', 'ي'), isTrue);
      expect(matches('[و,ي]', 'ب'), isFalse);
    });
    test('[!و] matches a letter that is not و', () {
      expect(matches('[!و]', 'ب'), isTrue);
      expect(matches('[!و]', 'و'), isFalse);
    });
    test('multi-letter alternatives as a word suffix', () {
      expect(matches('مسلم[ين,ون]', 'جاء المسلمون'), isFalse); // "ال" prefix: not a boundary
      expect(matches('مسلم[ين,ون]', 'مسلمون كثير'), isTrue);
      expect(matches('مسلم[ين,ون]', 'رأيت مسلمين'), isTrue);
      expect(matches('مسلم[ين,ون]', 'مسلمات هنا'), isFalse);
    });
    test('[ين,ون,!يَن] matches ين and ون but excludes the fatha form يَن', () {
      // The query's negated form and the excluded text both use ي + fatha + ن
      // (fatha = U+064E, written after the yaa it sits on).
      const q = 'حاضر[ين,ون,!يَن]';
      expect(matches(q, 'حاضرين'), isTrue); // bare ين — no fatha
      expect(matches(q, 'حاضرون'), isTrue);
      expect(matches(q, 'حاضريَن'), isFalse); // ...يَن with fatha
    });
    test('bracket integrates with boolean operators (its , is not OR)', () {
      expect(matches('مسلم[ين,ون] + الله', 'مسلمون عند الله'), isTrue);
      expect(matches('مسلم[ين,ون] + الله', 'مسلمون فقط'), isFalse);
    });
    test('empty slot makes the group optional (or nothing)', () {
      const q = 'مسلم[ين,ون,]';
      expect(matches(q, 'جاء مسلم'), isTrue); // bare word (empty branch)
      expect(matches(q, 'رأيت مسلمين'), isTrue);
      expect(matches(q, 'مسلمون كثير'), isTrue);
      expect(matches(q, 'مسلمات هنا'), isFalse); // ات is not an allowed ending
    });
    test('single optional suffix', () {
      expect(matches('كتاب[ين,]', 'هذا كتاب'), isTrue);
      expect(matches('كتاب[ين,]', 'رأيت كتابين'), isTrue);
    });
    test('empty slot combines with an exclusion', () {
      const q = 'حاضر[ين,ون,!يَن,]';
      expect(matches(q, 'هو حاضر'), isTrue);
      expect(matches(q, 'حاضرين'), isTrue);
      expect(matches(q, 'حاضرون'), isTrue);
      expect(matches(q, 'حاضريَن'), isFalse); // fatha form excluded
    });
  });

  group('Character class parse errors', () {
    test('unbalanced open bracket', () {
      expect(parseBoolean('مسلم[ين,ون').errorAr, isNotNull);
    });
    test('extra close bracket', () {
      expect(parseBoolean('مسلمين]').errorAr, isNotNull);
    });
    test('empty brackets', () {
      expect(parseBoolean('مسلم[]').errorAr, isNotNull);
    });
    test('only-negative with multi-letter exclusion is rejected', () {
      expect(parseBoolean('[!يَن]').errorAr, isNotNull);
    });
    test('an empty slot alongside a real option is valid', () {
      expect(parseBoolean('مسلم[ين,ون,]').isValid, isTrue);
    });
    test('only-empty brackets are still rejected', () {
      expect(parseBoolean('مسلم[,]').errorAr, isNotNull);
    });
  });

  group('Character class is boolean-only (inert in the main box)', () {
    test('buildRegexSource treats [ as a literal by default', () {
      final plain = buildRegexSource('[و,ي]');
      final withClass = buildRegexSource('[و,ي]', charClass: true);
      // Default: no alternation group is produced (bracket is literal).
      expect(plain, isNot(contains('(?:')));
      // charClass mode: an alternation group is produced.
      expect(withClass, contains('(?:'));
    });
  });

  group('Hard: deep nesting and precedence', () {
    test('triple-nested groups', () {
      // A + (B , (C - D)) == A AND (B OR (C AND NOT D))
      const q = 'أ + (ب , (ج - د))';
      expect(matches(q, 'أ و ب'), isTrue); // A + B via the OR's first branch
      expect(matches(q, 'أ و ج'), isTrue); // A + C (D absent)
      expect(matches(q, 'أ و ج و د'), isFalse); // C present but so is excluded D
      expect(matches(q, 'ب فقط'), isFalse); // A missing entirely
    });
    test('four-way AND chain', () {
      const q = 'أ + ب + ج + د';
      expect(matches(q, 'د ج ب أ'), isTrue); // any order
      expect(matches(q, 'أ ب ج'), isFalse); // د missing
    });
    test('five-way OR chain', () {
      const q = 'أ , ب , ج , د , هـ';
      for (final w in ['أ', 'ب', 'ج', 'د', 'هـ']) {
        expect(matches(q, 'كلام $w هنا'), isTrue, reason: w);
      }
      expect(matches(q, 'كلام آخر تمامًا'), isFalse);
    });
    test('sequential NOTs: A minus B minus C minus D', () {
      const q = 'أ - ب - ج - د';
      expect(matches(q, 'أ فقط'), isTrue);
      expect(matches(q, 'أ و ب'), isFalse);
      expect(matches(q, 'أ و ج'), isFalse);
      expect(matches(q, 'أ و د'), isFalse);
    });
    test('OR of two grouped ANDs, each with its own NOT', () {
      // (A - B) , (C - D)
      const q = '(أ - ب) , (ج - د)';
      expect(matches(q, 'أ وحده'), isTrue); // left branch: A without B
      expect(matches(q, 'ج وحده'), isTrue); // right branch: C without D
      expect(matches(q, 'أ و ب'), isFalse); // left branch fails (B present)
      expect(matches(q, 'ج و د'), isFalse); // right branch fails (D present)
      expect(matches(q, 'لا شيء مما سبق'), isFalse);
    });
    test('bracket + group + operators all combined', () {
      const q = 'مسلم[ين,ون] + (صادق , أمين) - كافر';
      expect(matches(q, 'مسلمون صادق'), isTrue);
      expect(matches(q, 'مسلمين أمين'), isTrue);
      expect(matches(q, 'مسلمون صادق كافر'), isFalse); // excluded term present
      expect(matches(q, 'صادق فقط'), isFalse); // bracket term missing
    });
    test('redundant nesting collapses to the same meaning', () {
      expect(matches('((((أ))))', 'جاء أ هنا'), isTrue);
      expect(matches('((((أ))))', 'لا شيء'), isFalse);
    });
  });

  group('Hard: whitespace and formatting robustness', () {
    test('operators with no surrounding spaces parse identically', () {
      expect(matches('أ+ب', 'أ و ب'), isTrue);
      expect(matches('أ+ب', 'أ فقط'), isFalse);
    });
    test('extra internal whitespace is tolerated', () {
      expect(matches('أ   +   ب', 'أ و ب'), isTrue);
      expect(matches('(  أ  +  ب  )', 'أ و ب'), isTrue);
    });
    test('leading/trailing whitespace around the whole query', () {
      expect(parseBoolean('  أ + ب  ').isValid, isTrue);
      expect(matches('  أ + ب  ', 'أ و ب'), isTrue);
    });
  });

  group('Hard: character class edge cases', () {
    test('five-way alternation inside one bracket', () {
      const q = '[ا,ب,ت,ث,ج]';
      for (final ch in ['ا', 'ب', 'ت', 'ث', 'ج']) {
        expect(matches(q, ch), isTrue, reason: ch);
      }
      expect(matches(q, 'ح'), isFalse);
    });
    test('option order inside the bracket does not matter', () {
      expect(matches('[ون,ين]', 'ون'), isTrue);
      expect(matches('[ون,ين]', 'ين'), isTrue);
    });
    test('a single-letter negative carrying a diacritic is still "one letter"', () {
      // The shadda on بّ doesn't count as a second base letter, so this is a
      // valid only-negative bracket (one excluded base letter).
      expect(parseBoolean('[!بّ]').isValid, isTrue);
    });
    test('a two-base-letter negative-only bracket is still rejected', () {
      expect(parseBoolean('[!اب]').errorAr, isNotNull);
    });
    test('two separate bracket groups in one term', () {
      // Two independent optional/alternate endings glued in sequence.
      const q = 'م[ح,خ]مد';
      expect(matches(q, 'محمد'), isTrue);
      expect(matches(q, 'مخمد'), isTrue);
      expect(matches(q, 'معمد'), isFalse);
    });
  });

  group('Hard: SQL predicate generation (toSql / mandatoryDriver)', () {
    String? sqlOf(String q, {String col = 'l.plain'}) {
      final expr = parseBoolean(q).expr!;
      final args = <Object?>[];
      return expr.toSql(col, args, (s) => s);
    }

    List<Object?> argsOf(String q, {String col = 'l.plain'}) {
      final expr = parseBoolean(q).expr!;
      final args = <Object?>[];
      expr.toSql(col, args, (s) => s);
      return args;
    }

    test('AND of two indexable terms ANDs their LIKE clauses', () {
      final sql = sqlOf('محمد + رسول');
      expect(sql, "(l.plain LIKE ? ESCAPE '\\' AND l.plain LIKE ? ESCAPE '\\')");
      expect(argsOf('محمد + رسول'), ['%محمد%', '%رسول%']);
    });
    test('OR of two indexable terms ORs their LIKE clauses', () {
      final sql = sqlOf('محمد , رسول');
      expect(sql, "(l.plain LIKE ? ESCAPE '\\' OR l.plain LIKE ? ESCAPE '\\')");
    });
    test('NOT parts are excluded from the SQL predicate entirely', () {
      // Only the positive part constrains SQL; NOT is Dart-only (see match()).
      expect(sqlOf('محمد - رسول'), "l.plain LIKE ? ESCAPE '\\'");
      expect(argsOf('محمد - رسول'), ['%محمد%']);
    });
    test('OR with one unconstrained branch cannot narrow at all', () {
      // "؟" alone has an empty probe (all-wildcard), so the OR can't be
      // expressed as a safe SQL superset and must return null.
      expect(sqlOf('محمد , ؟'), isNull);
    });
    test('OR bail-out leaves the args list untouched', () {
      final expr = parseBoolean('محمد , ؟').expr!;
      final args = <Object?>[];
      final sql = expr.toSql('l.plain', args, (s) => s);
      expect(sql, isNull);
      expect(args, isEmpty);
    });
    test('mandatoryDriver: AND picks the longest indexable positive probe', () {
      final expr = parseBoolean('حب + محبةعظيمة').expr!;
      expect(expr.mandatoryDriver(), 'محبةعظيمة');
    });
    test('mandatoryDriver: OR is never a mandatory driver', () {
      expect(parseBoolean('محمد , رسول').expr!.mandatoryDriver(), isNull);
    });
    test('mandatoryDriver: negated parts are excluded even if longer', () {
      // "طويلجداجدا" is the longer probe, but it's negated, so the positive
      // (shorter) "قصير" must be the one chosen as the mandatory driver.
      final expr = parseBoolean('قصير - طويلجداجدا').expr!;
      expect(expr.mandatoryDriver(), 'قصير');
    });
    test('a bracket term still yields a usable stem driver', () {
      final expr = parseBoolean('مسلم[ين,ون]').expr!;
      expect(expr.mandatoryDriver(), 'مسلم');
    });
    test('a whole term wrapped in one plain bracket option still narrows', () {
      // Regression: `[شمالات]` (e.g. from mis-using the char-class button on a
      // whole word) must not collapse to an empty/unnarrowed probe — that was
      // silently dropping the SQL LIKE/FTS filter entirely, falling back to an
      // unbounded table scan capped by `_candidateLimit`.
      final expr = parseBoolean('[شمالات]').expr!;
      expect(expr.mandatoryDriver(), 'شمالات');
      expect(sqlOf('[شمالات]'), "l.plain LIKE ? ESCAPE '\\'");
      expect(argsOf('[شمالات]'), ['%شمالات%']);
    });
    test('the escape function passed to toSql is actually applied', () {
      final expr = parseBoolean('محمد').expr!;
      final args = <Object?>[];
      expr.toSql('l.plain', args, (s) => s.toUpperCase());
      expect(args, ['%${'محمد'.toUpperCase()}%']);
    });
    test('positive-arg order matches textual order in a multi-term AND', () {
      // 'أ' folds to the canonical alif 'ا' in the normalized probe (rule 8).
      expect(argsOf('أ + ب + ج'), ['%ا%', '%ب%', '%ج%']);
    });
  });
}
