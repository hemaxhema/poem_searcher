import 'dart:math' as math;

/// Pure geometry for slicing the combined search results into fixed-size pages.
///
/// Results are two sections shown back-to-back: title matches first, then verse
/// lines. They form one combined tile sequence (`[titles…, lines…]`) that is
/// paginated *together* — a page holds up to [pageSize] tiles drawn from either
/// or both sections. This class turns a requested page into the local index
/// ranges to render from each section, and clamps the page into a valid range
/// so a shrinking result set can't strand the view on a dead page.
class PageWindow {
  const PageWindow({
    required this.page,
    required this.totalPages,
    required this.titleStart,
    required this.titleEnd,
    required this.lineStart,
    required this.lineEnd,
  });

  /// The clamped, 0-based page actually shown (may differ from the requested one).
  final int page;

  /// Total number of pages (always at least 1, even with no results).
  final int totalPages;

  /// Local index range `[titleStart, titleEnd)` into the titles list on this page.
  final int titleStart;
  final int titleEnd;

  /// Local index range `[lineStart, lineEnd)` into the lines list on this page.
  final int lineStart;
  final int lineEnd;

  int get titleCountOnPage => titleEnd - titleStart;
  int get lineCountOnPage => lineEnd - lineStart;

  /// Computes the window for [page] given the two section sizes and [pageSize].
  factory PageWindow.compute({
    required int titleCount,
    required int lineCount,
    required int page,
    required int pageSize,
  }) {
    final total = titleCount + lineCount;
    final totalPages = total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
    final clampedPage = page < 0
        ? 0
        : (page >= totalPages ? totalPages - 1 : page);

    final start = clampedPage * pageSize;
    final end = math.min(start + pageSize, total);

    // Titles occupy the global range [0, titleCount); lines follow in
    // [titleCount, total). Intersect the page window [start, end) with each.
    final titleStart = math.min(start, titleCount);
    final titleEnd = math.min(end, titleCount);
    final lineStart = math.max(start, titleCount) - titleCount;
    final lineEnd = math.max(end, titleCount) - titleCount;

    return PageWindow(
      page: clampedPage,
      totalPages: totalPages,
      titleStart: titleStart,
      titleEnd: titleEnd,
      lineStart: lineStart,
      lineEnd: lineEnd,
    );
  }
}
