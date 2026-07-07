/// Pure text helpers for tashkeel-aware poem deduplication (used by
/// `tool/dedup_poems.dart`). Framework-free so the merge decision — which is
/// destructive — is unit-testable.
///
/// Two poems are candidates to merge when their lines are identical after
/// stripping tashkeel ([strippedLine]); a poem is then removed only if another
/// is a [poemSupersets] of it (same text, more-or-equal harakat everywhere).
library;

/// Arabic combining marks treated as tashkeel: U+064B–U+065F and superscript
/// alef U+0670. Deliberately excludes U+0660+ (digits/punctuation).
bool isTashkeel(int cu) => (cu >= 0x064B && cu <= 0x065F) || cu == 0x0670;

/// Tatweel / kashida — decorative, carries no meaning; removed before compare.
const int _tatweel = 0x0640;

/// Removes tatweel and collapses whitespace runs to a single space (trimmed),
/// keeping letters, diacritics, hamza and punctuation. This is the canonical
/// form both the grouping key and the superset comparison operate on.
String cleanLine(String s) {
  final b = StringBuffer();
  var lastSpace = true; // trims leading whitespace
  for (final cu in s.codeUnits) {
    if (cu == _tatweel) continue;
    final isWs = cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;
    if (isWs) {
      if (!lastSpace) {
        b.writeCharCode(0x20);
        lastSpace = true;
      }
      continue;
    }
    b.writeCharCode(cu);
    lastSpace = false;
  }
  var out = b.toString();
  if (out.endsWith(' ')) out = out.substring(0, out.length - 1);
  return out;
}

/// A [cleanLine] with all tashkeel removed — the base-letter grouping key.
String strippedLine(String clean) {
  final b = StringBuffer();
  for (final cu in clean.codeUnits) {
    if (!isTashkeel(cu)) b.writeCharCode(cu);
  }
  return b.toString();
}

/// Number of tashkeel marks in a [cleanLine] (richer vocalization wins ties).
int tashkeelCount(String clean) {
  var n = 0;
  for (final cu in clean.codeUnits) {
    if (isTashkeel(cu)) n++;
  }
  return n;
}

/// True if cleaned poem [a] is a haraka-superset of cleaned poem [b]: same line
/// count, and at every base-letter position a's diacritics ⊇ b's (equal, or a
/// adds harakat where b is bare) with no disagreement. Deleting b then loses
/// nothing a doesn't already carry.
bool poemSupersets(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_lineSupersets(a[i], b[i])) return false;
  }
  return true;
}

bool _lineSupersets(String a, String b) {
  final ta = _tokenize(a);
  final tb = _tokenize(b);
  if (ta.length != tb.length) return false;
  for (var i = 0; i < ta.length; i++) {
    if (ta[i].base != tb[i].base) return false;
    for (final d in tb[i].dia) {
      if (!ta[i].dia.contains(d)) return false;
    }
  }
  return true;
}

/// One base character with the set of diacritics attached to it.
class _Tok {
  _Tok(this.base) : dia = <int>{};
  final int base;
  final Set<int> dia;
}

List<_Tok> _tokenize(String clean) {
  final toks = <_Tok>[];
  for (final cu in clean.codeUnits) {
    if (isTashkeel(cu)) {
      if (toks.isNotEmpty) toks.last.dia.add(cu); // ignore leading diacritics
    } else {
      toks.add(_Tok(cu));
    }
  }
  return toks;
}
