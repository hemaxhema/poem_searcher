/// Tashkeel-aware search: turns a query into a [RegExp] and runs a fast
/// two-stage match over an in-memory index.
///
/// Rules (see the plan / unit tests for worked examples):
///   1. A bare query letter matches that letter with any or no diacritic.
///   2. A query letter followed by a diacritic requires exactly that diacritic.
///   3. Punctuation, `=`, and tatweel are ignored in both query and text.
///   4. The match is anchored to word boundaries: the query's first letter
///      must start a word and its last letter must end a word.
///   5. `?` or `؟` matches exactly one (unknown) Arabic base letter, with
///      any/no diacritic on it.
///   6. `*` matches zero or more letters/diacritics *within the same word* —
///      it must sit directly against a word (no space) and extends it as a
///      suffix or prefix; it never crosses a space.
///   7. `_` matches zero or more whole additional words (each internally
///      letters/diacritics only, separated from each other by real
///      whitespace) — the whole-word counterpart to `*`, used where `*`
///      would need to cross a space.
///   8. By default, ي/ى are interchangeable and so are ا/أ/إ/آ/ؤ/ئ/ء (see
///      [yaEquivalents]/[alifHamzaEquivalents] in arabic_normalizer.dart).
///      Wrapping part of the query in `"..."` marks those letters as exact,
///      disabling the fold for just that span (for either group) and
///      requiring the literal written form. The quote marks themselves are
///      deleted outright (not treated as a word separator).
library;

import 'arabic_normalizer.dart';

/// One indexed unit of searchable text (a poem line, or a poet name).
///
/// [plain] is [stripAll] of [original] and is used for the coarse pre-filter;
/// [original] is kept so the precise regex can run on its punctuation-stripped
/// form and so matches can be highlighted in the real text.
class SearchEntry {
  SearchEntry({
    required this.original,
    required this.lineId,
    required this.poemId,
    required this.lineNumber,
  }) : plain = stripAll(original);

  /// Text exactly as stored in the database (with tashkeel and punctuation).
  final String original;

  /// `lines.id` for a verse entry, or a synthetic id for non-line entries.
  final int lineId;

  /// Owning `poem.id`.
  final int poemId;

  /// `lines.line_number` for a verse, or 0 for non-line entries.
  final int lineNumber;

  /// [original] with punctuation and diacritics removed (coarse-filter key).
  final String plain;
}

/// A confirmed match of a query against one [SearchEntry], with the matched
/// span expressed as `[start, end)` character offsets into [SearchEntry.original]
/// so it can be highlighted. Offsets are `-1` when no span could be resolved.
class LineMatch {
  const LineMatch(this.entry, this.start, this.end);

  final SearchEntry entry;
  final int start;
  final int end;
}

const String _regexSpecials = r'\^$.|?*+()[]{}';

/// Escapes a run of characters for safe literal use inside a regex, touching
/// only the characters the regex engine treats as special. Diacritics and
/// Arabic letters are passed through unchanged.
String _escape(String s) {
  final sb = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (_regexSpecials.contains(ch)) {
      sb.write('\\');
    }
    sb.write(ch);
  }
  return sb.toString();
}

/// Result of [_dequote]: [text] is [query] with every literal `"` removed
/// (deleted outright, like tatweel — no separator inserted), and `exact[i]`
/// is true when `text[i]` was written inside a quoted span and must match
/// its exact literal letter, bypassing the ي/ى and alif-hamza folds (rule 8).
class _DequotedQuery {
  const _DequotedQuery(this.text, this.exact);
  final String text;
  final List<bool> exact;
}

