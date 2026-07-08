/// Boolean search: parses a user expression combining tashkeel-aware *terms*
/// with AND / OR / NOT and grouping, into an expression tree that can confirm a
/// line (Dart) and narrow candidates (SQL).
///
/// The boolean layer sits *above* the per-term regex: every leaf term is still
/// compiled by [buildRegex] / [coarseProbe] in tashkeel_search.dart exactly as a
/// normal query, so each term keeps all its features (`*`, `?`/`؟`, `_`,
/// `"..."` exact, diacritics, ي/ى & alif-hamza folds). Spaces inside a term
/// still mean a phrase; only the operator characters below are special.
///
/// Operators (all ASCII, chosen so they don't collide with Arabic text or the
/// existing query syntax):
///   `+`            AND
///   `|`            OR — the primary/taught symbol; `,` and `،` are accepted
///                  synonyms (but see [_emitCharClass] in tashkeel_search.dart:
///                  a `,`/`،` *inside* `[...]` is that group's own option
///                  separator, unrelated to this OR)
///   `-`            NOT ("and not")
///   `( )`          grouping — anywhere, including after `-` to negate a group
///
/// Precedence: OR is lowest, AND next, NOT highest; parentheses override. So
/// `A | B + C` is `A OR (B AND C)` and `A - (B + C)` is `A AND NOT(B AND C)`.
library;

import 'tashkeel_search.dart';

/// One node of a parsed boolean expression. See [parseBoolean].
sealed class BoolExpr {
  const BoolExpr();

  /// Confirms the whole expression against a line's [original] text and returns
  /// the highlight spans of every matching *positive* leaf (in [parts]/[options]
  /// order), or `null` if the line does not satisfy the expression. The list may
  /// be empty for a satisfied expression with no positive span to show (e.g. a
  /// purely-negative group).
  List<({int start, int end})>? match(String original);

  /// True when the expression is anchored by at least one positive term, so a
  /// bounded result set exists. A NOT-only expression (`-فراق`) is not.
  bool get hasPositive;

  /// A simple plain-Arabic rendering of the expression, for the preview shown to
  /// the user before running the search.
  String describeArabic();

  /// A SQL boolean predicate over the normalized column [col] that every match
  /// must satisfy (a *superset* filter — the precise decision is [match]), or
  /// `null` when the sub-expression cannot be narrowed in SQL (treated as true).
  /// Appends `LIKE` arguments to [args]; [escapeLike] escapes a probe literal.
  String? toSql(String col, List<Object?> args, String Function(String) escapeLike);

  /// The longest index-usable probe that must appear in every match (used to
  /// pick the FTS trigram driver), or `null` if none is guaranteed.
  String? mandatoryDriver();

  /// Whether this node needs parentheses when embedded in a larger description.
  bool get _needsGroupingInArabic => this is OrExpr || this is AndExpr;
}

/// Disjunction: matches when any [options] entry matches.
class OrExpr extends BoolExpr {
  const OrExpr(this.options);
  final List<BoolExpr> options;

  @override
  List<({int start, int end})>? match(String original) {
    for (final option in options) {
      final spans = option.match(original);
      if (spans != null) return spans;
    }
    return null;
  }

  @override
  bool get hasPositive =>
      options.isNotEmpty && options.every((o) => o.hasPositive);

  @override
  String describeArabic() =>
      options.map(_describeChild).join(' أو ');

  @override
  String? toSql(String col, List<Object?> args, String Function(String) esc) {
    // OR can only narrow if *every* branch narrows; one unconstrained branch
    // makes the union unconstrained. Build into a temp arg list so a bail-out
    // leaves [args] untouched (no orphan placeholders).
    final clauses = <String>[];
    final tmp = <Object?>[];
    for (final option in options) {
      final sql = option.toSql(col, tmp, esc);
      if (sql == null) return null;
      clauses.add(sql);
    }
    args.addAll(tmp);
    return '(${clauses.join(' OR ')})';
  }

  @override
  String? mandatoryDriver() => null;
}

