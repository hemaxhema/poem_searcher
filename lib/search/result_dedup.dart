import '../db/poem_dedup.dart' show cleanLine, strippedLine;
import '../db/poem_repository.dart';

/// One display row: the result actually shown, plus any other confirmed
/// matches whose text collapsed into it (see [groupTitleResults] /
/// [groupLineResults]) that are hidden behind a badge instead of their own
/// tile.
typedef ResultGroup<T> = ({T shown, List<T> duplicates});

/// Splits [results] into groups sharing the same [keyOf] key, preserving
/// input order: the first result seen for a key becomes that group's `shown`
/// entry, every later result with the same key is filed under `duplicates`.
///
/// Relies on [results] already being grouped contiguously by source priority
/// (see `sortLineResults`/`sortTitleResults` in `search_sort.dart`, applied
/// before this runs): the first occurrence of a key is therefore always the
/// copy from the highest-priority (first-in-order) source, so keeping that
/// one and hiding the rest is exactly "prefer the first source in source
/// order".
List<ResultGroup<T>> groupByKey<T, K>(
  List<T> results,
  K Function(T) keyOf,
) {
  final keysInOrder = <K>[];
  final byKey = <K, List<T>>{};
  for (final r in results) {
    final key = keyOf(r);
    final bucket = byKey.putIfAbsent(key, () {
      keysInOrder.add(key);
      return [];
    });
    bucket.add(r);
  }
  return [
    for (final key in keysInOrder)
      (shown: byKey[key]!.first, duplicates: byKey[key]!.skip(1).toList()),
  ];
}

/// Tashkeel/tatweel-insensitive text key, using the same normalization the
/// offline build-time merge tool uses ([cleanLine] + [strippedLine] from
/// `poem_dedup.dart`) so sources that vocalize identical wording differently
/// still collapse together.
String _textKey(String s) => strippedLine(cleanLine(s));

/// Groups title results by normalized title text: the same poem catalogued
/// more than once — whether as one DB row matched under several sources via
/// `poem_alias`, or as separate poem rows the offline merge left unmerged
/// (differently-spelled poet attribution, or a differently-lengthed copy
/// under a variant scribal transmission — same title text still counts as
/// "the same result" here). Trade-off: two genuinely different poems that
/// happen to share a generic/common title (rare, but not impossible) would
/// also collapse; deliberate, since scraped near-duplicates are far more
/// common than that coincidence in this corpus.
List<ResultGroup<TitleResult>> groupTitleResults(List<TitleResult> results) =>
    groupByKey(results, (r) => _textKey(r.title));

/// [groupTitleResults]' counterpart for verse-line results: groups purely by
/// normalized line text, regardless of which poem/poet it was attributed to
/// or how long that poem is — classical verses are frequently quoted or
/// answered across poems of differing length, and those still read as the
/// same duplicated line to a reader of the results list.
List<ResultGroup<LineResult>> groupLineResults(List<LineResult> results) =>
    groupByKey(results, (r) => _textKey(r.original));
