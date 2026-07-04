/// Arabic text normalization helpers for tashkeel-aware search.
///
/// These utilities are pure and framework-free so they can be unit-tested and
/// reused by both the global search and the poet-scoped search.
///
/// All Arabic/RTL characters are written with `\u` escapes so the exact code
/// points are unambiguous and never confuse the parser via bidi reordering.
library;

/// Inner body of the diacritic character class (no surrounding brackets):
///   U+064B..U+065F  tanwin, harakat, shadda, sukun, extended combining marks
///   U+0670          superscript alef
const String diacInner = 'ً-ٰٟ';

/// Character class matching a single diacritic. Used inside built regexes.
const String diacClass = '[$diacInner]';

/// Tatweel / kashida (U+0640) — a decorative letter-stretching character that
/// carries no meaning and must be ignored everywhere. Unlike other ignored
/// punctuation (see [_punctRe]), tatweel is deleted outright rather than
/// treated as a word separator, since it can appear stretching a single word
/// (e.g. "شَـرُّ") and must not split it into two words for boundary purposes.
const String tatweel = 'ـ';

/// Any single Arabic base letter (no diacritics): U+0621..U+063A (hamza..ghain)
/// and U+0641..U+064A (feh..yeh). Excludes U+0640 (tatweel, not a letter).
/// Used to expand the `?`/`؟` single-letter wildcard and the `*` run wildcard.
const String arabicLetterInner = 'ء-غف-ي';

/// Character class matching any single Arabic base letter.
const String arabicLetterClass = '[$arabicLetterInner]';

/// Letters treated as interchangeable for search purposes: "ي" (yeh) and
/// "ى" (alif maksura) are visually similar and routinely confused/miswritten
/// in Arabic text, so a query using either form matches text using the other.
/// A letter can be wrapped in `"..."` in a query to require an exact literal
/// match instead (see tashkeel_search.dart's rule 8).
const String yaEquivalents = 'يى';

/// Letters treated as interchangeable for search purposes: the bare hamza and
/// every alif/hamza-seat form are folded together, since orthographic
/// variation in hamza placement (or omission) is extremely common and not
/// meaningful for search. Same `"..."` exact-match override as [yaEquivalents].
const String alifHamzaEquivalents = 'اأإآؤئء';

/// Folds [text]'s ي/ى and alif/hamza-family letters to one canonical form per
/// group. Used by [stripAll] so its coarse pre-filter key agrees with the
/// regex's character-class-based equivalence groups (see [yaEquivalents],
/// [alifHamzaEquivalents]).
String _foldLetterVariants(String text) => text
    .replaceAll(RegExp('[$yaEquivalents]'), 'ي')
    .replaceAll(RegExp('[$alifHamzaEquivalents]'), 'ا');

final RegExp _diacRe = RegExp(diacClass);
final RegExp _diacOrTatweelRe = RegExp('[$diacInner$tatweel]');

/// Punctuation, Arabic punctuation, and the hemistich separator `=` (but NOT
/// tatweel, see [tatweel]). Ignored in both the query and the searched text —
/// but unlike tatweel, these are treated as word separators (collapsed into a
/// space) rather than deleted outright, so that e.g. a colon touching a word
/// with no surrounding whitespace still counts as ending that word.
///   ASCII: = . , ; : ! ? - ( ) [ ] "
///   U+060C Arabic comma, U+061B Arabic semicolon, U+061F Arabic question mark,
///   U+00AB « , U+00BB »
final RegExp _punctRe = RegExp('[=.,;:!?\\-()\\[\\]"،؛؟«»]');

final RegExp _whitespaceRe = RegExp(r'\s+');

/// True if [ch] (a single-character string) is an Arabic diacritic.
bool isDiacritic(String ch) => _diacRe.hasMatch(ch);

/// True if [ch] is a diacritic or tatweel — i.e. something that binds to the
/// preceding base letter and should be skipped when tokenizing a query.
bool isDiacriticOrTatweel(String ch) => _diacOrTatweelRe.hasMatch(ch);

/// Removes ignorable punctuation / `=` / tatweel but **keeps** diacritics and
/// collapses runs of whitespace to a single space. This is the string the
/// precise, diacritic-aware regex runs against.
String stripPunct(String text) => text
    .replaceAll(tatweel, '')
    .replaceAll(_punctRe, ' ')
    .replaceAll(_whitespaceRe, ' ')
    .trim();

/// Removes punctuation **and** all diacritics, leaving base letters and single
/// spaces, and folds ي/ى and alif/hamza-family letters to one canonical form
/// per group (see [yaEquivalents], [alifHamzaEquivalents]). Used for the fast
/// coarse pre-filter, where losing exact letter identity is safe.
String stripAll(String text) => _foldLetterVariants(text
    .replaceAll(tatweel, '')
    .replaceAll(_punctRe, ' ')
    .replaceAll(_diacRe, '')
    .replaceAll(_whitespaceRe, ' ')
    .trim());

/// Result of [stripPunctWithMap]: the punctuation-stripped text plus a map from
/// each kept character back to its index in the original string. This lets a
/// regex match found on the stripped text be projected back onto the original
/// (punctuated) text for highlighting.
class StrippedText {
  const StrippedText(this.text, this.map);

  /// Punctuation-stripped text (diacritics kept, whitespace collapsed).
  final String text;

  /// `map[i]` = index in the original string of the i-th char of [text].
  final List<int> map;
}

/// Like [stripPunct] but also records, for every kept character, its index in
/// the original [text]. Whitespace runs collapse to a single space whose map
/// entry points at the first whitespace character of the run.
StrippedText stripPunctWithMap(String text) {
  final buffer = StringBuffer();
  final map = <int>[];
  var lastWasSpace = true; // leading whitespace is trimmed, so start "spaced"
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == tatweel) {
      continue; // deleted outright: joins letters, creates no boundary.
    }
    if (_whitespaceRe.hasMatch(ch) || _punctRe.hasMatch(ch)) {
      if (!lastWasSpace) {
        buffer.write(' ');
        map.add(i);
        lastWasSpace = true;
      }
      continue;
    }
    buffer.write(ch);
    map.add(i);
    lastWasSpace = false;
  }
  // Trim a possible trailing collapsed space.
  var out = buffer.toString();
  if (out.endsWith(' ')) {
    out = out.substring(0, out.length - 1);
    map.removeLast();
  }
  return StrippedText(out, map);
}
