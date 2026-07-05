/// Kashida (tatweel, U+0640) justification for Arabic text.
///
/// Flutter has no native Kashida support — `TextAlign.justify` only distributes
/// whitespace and never touches a single/last line, so it does nothing for a
/// one-line verse. These helpers instead *insert* tatweel characters into the
/// gaps between joined letters until a line reaches a target rendered width, the
/// authentic way Arabic text is stretched to a uniform width.
///
/// The insertion-point logic is framework-free and unit-tested; only the width
/// measurement and the width-driven [kashidaJustify] touch `TextPainter`.
library;

import 'package:flutter/widgets.dart';

import '../search/arabic_normalizer.dart' show arabicLetterInner, diacInner, tatweel;

final RegExp _baseLetterRe = RegExp('[$arabicLetterInner]');
final RegExp _diacRe = RegExp('[$diacInner]');

/// Bare hamza (U+0621) — the only base letter that does not connect to the
/// letter on its right, so a tatweel can never precede it.
const String _hamza = 'ء';

/// Arabic letters that do **not** connect to the letter on their left (they have
/// no initial/medial form), so a tatweel can never follow them.
const Set<String> _noLeftJoin = <String>{
  'ء', // ء  hamza
  'آ', // آ  alef with madda
  'أ', // أ  alef with hamza above
  'ؤ', // ؤ  waw with hamza
  'إ', // إ  alef with hamza below
  'ا', // ا  alef
  'ة', // ة  teh marbuta
  'د', // د  dal
  'ذ', // ذ  thal
  'ر', // ر  reh
  'ز', // ز  zain
  'و', // و  waw
  'ى', // ى  alef maksura
};

bool _isBaseLetter(String ch) => _baseLetterRe.hasMatch(ch);
bool _isDiacritic(String ch) => _diacRe.hasMatch(ch);

/// Lam (ل).
const String _lam = 'ل';

/// Alef and alef-like letters. Immediately after a lam these form a mandatory
/// ligature (لا، لأ، لإ، لآ), so a tatweel must never be inserted between
/// them — unlike alef elsewhere, which can still take a preceding tatweel
/// normally (e.g. كتاب → كتـاب).
const Set<String> _noRightJoin = <String>{
  'ا', // ا  alef
  'أ', // أ  alef with hamza above
  'إ', // إ  alef with hamza below
  'آ', // آ  alef with madda
};

/// Indices in [text] where a tatweel may legally be inserted (i.e. right before
/// the returned index). A gap qualifies when the previous base letter connects
/// to its left, the next base letter connects to its right, only diacritics
/// sit between them (no space, `=`, or punctuation), and the pair isn't a
/// lam-alef ligature (see [_noRightJoin]).
List<int> kashidaInsertionPoints(String text) {
  final points = <int>[];
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (!_isBaseLetter(ch) || _noLeftJoin.contains(ch)) continue;
    // Skip any diacritics bound to this letter to find the next real character.
    var j = i + 1;
    while (j < text.length && _isDiacritic(text[j])) {
      j++;
    }
    if (j >= text.length) break;
    final next = text[j];
    final blockedByLamAlef = ch == _lam && _noRightJoin.contains(next);
    if (_isBaseLetter(next) && next != _hamza && !blockedByLamAlef) {
      points.add(j); // insert the tatweel just before the next letter
    }
  }
  return points;
}

/// Inserts [count] tatweel characters into [text], spread as evenly as possible
/// across [points] (as returned by [kashidaInsertionPoints]). Returns [text]
/// unchanged when there is nothing to do.
String insertKashida(String text, List<int> points, int count) {
  if (count <= 0 || points.isEmpty) return text;
  final n = points.length;
  final perPoint = List<int>.filled(n, count ~/ n);
  final rem = count % n;
  // Scatter the remainder across evenly spaced points rather than clumping it.
  for (var k = 0; k < rem; k++) {
    perPoint[(k * n) ~/ rem] += 1;
  }
  final add = <int, int>{for (var k = 0; k < n; k++) points[k]: perPoint[k]};

  final sb = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final t = add[i];
    if (t != null) {
      for (var c = 0; c < t; c++) {
        sb.write(tatweel);
      }
    }
    sb.write(text[i]);
  }
  return sb.toString();
}

/// Rendered width of [text] in [style] under [scaler], laid out RTL on one line.
double measureTextWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.rtl,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// Returns [text] with tatweel inserted so it renders as close to [targetWidth]
/// as possible **without exceeding it** (so a justified line can never overflow
/// and wrap). Text already at/over the target, or with no legal insertion point,
/// is returned unchanged.
String kashidaJustify(
  String text,
  TextStyle style,
  double targetWidth,
  TextScaler scaler,
) {
  final natural = measureTextWidth(text, style, scaler);
  if (natural >= targetWidth) return text;

  final points = kashidaInsertionPoints(text);
  if (points.isEmpty) return text;

  final tatweelWidth = measureTextWidth(tatweel, style, scaler);
  if (tatweelWidth <= 0) return text;

  // Estimate the number of tatweels from the average glyph width, then correct
  // by measuring — only a couple of layouts in practice.
  var count = ((targetWidth - natural) / tatweelWidth).round();
  if (count < 0) count = 0;

  var best = insertKashida(text, points, count);
  var bestWidth = measureTextWidth(best, style, scaler);

  // If the estimate overshot, shrink until we are within budget.
  var guard = 0;
  while (bestWidth > targetWidth && count > 0 && guard < 8) {
    count--;
    best = insertKashida(text, points, count);
    bestWidth = measureTextWidth(best, style, scaler);
    guard++;
  }
  // Then grow while we still fit, keeping the widest result that fits.
  guard = 0;
  while (guard < 8) {
    final nextCount = count + 1;
    final next = insertKashida(text, points, nextCount);
    final nextWidth = measureTextWidth(next, style, scaler);
    if (nextWidth > targetWidth) break;
    count = nextCount;
    best = next;
    bestWidth = nextWidth;
    guard++;
  }
  return best;
}
