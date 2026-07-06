import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/search/boolean_query.dart';

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

  group('OR (, ، |)', () {
    test('any term present matches', () {
      expect(matches('حب , هوى', 'في قلبي حب'), isTrue);
      expect(matches('حب , هوى', 'ذاك هوى قديم'), isTrue);
    });
    test('no term present does not match', () {
      expect(matches('حب , هوى', 'كلام آخر'), isFalse);
    });
    test('Arabic comma and pipe are also OR separators', () {
      expect(matches('حب ، هوى', 'ذاك هوى'), isTrue);
      expect(matches('حب | هوى', 'ذاك هوى'), isTrue);
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
  });

  group('Highlight span', () {
    test('span comes from a positive matching term and maps into the text', () {
      final expr = parseBoolean('رسول + محمد').expr!;
      const text = 'محمد هو رسول الله';
      final span = expr.match(text);
      expect(span, isNotNull);
      // The first positive term "رسول" should be the highlighted span.
      expect(text.substring(span!.start, span.end), 'رسول');
    });
  });
}