/// Conjunction of signed parts: matches when every positive part matches and no
/// negated part matches. A negated part's [PartOf.child] may itself be a group,
/// which is how `- (B + C)` negates a whole group.
class AndExpr extends BoolExpr {
  const AndExpr(this.parts);
  final List<PartOf> parts;

  @override
  List<({int start, int end})>? match(String original) {
    final spans = <({int start, int end})>[];
    for (final part in parts) {
      if (part.negate) {
        if (part.child.match(original) != null) return null; // must NOT match
      } else {
        final s = part.child.match(original);
        if (s == null) return null; // required part missing
        spans.addAll(s);
      }
    }
    return spans;
  }

  @override
  bool get hasPositive =>
      parts.any((p) => !p.negate && p.child.hasPositive);

  @override
  String describeArabic() {
    final sb = StringBuffer();
    for (final part in parts) {
      final text = _describeChild(part.child);
      if (part.negate) {
        sb.write(sb.isEmpty ? 'بدون $text' : ' وبدون $text');
      } else {
        sb.write(sb.isEmpty ? text : ' و$text');
      }
    }
    return sb.toString();
  }

  @override
  String? toSql(String col, List<Object?> args, String Function(String) esc) {
    // Only positive parts constrain; negated parts are enforced in [match].
    final clauses = <String>[];
    for (final part in parts) {
      if (part.negate) continue;
      final sql = part.child.toSql(col, args, esc);
      if (sql != null) clauses.add(sql);
    }
    if (clauses.isEmpty) return null;
    if (clauses.length == 1) return clauses.first;
    return '(${clauses.join(' AND ')})';
  }

  @override
  String? mandatoryDriver() {
    String? best;
    for (final part in parts) {
      if (part.negate) continue;
      final d = part.child.mandatoryDriver();
      if (d != null && (best == null || d.length > best.length)) best = d;
    }
    return best;
  }
}

/// One signed operand of an [AndExpr].
class PartOf {
  const PartOf(this.negate, this.child);
  final bool negate;
  final BoolExpr child;
}

/// A single term — a full tashkeel-aware sub-query compiled to its own regex.
class TermLeaf extends BoolExpr {
  TermLeaf(this.raw, this.regex, this.probe);

  /// The term text exactly as the user typed it (used in [describeArabic]).
  final String raw;
  final RegExp regex;
  final CoarseProbe probe;

  @override
  List<({int start, int end})>? match(String original) {
    final span = confirmSpan(original, regex);
    return span == null ? null : [span];
  }

  @override
  bool get hasPositive => true;

  @override
  String describeArabic() => raw.contains('[') ? _glossBrackets(raw) : raw;

  @override
  String? toSql(String col, List<Object?> args, String Function(String) esc) {
    if (probe.probe.isEmpty) return null; // all-wildcard term: can't narrow.
    args.add('%${esc(probe.probe)}%');
    return "$col LIKE ? ESCAPE '\\'";
  }

  @override
  String? mandatoryDriver() => probe.canUseIndex ? probe.probe : null;
}

String _describeChild(BoolExpr child) {
  final text = child.describeArabic();
  return child._needsGroupingInArabic ? '($text)' : text;
}

/// Rewrites the `[...]` groups in a term into a readable Arabic gloss for the
/// preview: positive/empty options joined with «أو» (a blank slot → «لا شيء»),
/// and any `!`-excluded options appended as «عدا …», wrapped in «(…)». Text
/// outside the brackets is left as-is. E.g. `مسلم[ين,ون,]` → `مسلم(ين أو ون أو
/// لا شيء)`; `[ين,ون,!يَن]` → `(ين أو ون عدا يَن)`.
String _glossBrackets(String raw) {
  return raw.replaceAllMapped(RegExp(r'\[([^\]]*)\]'), (m) {
    final choices = <String>[];
    final excluded = <String>[];
    for (final rawOpt in m.group(1)!.split(RegExp('[,،]'))) {
      final opt = rawOpt.trim();
      if (opt.isEmpty) {
        choices.add('لا شيء');
      } else if (opt.startsWith('!')) {
        excluded.add(opt.substring(1).trim());
      } else {
        choices.add(opt);
      }
    }
    final sb = StringBuffer('(')..write(choices.join(' أو '));
    if (excluded.isNotEmpty) {
      if (choices.isNotEmpty) sb.write(' ');
      sb.write('عدا ${excluded.join(' و')}');
    }
    sb.write(')');
    return sb.toString();
  });
}

