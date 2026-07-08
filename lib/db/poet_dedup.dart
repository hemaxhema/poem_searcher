/// Pure logic for merging poet-name spelling variants that differ in
/// tashkeel/tatweel/whitespace/punctuation, and for recovering the real name
/// from a handful of known trailing-junk shapes (see `tool/merge_poets.dart`).
/// Framework-free so the rename decision is unit-testable, mirroring
/// `poem_dedup.dart`.
library;

import 'poem_dedup.dart';
import '../search/arabic_normalizer.dart';

/// One (raw poet spelling, source, usage count) observation, aggregated from
/// `SELECT poet, source_id, COUNT(*) FROM poem GROUP BY poet, source_id`.
class PoetVariant {
  const PoetVariant({
    required this.name,
    required this.count,
    required this.sourcePriority,
  });

  final String name;
  final int count;

  /// Lower wins — the `source_id` (== `Source.values` index) of the
  /// highest-priority source that uses this spelling.
  final int sourcePriority;
}

/// Trailing parenthetical tags that are era/classification/meter/date notes,
/// never part of the name itself — verified against the shipped asset's
/// distinct trailing-paren contents (the top ~35 account for the vast
/// majority of the ~4,100 paren-suffixed poet names). Compared after
/// [stripAll]-normalizing both sides, so tashkeel/spacing/letter-variant
/// differences (e.g. "من الطَّويل" vs "من الطويل") still match.
final Set<String> _knownTrailingTagsNormalized = {
  // Era / classification.
  'الجاهلية', 'شاعر مجهول', 'الاموي', 'المخضرمون', 'صدر الاسلام', 'العباسي',
  'مخضرمو الدولتين',
  // Poetic meter.
  'من الطويل', 'من البسيط', 'من الكامل', 'من الوافر', 'من الخفيف',
  'من المتقارب', 'من السريع', 'من الرجز', 'من المنسرح', 'من الرمل',
  'من الهزج', 'من المديد', 'من مجزوء الكامل', 'من الكامل الاحذ',
  'طويل', 'كامل', 'بسيط', 'الطويل', 'البسيط',
}.map(stripAll).toSet();

/// A bare death-year note, e.g. "(580م)" — also never part of the name.
final RegExp _yearTagRe = RegExp(r'^\d{2,4}\s*م$');

/// A trailing parenthetical group with no nested parens, e.g. the
/// "(الجاهلية)" in "... الأسْديّ) (الجاهلية)" — greedy so an earlier,
/// meaningful parenthetical (like the alias in that same example) is left in
/// `before` untouched.
final RegExp _trailingParenRe = RegExp(r'^(.*)\(([^()]*)\)\s*$');

/// The quote-delimited counterpart of [_trailingParenRe] — the imported data
/// uses a trailing `"..."` clause for the same kind of era/meter/date tag
/// just as often as parens, e.g. the "من الطويل" in 'دريد بن الصِّمَّة "من
/// الطويل"'. Checked against the same [_knownTrailingTagsNormalized] /
/// [_yearTagRe] whitelist.
final RegExp _trailingQuoteRe = RegExp(r'^(.+)"([^"]*)"\s*$');

/// Punctuation characters that never carry meaning on their own — used to
/// build both the leading- and trailing-junk regexes below.
const String _danglingPunctInner = '.,;:\\-،؛';

/// A run of trailing punctuation/whitespace with no letters after it, e.g.
/// the dangling ":" in "أبو الحسن الشيزري:" or the dangling "،" in
/// "محمد بن مسرور الجياني، ". Safe to drop outright since nothing after it
/// is lost.
final RegExp _danglingTrailingPunctRe =
    RegExp('[$_danglingPunctInner\\s]+\$');

/// Leading punctuation/whitespace before the first real character, e.g. the
/// stray "." in ".عُقْبَة بن كَعْب ...". Safe to drop outright. Excludes `"`
/// deliberately — a leading double quote needs the parity check in
/// [_stripLoneLeadingQuote] instead, since it's just as often the opening
/// half of a legitimate `"..."` wrap as a stray artifact.
final RegExp _leadingJunkRe = RegExp('^[$_danglingPunctInner\\s\']+');

/// Placeholder for a `poet.name` that holds no actual name at all — pure
/// symbol/digit scrape noise like "()", "- 1 -" or "149)", with nothing
/// identifiable to recover. Chosen so these collapse into one shared row
/// via the normal [groupPoetVariants]/merge flow instead of surviving as
/// several distinct meaningless spellings.
const String unknownPoetName = 'مجهول';

