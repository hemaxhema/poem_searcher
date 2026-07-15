import 'dart:math';

import 'package:flutter/rendering.dart';

import '../models/poem_line.dart';
import '../util/kashida.dart';

/// Result of laying out a poem's verses: the kashida-justified display string
/// for each line (keyed by line id) plus the [fontSize] they should actually be
/// rendered at. The font size is the requested one, or a smaller value when the
/// widest verse would otherwise overflow the available width (see
/// [computeKashidaDisplay]) — never larger, so the user's chosen size is a cap.
typedef KashidaDisplay = ({Map<int, String> display, double fontSize});

/// Presentation-layer helper: builds and memoizes the kashida-justified
/// display strings for one poem. It depends on [TextStyle]/[TextScaler]
/// measurement ([measureTextWidth] uses a `TextPainter`) on purpose — this is
/// rendering logic, not backend logic — and it renders identically on every
/// Flutter platform, so the Android UI reuses it unchanged.
class KashidaDisplayCache {
  KashidaDisplay? _cache;
  TextScaler? _scaler;
  double? _width;
  double? _fontSize;
  String? _fontFamily;

  /// Returns the [KashidaDisplay] for a poem, memoized on the [scaler],
  /// [available] width, and [style]'s font size and font family so the
  /// (moderately expensive) text measurement runs once per poem rather than on
  /// every scroll rebuild — and is recomputed if any of those change, since
  /// justification widths depend on the font's glyph metrics. The requested
  /// [style] font size is part of the key; the fitted size it may shrink to is
  /// a deterministic function of the key, so it needs no separate entry.
  KashidaDisplay displayFor(
    List<PoemLine> lines,
    TextStyle style,
    TextScaler scaler,
    double available,
  ) {
    if (_cache != null &&
        _scaler == scaler &&
        _width == available &&
        _fontSize == style.fontSize &&
        _fontFamily == style.fontFamily) {
      return _cache!;
    }
    final result = computeKashidaDisplay(lines, style, scaler, available);
    _cache = result;
    _scaler = scaler;
    _width = available;
    _fontSize = style.fontSize;
    _fontFamily = style.fontFamily;
    return result;
  }
}

/// The natural (un-stretched) widths a poem needs, measured once at a given
/// [TextStyle]: the widest single hemistich, the widest whole single-hemistich
/// line, the `=` separator's width, and whether any line has two hemistichs.
typedef _Extents = ({
  double maxHalf,
  double maxSingle,
  double sepWidth,
  bool hasTwoHemistichs,
});

/// Builds the elongated "sadr = ajz" strings and reports the font size to render
/// them at. Every hemistich is stretched to a single common half-width `H` (the
/// widest natural hemistich in the poem, capped so the line still fits
/// [available]), so all bayts end up the same width, sadr and ajz are equal, and
/// the `=` aligns in one central column.
///
/// Lines without a `=` (single hemistich) are stretched to the width of a whole
/// normal verse: `2*H + separator` when the poem has two-hemistich lines, or —
/// for a poem that has no `=` at all — the width of the widest single line.
///
/// Because kashida can only *stretch* a hemistich, never shrink one, a verse
/// whose natural width already exceeds [available] would overflow. To prevent
/// that, the whole poem's font is first scaled down uniformly (never up) to the
/// largest size at which the widest verse still fits, and every verse is then
/// laid out at that one [KashidaDisplay.fontSize].
KashidaDisplay computeKashidaDisplay(
  List<PoemLine> lines,
  TextStyle style,
  TextScaler scaler,
  double available,
) {
  final requestedSize = style.fontSize;
  final ext = _measureExtents(lines, style, scaler);

  // Largest uniform scale (<= 1) at which the widest verse fits [available].
  // Glyph advance widths scale ~linearly with font size, so the scale can be
  // read straight off the natural widths measured at the requested size.
  var scale = 1.0;
  if (requestedSize != null && requestedSize > 0 && available > 0) {
    if (ext.hasTwoHemistichs) {
      final fullNatural = 2 * ext.maxHalf + ext.sepWidth;
      if (fullNatural > available) scale = min(scale, available / fullNatural);
    }
    if (ext.maxSingle > available) {
      scale = min(scale, available / ext.maxSingle);
    }
    if (scale < 1.0) {
      // A small safety margin absorbs the slight non-linearity of glyph
      // hinting so no verse is left a sub-pixel over the width after scaling.
      scale = (scale * 0.99).clamp(0.05, 1.0);
    }
  }

  // At scale == 1 nothing shrank, so reuse the style and extents already
  // measured; otherwise re-measure at the smaller size the verses will use.
  final effectiveStyle =
      scale < 1.0 ? style.copyWith(fontSize: requestedSize! * scale) : style;
  final effectiveExt =
      scale < 1.0 ? _measureExtents(lines, effectiveStyle, scaler) : ext;

  return (
    display: _justify(lines, effectiveStyle, scaler, available, effectiveExt),
    fontSize: effectiveStyle.fontSize ?? requestedSize ?? 0,
  );
}

/// Measures the natural extents (see [_Extents]) of [lines] in [style].
_Extents _measureExtents(
  List<PoemLine> lines,
  TextStyle style,
  TextScaler scaler,
) {
  final sepWidth = measureTextWidth(' = ', style, scaler);
  var maxHalf = 0.0;
  var maxSingle = 0.0;
  var hasTwoHemistichs = false;
  for (final line in lines) {
    if (line.hasTwoHemistichs) {
      hasTwoHemistichs = true;
      maxHalf = max(maxHalf, measureTextWidth(line.sadr, style, scaler));
      maxHalf = max(maxHalf, measureTextWidth(line.ajz, style, scaler));
    } else {
      maxSingle = max(maxSingle, measureTextWidth(line.line, style, scaler));
    }
  }
  return (
    maxHalf: maxHalf,
    maxSingle: maxSingle,
    sepWidth: sepWidth,
    hasTwoHemistichs: hasTwoHemistichs,
  );
}

/// Kashida-justifies every line to the common targets derived from [ext] and
/// [available], keyed by line id. Assumes [style] is already the size the
/// verses will render at (see [computeKashidaDisplay]).
Map<int, String> _justify(
  List<PoemLine> lines,
  TextStyle style,
  TextScaler scaler,
  double available,
  _Extents ext,
) {
  // Never let a justified line grow past the available width (else it wraps).
  final capHalf = (available - ext.sepWidth) / 2;
  final halfTarget = min(ext.maxHalf, capHalf);
  // Width of a whole normal verse. Single-hemistich lines are stretched to
  // this. When the poem has no `=` anywhere, the widest single line sets it.
  final fullTarget = ext.hasTwoHemistichs
      ? min(2 * halfTarget + ext.sepWidth, available)
      : min(ext.maxSingle, available);

  final map = <int, String>{};
  for (final line in lines) {
    if (line.hasTwoHemistichs) {
      final sadr = kashidaJustify(line.sadr, style, halfTarget, scaler);
      final ajz = kashidaJustify(line.ajz, style, halfTarget, scaler);
      map[line.id] = '$sadr = $ajz';
    } else {
      map[line.id] = kashidaJustify(line.line, style, fullTarget, scaler);
    }
  }
  return map;
}