/// Outcome of [parseBoolean]: either a compiled [expr], or an Arabic [errorAr]
/// describing what is wrong so the UI can show it to the user.
class BoolParseResult {
  const BoolParseResult({this.expr, this.errorAr});
  final BoolExpr? expr;
  final String? errorAr;

  bool get isValid => expr != null;
}

/// Parses [query] into a boolean expression tree, or returns an Arabic error.
BoolParseResult parseBoolean(String query) {
  final tokens = _tokenize(query);
  if (tokens.isEmpty) {
    return const BoolParseResult(errorAr: 'اكتب تعبيرًا للبحث.');
  }
  try {
    final parser = _Parser(tokens);
    final expr = parser.parseExpression();
    parser.expectEnd();
    if (!expr.hasPositive) {
      return const BoolParseResult(
        errorAr: 'أضف كلمة واحدة على الأقل مطلوب وجودها (لا يكفي النفي وحده).',
      );
    }
    return BoolParseResult(expr: expr);
  } on _ParseError catch (e) {
    return BoolParseResult(errorAr: e.messageAr);
  }
}

// --- Tokenizer -------------------------------------------------------------

enum _TokKind { term, lparen, rparen, and, or, minus }

class _Tok {
  const _Tok(this.kind, [this.text = '']);
  final _TokKind kind;
  final String text;
}

const _orChars = {',', '،', '|'};

List<_Tok> _tokenize(String query) {
  final tokens = <_Tok>[];
  final buffer = StringBuffer();

  void flushTerm() {
    final term = buffer.toString().trim();
    if (term.isNotEmpty) tokens.add(_Tok(_TokKind.term, term));
    buffer.clear();
  }

  // Inside a `[...]` character class the operators are ordinary term
  // characters (its own `,` separates options, not an OR), so bracketed spans
  // are opaque to the tokenizer.
  var bracketDepth = 0;
  for (var i = 0; i < query.length; i++) {
    final ch = query[i];
    if (ch == '[') {
      bracketDepth++;
      buffer.write(ch);
      continue;
    }
    if (ch == ']') {
      if (bracketDepth > 0) bracketDepth--;
      buffer.write(ch);
      continue;
    }
    if (bracketDepth > 0) {
      buffer.write(ch);
      continue;
    }
    _TokKind? op;
    if (ch == '(') {
      op = _TokKind.lparen;
    } else if (ch == ')') {
      op = _TokKind.rparen;
    } else if (ch == '+') {
      op = _TokKind.and;
    } else if (ch == '-') {
      op = _TokKind.minus;
    } else if (_orChars.contains(ch)) {
      op = _TokKind.or;
    }
    if (op != null) {
      flushTerm();
      tokens.add(_Tok(op));
    } else {
      buffer.write(ch);
    }
  }
  flushTerm();
  return tokens;
}

// --- Parser ----------------------------------------------------------------

class _ParseError implements Exception {
  const _ParseError(this.messageAr);
  final String messageAr;
}

class _Parser {
  _Parser(this.tokens);
  final List<_Tok> tokens;
  int _pos = 0;

  _Tok? get _peek => _pos < tokens.length ? tokens[_pos] : null;
  _Tok _next() => tokens[_pos++];

  /// expr := and ( OR and )*
  BoolExpr parseExpression() {
    final options = <BoolExpr>[parseAnd()];
    while (_peek?.kind == _TokKind.or) {
      _next();
      options.add(parseAnd());
    }
    return options.length == 1 ? options.first : OrExpr(options);
  }

  /// and := ['-'] atom ( ('+' | '-') atom )*
  BoolExpr parseAnd() {
    final parts = <PartOf>[];
    var negate = false;
    if (_peek?.kind == _TokKind.minus) {
      _next();
      negate = true;
    }
    parts.add(PartOf(negate, parseAtom()));
    while (_peek?.kind == _TokKind.and || _peek?.kind == _TokKind.minus) {
      final op = _next();
      parts.add(PartOf(op.kind == _TokKind.minus, parseAtom()));
    }
    // Flatten a lone positive part so `(A)` and a bare term don't wrap.
    if (parts.length == 1 && !parts.first.negate) return parts.first.child;
    return AndExpr(parts);
  }