/// Matches a Latin or Arabic base letter. A raw poet name containing none of
/// these can never be a real name — only digits/punctuation/whitespace.
final RegExp _anyLetterRe = RegExp('[A-Za-z$arabicLetterInner]');

/// True if [s] has no Latin or Arabic base letter anywhere — i.e. it's only
/// digits/punctuation/whitespace and can never be a real name.
bool _hasNoLetters(String s) => !_anyLetterRe.hasMatch(s);

/// True if [s] is entirely one balanced `(...)` wrapping — e.g. "(المجنون)"
/// — as opposed to sibling groups like "(X) (Y)" or trailing punctuation
/// like "(X)،", where the outer parens don't span the whole string.
bool _isFullyWrapped(String s) {
  if (!s.startsWith('(') || !s.endsWith(')')) return false;
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0 && i != s.length - 1) return false;
    }
  }
  return depth == 0;
}

/// The quote-delimited counterpart of [_isFullyWrapped] — a name that is
/// entirely one `"..."` wrapping, e.g. '"وقال ابن هرمة"'. Quotes don't
/// nest, so this only requires no *other* quote inside; that also correctly
/// rejects sibling groups like '"X" وقال "Y"', where a second pair follows
/// plain text instead of the wrapping spanning the whole string.
bool _isFullyQuoteWrapped(String s) =>
    s.length >= 2 &&
    s.startsWith('"') &&
    s.endsWith('"') &&
    !s.substring(1, s.length - 1).contains('"');

/// A trailing `"` with no matching opening quote anywhere else in the name —
/// a stray scrape artifact like the dangling `"` in 'هذه المرآة لهذا
/// الوجيه"'. Only stripped when [s] has an odd number of `"` overall, so a
/// genuine balanced `"..."` clause (handled by [_trailingQuoteRe] or
/// [_isFullyQuoteWrapped] instead) is never touched here.
final RegExp _trailingQuoteCharRe = RegExp('"\\s*\$');
String _stripLoneTrailingQuote(String s) {
  if (!_trailingQuoteCharRe.hasMatch(s)) return s;
  if ('"'.allMatches(s).length.isOdd) {
    return s.replaceFirst(_trailingQuoteCharRe, '');
  }
  return s;
}

/// A leading `"` with no matching closing quote anywhere else in the name —
/// the leading-side counterpart of [_stripLoneTrailingQuote]. Only stripped
/// when [s] has an odd number of `"` overall, so the opening quote of a
/// genuine balanced `"..."` wrap or sibling group is never touched here.
final RegExp _leadingQuoteCharRe = RegExp('^"\\s*');
String _stripLoneLeadingQuote(String s) {
  if (!_leadingQuoteCharRe.hasMatch(s)) return s;
  if ('"'.allMatches(s).length.isOdd) {
    return s.replaceFirst(_leadingQuoteCharRe, '');
  }
  return s;
}

/// Recovers the real poet name from a handful of known trailing/leading-junk
/// shapes found in the imported data:
///  - a raw value with no Latin/Arabic letter at all (e.g. "()", "- 1 -",
///    "149)") — pure scrape noise with no name to recover, collapsed to
///    [unknownPoetName] so every such row merges into one instead of
///    surviving as several distinct meaningless spellings,
///  - a leading stray punctuation character (scrape artifact),
///  - a dangling trailing punctuation run (nothing meaningful follows it),
///  - a dangling trailing quote with no matching opening quote anywhere else
///    in the name (see [_stripLoneTrailingQuote]) — a lone scrape artifact,
///    distinct from a genuine balanced `"..."` clause,
///  - the whole name wrapped in one pair of parens or one pair of quotes
///    (scrape artifact, e.g. "(المجنون)" or '"وقال ابن هرمة"') — unwrapped
///    regardless of content, since a name that is *only* a parenthesized/
///    quoted clause is never intentional,
///  - a trailing era/meter/date tag in parens *or* quotes (see
///    [_knownTrailingTagsNormalized] / [_yearTagRe]) — checked only for
///    content *after* some other text, so an inner meaningful parenthetical/
///    quoted clause is preserved.
///
/// Deliberately does **not** attempt to cut a trailing " - ..." or "، وهو
/// ..." clause: spot-checking the real data shows those sometimes hold a
/// generic placeholder *before* the delimiter ("آخر - وهو أبو العتاهية",
/// "الشاعر - عباس بن مرداس") with the actual identifying name *after* it —
/// a blind cut would discard the real name and keep the placeholder, which
/// is worse than leaving the row alone. Likewise does not attempt to
/// truncate freeform biographical prose with no punctuation boundary at all
/// (e.g. "... كان يهاجي ...") — no reliable, low-risk signal for that case.
///
/// The rules are applied repeatedly until none of them changes anything —
/// e.g. "(الاسم) (من الوافر)" first has its whitelisted trailing meter tag
/// stripped, leaving "(الاسم)", which only *then* becomes fully-wrapped and
/// gets unwrapped in the next pass. Each rule only ever shortens the string
/// (or leaves it unchanged), so this always terminates.
String extractPoetName(String raw) {
  if (_hasNoLetters(raw)) return unknownPoetName;
  var name = raw;
  while (true) {
    final before = name;

    name = name.replaceFirst(_leadingJunkRe, '');
    name = _stripLoneLeadingQuote(name);
    name = name.replaceFirst(_danglingTrailingPunctRe, '');
    name = _stripLoneTrailingQuote(name);

    if (_isFullyWrapped(name)) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (_isFullyQuoteWrapped(name)) {
      name = name.substring(1, name.length - 1).trim();
    }

    final parenMatch = _trailingParenRe.firstMatch(name);
    if (parenMatch != null) {
      final tag = parenMatch.group(2)!.trim();
      if (_knownTrailingTagsNormalized.contains(stripAll(tag)) ||
          _yearTagRe.hasMatch(tag)) {
        name =
            parenMatch.group(1)!.replaceFirst(_danglingTrailingPunctRe, '');
      }
    }

    final quoteMatch = _trailingQuoteRe.firstMatch(name);
    if (quoteMatch != null) {
      final tag = quoteMatch.group(2)!.trim();
      if (_knownTrailingTagsNormalized.contains(stripAll(tag)) ||
          _yearTagRe.hasMatch(tag)) {
        name =
            quoteMatch.group(1)!.replaceFirst(_danglingTrailingPunctRe, '');
      }
    }

    name = name.trim();
    if (name == before) break;
  }
  return name.length >= 2 ? name : raw;
}

