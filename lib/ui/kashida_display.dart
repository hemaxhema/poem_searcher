import 'dart:math';

import 'package:flutter/rendering.dart';

import '../models/poem_line.dart';
import '../util/kashida.dart';

/// Presentation-layer helper: builds and memoizes the kashida-justified
/// display strings for one poem. It depends on [TextStyle]/[TextScaler]
/// measurement ([measureTextWidth] uses a `TextPainter`) on purpose — this is
/// rendering logic, not backend logic — and it renders identically on every
/// Flutter platform, so the Android UI reuses it unchanged.
class KashidaDisplayCache {
  Map<int, String>? _cache;
  TextScaler? _scaler;
  double? _width;
  double? _fontSize;
  String? _fontFamily;

  /// Returns the kashida-justified display string for every line (keyed by
  /// line id), memoized on the [scaler], [available] width, and [style]'s
  /// font size and font family so the (moderately expensive) text measurement
  /// runs once per poem rather than on every scroll rebuild — and is
  /// recomputed if any of those change, since justification widths depend on
  /// the font's glyph metrics.
  Map<int, String> displayFor(
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
    final map = computeKashidaDisplay(lines, style, scaler, available);
    _cache = map;
    _scaler = scaler;
    _width = available;
    _fontSize = style.fontSize;
    _fontFamily = style.fontFamily;
    return map;
  }
}

/// Builds the elongated "sadr = ajz" strings. Every hemistich is stretched to
/// a single common half-width `H` (the widest natural hemistich in the poem,
/// capped so the line still fits [available]), so all bayts end up the same
/// width, sadr and ajz are equal, and the `=` aligns in one central column.
///
/// Lines without a `=` (single hemistich) are stretched to the width of a whole
/// normal verse: `2*H + separator` when the poem has two-hemistich lines, or —
/// for a poem that has no `=` at all — the width of the widest single line.
Map<int, String> computeKashidaDisplay(
  List<PoemLine> lines,
  TextStyle style,
  TextScaler scaler,
  double available,
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
  // Never let a justified line grow past the available width (else it wraps).
  final capHalf = (available - sepWidth) / 2;
  final halfTarget = min(maxHalf, capHalf);
  // Width of a whole normal verse. Single-hemistich lines are stretched to
  // this. When the poem has no `=` anywhere, the widest single line sets it.
  final fullTarget = hasTwoHemistichs
      ? min(2 * halfTarget + sepWidth, available)
      : min(maxSingle, available);

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