  /// atom := '(' expr ')' | term
  BoolExpr parseAtom() {
    final tok = _peek;
    if (tok == null) {
      throw const _ParseError('يوجد عامل (+ , -) بدون كلمة بعده.');
    }
    switch (tok.kind) {
      case _TokKind.lparen:
        _next();
        final inner = parseExpression();
        if (_peek?.kind != _TokKind.rparen) {
          throw const _ParseError('أقواس غير متوازنة: ينقص قوس إغلاق «)».');
        }
        _next();
        return inner;
      case _TokKind.term:
        _next();
        return _makeLeaf(tok.text);
      case _TokKind.rparen:
        throw const _ParseError('أقواس غير متوازنة: قوس إغلاق «)» زائد.');
      case _TokKind.and:
      case _TokKind.or:
      case _TokKind.minus:
        throw const _ParseError('يوجد عامل (+ , -) بدون كلمة بعده.');
    }
  }

  void expectEnd() {
    if (_peek != null) {
      if (_peek!.kind == _TokKind.rparen) {
        throw const _ParseError('أقواس غير متوازنة: قوس إغلاق «)» زائد.');
      }
      throw const _ParseError('تعبير غير صالح.');
    }
  }

  BoolExpr _makeLeaf(String raw) {
    _validateBrackets(raw);
    final regex = buildRegex(raw, charClass: true);
    if (regex == null) {
      throw _ParseError('مصطلح غير صالح: «$raw».');
    }
    return TermLeaf(raw, regex, coarseProbe(raw, charClass: true));
  }
}

/// A single base letter (U+0621..U+063A, U+0641..U+064A) — used to reject
/// multi-letter negatives in an only-exclusions `[...]` group.
final RegExp _baseLetterRe = RegExp('[ء-غف-ي]');

/// Validates every `[...]` group in a boolean term, throwing a [_ParseError]
/// with an Arabic message the live preview can show. Checks: balanced brackets,
/// non-empty group/options, and — when a group has only `!`-exclusions — that
/// each exclusion is a single letter (an only-negatives group matches one
/// letter, so a multi-letter exclusion has no well-defined width).
void _validateBrackets(String raw) {
  var depth = 0;
  for (final ch in raw.split('')) {
    if (ch == '[') depth++;
    if (ch == ']') depth--;
    if (depth < 0) {
      throw const _ParseError('أقواس مربعة غير متوازنة: «]» زائدة.');
    }
  }
  if (depth != 0) {
    throw const _ParseError('أقواس مربعة غير متوازنة: ينقص «]».');
  }
  for (final m in RegExp(r'\[([^\]]*)\]').allMatches(raw)) {
    final content = m.group(1)!;
    final options = content.split(RegExp('[,،]'));
    var positives = 0;
    final multiLetterNegatives = <String>[];
    var anyOption = false;
    for (final rawOpt in options) {
      var opt = rawOpt.trim();
      if (opt.isEmpty) continue;
      anyOption = true;
      final neg = opt.startsWith('!');
      if (neg) opt = opt.substring(1).trim();
      if (opt.isEmpty) {
        throw const _ParseError('خيار فارغ داخل الأقواس المربعة [ ].');
      }
      if (neg) {
        if (_baseLetterRe.allMatches(opt).length > 1) {
          multiLetterNegatives.add(opt);
        }
      } else {
        positives++;
      }
    }
    if (!anyOption) {
      throw const _ParseError('أقواس مربعة فارغة [].');
    }
    if (positives == 0 && multiLetterNegatives.isNotEmpty) {
      throw _ParseError(
        'مع النفي فقط داخل [ ] استخدم حرفًا واحدًا (مثل [!و])، '
        'أو أضف خيارًا موجبًا: «${multiLetterNegatives.first}».',
      );
    }
  }
}