/// Groups [variants] by their tashkeel/punctuation/trailing-junk-stripped
/// spelling: [extractPoetName] recovers the real name (while punctuation is
/// still intact, so it can see the structural delimiters), then [stripAll]
/// (from `arabic_normalizer.dart`) folds away diacritics, punctuation, and
/// letter-variant differences for the grouping key.
Map<String, List<PoetVariant>> groupPoetVariants(List<PoetVariant> variants) {
  final groups = <String, List<PoetVariant>>{};
  for (final v in variants) {
    final key = stripAll(extractPoetName(v.name));
    (groups[key] ??= []).add(v);
  }
  return groups;
}

/// Merges [group]'s variants by the key [keyOf] extracts from each raw name
/// (counts summed, best `sourcePriority` kept per key), then returns the
/// winning key: lowest `sourcePriority`, then richest vocalization, then
/// highest usage count, then lexicographically first.
String _bestKey(List<PoetVariant> group, String Function(String raw) keyOf) {
  final byKey = <String, PoetVariant>{};
  for (final v in group) {
    final key = keyOf(v.name);
    final existing = byKey[key];
    byKey[key] = existing == null
        ? PoetVariant(name: key, count: v.count, sourcePriority: v.sourcePriority)
        : PoetVariant(
            name: key,
            count: existing.count + v.count,
            sourcePriority: existing.sourcePriority < v.sourcePriority
                ? existing.sourcePriority
                : v.sourcePriority,
          );
  }
  final merged = byKey.values.toList()
    ..sort((a, b) {
      if (a.sourcePriority != b.sourcePriority) {
        return a.sourcePriority - b.sourcePriority;
      }
      final ta = tashkeelCount(cleanLine(a.name));
      final tb = tashkeelCount(cleanLine(b.name));
      if (ta != tb) return tb - ta;
      if (a.count != b.count) return b.count - a.count;
      return a.name.compareTo(b.name);
    });
  return merged.first.name;
}

/// Canonical spelling for one group: every variant's raw name is first
/// passed through [extractPoetName] to recover the real name, then the
/// canonical pick is the tie-break winner among those cleaned names (see
/// [_bestKey]).
String canonicalPoetName(List<PoetVariant> group) =>
    _bestKey(group, extractPoetName);

/// The existing *stored* spelling (no [extractPoetName] cleaning) that
/// should survive a merge/rename: the tie-break winner among the group's raw
/// names (see [_bestKey]). Only a spelling that's actually a `poet.name` row
/// can be the target of `UPDATE poem SET poet_id = ...`, which is why this is
/// computed separately from [canonicalPoetName] (whose cleaned result may not
/// match any stored row, e.g. after stripping a trailing tag).
String bestStoredPoetName(List<PoetVariant> group) =>
    _bestKey(group, (raw) => raw);
