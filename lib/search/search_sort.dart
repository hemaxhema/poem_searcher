import '../db/poem_repository.dart';
import '../models/source.dart';
import 'tashkeel_search.dart';

/// How confirmed search results are ordered before they are shown.
///
/// Ordering is applied client-side over the already-fetched result lists (see
/// [sortLineResults]/[sortTitleResults]), so switching modes reorders in memory
/// with no database query.
enum SearchSort {
  /// Most-relevant first (by [matchTightness]), which is the order the
  /// repository already emits.
  lineCountDesc('line_count_desc', 'الأطول (عدد الأبيات)'),
  relevance('relevance', 'الأكثر صلة');

  /// The default: longest poems first (by `poem.line_count`), still grouped
  /// by source.


  const SearchSort(this.id, this.label);

  /// Stable identifier used for persistence (see `SearchSortPrefs`).
  final String id;

  /// Arabic label shown in the sort menu.
  final String label;

  /// The mode with the given [id], or [lineCountDesc] for an unknown/absent id.
  static SearchSort byId(String? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => lineCountDesc);
}

/// Reorders confirmed line results according to [sort], preserving the
/// source grouping in [order].
///
/// The repository emits results already grouped by source (in [order] priority)
/// and, within each group, sorted by [matchTightness]. For [SearchSort.relevance]
/// that is exactly the desired order, so the input is returned unchanged. For
/// [SearchSort.lineCountDesc] each group is reordered longest-first; the source
/// grouping is reproduced with an explicit group-rank key rather than relying on
/// sort stability (Dart's [List.sort] is not guaranteed stable).
///
/// Accuracy caveat: the coarse SQL pre-filter fetches candidates in rowid order
/// under a fixed `LIMIT` per source (see `_candidateLimit` in
/// `poem_repository.dart`), so this in-memory sort only orders what was fetched
/// — the genuinely longest matching poems can lie beyond that cap and never
/// surface at the top. This is the same capped approximation already accepted
/// for relevance ranking. If exactness is ever required for this mode, push
/// `ORDER BY p.line_count DESC` into the coarse query instead.
List<LineResult> sortLineResults(
  List<LineResult> results,
  SearchSort sort,
  List<Source> order,
) {
  if (sort == SearchSort.relevance) return results;
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  return [...results]..sort((a, b) {
      final ga = rank[a.source] ?? order.length;
      final gb = rank[b.source] ?? order.length;
      if (ga != gb) return ga.compareTo(gb);
      if (a.lineCount != b.lineCount) return b.lineCount.compareTo(a.lineCount);
      return matchTightness(b.start, b.end, b.original)
          .compareTo(matchTightness(a.start, a.end, a.original));
    });
}

/// Reorders confirmed title results according to [sort], preserving the source
/// grouping in [order]. See [sortLineResults] for the ordering rationale and the
/// accuracy caveat.
/// Orders poet names by poem count (descending), breaking ties by name
/// (ascending). [poemCountOf] supplies each poet's poem count (see
/// `PoemRepository.poemCountFor`). Returns a new list; the input is untouched.
List<String> sortPoetsByCount(
  List<String> poets,
  int Function(String poet) poemCountOf,
) {
  final sorted = [...poets];
  sorted.sort((a, b) {
    final byCount = poemCountOf(b).compareTo(poemCountOf(a));
    return byCount != 0 ? byCount : a.compareTo(b);
  });
  return sorted;
}

List<TitleResult> sortTitleResults(
  List<TitleResult> results,
  SearchSort sort,
  List<Source> order,
) {
  if (sort == SearchSort.relevance) return results;
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  return [...results]..sort((a, b) {
      final ga = rank[a.source] ?? order.length;
      final gb = rank[b.source] ?? order.length;
      if (ga != gb) return ga.compareTo(gb);
      if (a.lineCount != b.lineCount) return b.lineCount.compareTo(a.lineCount);
      return matchTightness(b.start, b.end, b.title)
          .compareTo(matchTightness(a.start, a.end, a.title));
    });
}