_DequotedQuery _dequote(String query) {
  final buffer = StringBuffer();
  final exact = <bool>[];
  var inQuotes = false;
  for (var i = 0; i < query.length; i++) {
    final ch = query[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    buffer.write(ch);
    exact.add(inQuotes);
  }
  return _DequotedQuery(buffer.toString(), exact);
}

/// Returns the regex character class for [ch]'s fold group (rule 8), or
/// `null` if [ch] has no fold group and should be matched literally.
String? _equivalenceClass(String ch) {
  if (yaEquivalents.contains(ch)) return '[$yaEquivalents]';
  if (alifHamzaEquivalents.contains(ch)) return '[$alifHamzaEquivalents]';
  return null;
}

/// Builds the regex source string for [query], or `null` if the query contains
/// no base letters (only punctuation/diacritics/whitespace).
String? buildRegexSource(String query) {
  final dequoted = _dequote(query);
  final text = dequoted.text;
  final exactAt = dequoted.exact;
  final sb = StringBuffer();
  var hasLetter = false;
  var i = 0;
  // True right after emitting a `_` wildcard. `_`'s own compiled pattern
  // already bakes in a mandatory trailing space when it matches 1+ words
  // (see below), and contributes nothing when it matches zero words — in
  // which case the mandatory space *before* `_` (left untouched) supplies
  // the one real separator needed. Emitting a second, independent mandatory
  // space right after `_` as well would demand two whitespace characters
  // where the text may only have one (e.g. "زيد الكتاب" with nothing
  // between), so that immediately-following query space is suppressed here.
  var suppressNextSpace = false;
  while (i < text.length) {
    final ch = text[i];
    if (_isWhitespace(ch)) {
      if (!suppressNextSpace) {
        sb.write(r'\s+');
      }
      suppressNextSpace = false;
      i++;
      continue;
    }
    if (isDiacriticOrTatweel(ch)) {
      // A stray diacritic with no preceding base letter — ignore it.
      i++;
      continue;
    }
    if (ch == '*') {
      // Rule 6: zero or more letters/diacritics, staying within the current
      // word (no `\s` alternative — `*` never crosses a space; `_` does
      // that job). Lazy (`*?`) so the match reports the smallest span that
      // still satisfies whatever follows (the trailing boundary lookahead,
      // or a subsequent mandatory space/literal).
      sb.write('(?:$arabicLetterClass|$diacClass)*?');
      i++;
      suppressNextSpace = false;
      continue;
    }
    if (ch == '_') {
      // Rule 7: zero or more *whole* additional words. When non-empty, bakes
      // in its own mandatory trailing space (see `suppressNextSpace` above).
      sb.write('(?:$_wordUnit(?:\\s+$_wordUnit)*\\s+)?');
      i++;
      suppressNextSpace = true;
      continue;
    }
    if (ch == '?' || ch == '؟') {
      // Rule 5: exactly one (unknown) base letter, any/no diacritic on it —
      // same "any diacritic" semantics as the bare-letter rule, for an
      // unknown letter instead of a fixed one.
      sb.write('$arabicLetterClass$diacClass*');
      hasLetter = true;
      i++;
      suppressNextSpace = false;
      continue;
    }
    // Base letter: gather the diacritics bound to it (skipping tatweel).
    final dia = StringBuffer();
    var j = i + 1;
    while (j < text.length && isDiacriticOrTatweel(text[j])) {
      if (text[j] != tatweel) {
        dia.write(text[j]);
      }
      j++;
    }
    // Rule 8: fold to the letter's equivalence class unless quoted-exact.
    final cls = exactAt[i] ? null : _equivalenceClass(ch);
    sb.write(cls ?? _escape(ch));
    if (dia.isEmpty) {
      sb.write('$diacClass*'); // rule 1: any/no diacritic
    } else {
      sb.write(_escape(dia.toString())); // rule 2: exactly these diacritics
    }
    hasLetter = true;
    i = j;
    suppressNextSpace = false;
  }
  if (!hasLetter) return null;
  // Rule 4: anchor to word boundaries. `_wordCharInner` is "not a space" in
  // stripped-text terms (this regex runs against `stripPunctWithMap`'s
  // output, where punctuation has already been collapsed to spaces and
  // tatweel deleted — see arabic_normalizer.dart), so a negative lookaround
  // against it is exactly "start/end of string, or adjacent to a space".
  return '(?<![$_wordCharInner])${sb.toString()}(?![$_wordCharInner])';
}

const String _wordCharInner = '$arabicLetterInner$diacInner';

/// One whole word's worth of letters (a maximal run of letter+diacritic
/// groups with no internal spaces) — the unit `_` repeats to bridge zero or
/// more whole words.
const String _wordUnit = '(?:$arabicLetterClass$diacClass*)+';

/// Compiles [query] into a [RegExp], or `null` if the query has no base letters.
RegExp? buildRegex(String query) {
  final source = buildRegexSource(query);
  return source == null ? null : RegExp(source);
}

/// True if [query] contains any wildcard marker (`*`, `?`, `؟`, `_`).
bool _queryHasWildcard(String query) =>
    query.contains('*') ||
    query.contains('?') ||
    query.contains('؟') ||
    query.contains('_');

/// The coarse pre-filter key derived from a query. A candidate line whose
/// [stripAll]-normalized text does not contain [probe] cannot match the precise
/// regex, so [probe] is used to narrow candidates (via an in-memory
/// `.contains` or an SQL `LIKE`/FTS lookup) before [confirmSpan] confirms them.
///
/// [probe] is empty only when the query is all wildcards with no literal
/// letters (e.g. `؟؟`), in which case no useful pre-filter exists.
class CoarseProbe {
  const CoarseProbe(this.probe);

  /// Normalized literal substring every candidate line must contain, or `''`.
  final String probe;

  /// True when [probe] is long enough (≥3 chars) to use an FTS5 trigram index;
  /// shorter probes require a fallback scan (or none, when empty).
  bool get canUseIndex => probe.length >= 3;
}

/// Derives the [CoarseProbe] for [query].
///
/// For a wildcard-free query the whole [stripAll]-normalized (dequoted) text is
/// the probe — the same key the old in-memory pre-filter used. `stripAll` folds
/// ي/ى and alif-hamza variants (rule 8), and the key is built from the dequoted
/// text so quote marks are deleted outright (e.g. `"آ"من` → key "امن", not
/// "ا من").
///
/// For a wildcard query no single contiguous key spans the whole match, so the
/// query is split on the wildcard markers (`*`, `?`, `؟`, `_`) and the longest
/// normalized literal segment becomes the probe (the regex confirms the rest).
CoarseProbe coarseProbe(String query) {
  final text = _dequote(query).text;
  if (!_queryHasWildcard(query)) {
    return CoarseProbe(stripAll(text));
  }
  var best = '';
  for (final segment in text.split(RegExp(r'[*?؟_]'))) {
    final normalized = stripAll(segment);
    if (normalized.length > best.length) best = normalized;
  }
  return CoarseProbe(best);
}

/// Precise, diacritic-aware confirmation of [regex] against a single line's
/// [original] text. Returns the highlight span `[start, end)` mapped back onto
/// [original], or `null` if the line does not match. Offsets are `-1` when no
/// span could be resolved (an empty match).
///
/// Word-boundary anchoring is baked into `regex` (see [buildRegexSource]), so
/// the first match found is already boundary-valid. Shared by the in-memory
/// [searchEntries] and the SQL-backed line search so the span logic lives once.
({int start, int end})? confirmSpan(String original, RegExp regex) {
  final stripped = stripPunctWithMap(original);
  final m = regex.firstMatch(stripped.text);
  if (m == null) return null;

  int start = -1, end = -1;
  if (m.end > m.start &&
      m.start < stripped.map.length &&
      m.end - 1 < stripped.map.length) {
    start = stripped.map[m.start];
    end = stripped.map[m.end - 1] + 1;
  }
  return (start: start, end: end);
}

/// [confirmSpan] wrapped to return a [LineMatch] for a full [SearchEntry].
LineMatch? confirmMatch(SearchEntry entry, RegExp regex) {
  final span = confirmSpan(entry.original, regex);
  return span == null ? null : LineMatch(entry, span.start, span.end);
}

/// Runs the two-stage tashkeel-aware search of [query] over [index] and returns
/// the matching entries with highlight spans, preserving [index] order. Used
/// for the in-memory poet-name index; the (far larger) line search runs the
/// same two stages with its coarse filter pushed into SQL (see
/// `PoemRepository.searchLines`).
List<LineMatch> searchEntries(List<SearchEntry> index, String query) {
  final regex = buildRegex(query);
  if (regex == null) return const [];

  // Stage 1: coarse substring pre-filter. Skipped for wildcard queries, whose
  // probe is not a contiguous substring of the whole match (`canUseIndex` is
  // irrelevant here — the in-memory `.contains` has no length floor).
  final hasWildcard = _queryHasWildcard(query);
  final base = hasWildcard ? null : coarseProbe(query).probe;
  if (base != null && base.isEmpty) return const [];

  final results = <LineMatch>[];
  for (final entry in index) {
    if (base != null && !entry.plain.contains(base)) continue;
    // Stage 2: precise, diacritic-aware confirmation.
    final m = confirmMatch(entry, regex);
    if (m != null) results.add(m);
  }
  return results;
}

bool _isWhitespace(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
