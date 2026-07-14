import 'package:flutter/foundation.dart';

import '../db/poem_repository.dart';
import '../db/poem_search_api.dart';
import '../models/source.dart';
import '../search/boolean_query.dart';
import '../search/result_dedup.dart';
import '../search/results_pagination.dart';
import '../search/search_sort.dart';
import '../services/search_sort_prefs.dart';
import '../services/search_titles_prefs.dart';
import '../services/source_filter_prefs.dart';

/// Search orchestration shared by the home page and the poet page: runs the
/// plain/boolean searches, guards against stale results, derives the sorted
/// and grouped display lists, and owns the prefs-backed knobs (source order,
/// sort mode, titles toggle).
///
/// Named `PoemSearchController` (not `SearchController`) because Flutter's
/// material library already exports a `SearchController`.
///
/// Views render from the read-only state below inside a `ListenableBuilder`
/// and mutate it only through the command methods; genuinely visual concerns
/// (focus, scrolling, navigation, dialogs) stay in the widgets.
class PoemSearchController extends ChangeNotifier {
  PoemSearchController({
    required this.api,
    this.poet,
    this.useTitlesPref = true,
    this.pageSize = 100,
  });

  final PoemSearchApi api;

  /// When non-null every search is scoped to this poet (the poet page).
  final String? poet;

  /// Whether the titles section obeys the persisted `SearchTitlesPrefs`
  /// toggle (home page) or titles are always searched (poet page).
  final bool useTitlesPref;

  /// Number of result tiles shown per page (see [pageWindow]).
  final int pageSize;

  // ---------------------------------------------------------------- state --

  String _query = '';
  BoolExpr? _boolExpr;
  String? _boolDescription;
  String _boolRaw = '';
  bool _isSearching = false;

  /// Monotonic token so a slow search that resolves after a newer one has
  /// started is discarded instead of overwriting fresher results.
  int _searchToken = 0;

  /// Replaces the widget-level `mounted` check of the old in-`State`
  /// orchestration: results arriving after [dispose] are dropped and
  /// `notifyListeners` is never called again.
  bool _disposed = false;

  /// Repository output, in relevance order — the source of truth from the
  /// last search. Display lists are derived from these by [_applySort].
  List<TitleResult> _rawTitleMatches = const [];
  List<LineResult> _rawLineMatches = const [];

  List<TitleResult> _sortedTitles = const [];
  List<LineResult> _sortedLines = const [];
  List<ResultGroup<TitleResult>> _titleGroups = const [];
  List<ResultGroup<LineResult>> _lineGroups = const [];

  SearchSort _sortMode = SearchSort.lineCountDesc;
  List<Source> _sourceOrder = Source.values;
  bool _searchInTitles = SearchTitlesPrefs.defaultEnabled;
  int _page = 0;

  // ------------------------------------------------------ read-only state --

  /// The trimmed query currently driving the results (empty in boolean mode).
  String get query => _query;

  /// The active boolean-search expression, or `null` when searching via the
  /// plain box.
  BoolExpr? get boolExpr => _boolExpr;

  /// Plain-Arabic description of [boolExpr] for the banner, or `null`.
  String? get boolDescription => _boolDescription;

  /// The raw boolean expression text, kept so the editor reopens pre-filled.
  String get boolRaw => _boolRaw;

  /// True while a search is in flight, so the results area can show a
  /// loading spinner instead of stale results during the DB query.
  bool get isSearching => _isSearching;

  /// True when a search (plain box or boolean) is currently driving the
  /// results area.
  bool get hasActiveSearch => _query.isNotEmpty || _boolExpr != null;

  SearchSort get sortMode => _sortMode;
  List<Source> get sourceOrder => _sourceOrder;

  /// Whether searches also run over poem titles (see [useTitlesPref]).
  bool get searchInTitles => useTitlesPref ? _searchInTitles : true;

  /// Current 0-based results page. Reset to 0 on every new search.
  int get page => _page;

  /// Sorted (ungrouped) display lists — what the poet page renders.
  List<TitleResult> get sortedTitles => _sortedTitles;
  List<LineResult> get sortedLines => _sortedLines;

  /// Sorted display lists with same-wording results collapsed to one tile
  /// each (see `result_dedup.dart`) — what the home page renders.
  List<ResultGroup<TitleResult>> get titleGroups => _titleGroups;
  List<ResultGroup<LineResult>> get lineGroups => _lineGroups;

  /// Page geometry over the grouped lists for the current [page]. Cheap to
  /// compute, so views derive it fresh each build.
  PageWindow get pageWindow => PageWindow.compute(
        titleCount: _titleGroups.length,
        lineCount: _lineGroups.length,
        page: _page,
        pageSize: pageSize,
      );

  // -------------------------------------------------------------- commands --

  /// Loads the persisted knobs (source order, sort mode, titles toggle),
  /// notifying as each arrives — same progressive behavior as the old
  /// per-pref `initState` loads.
  Future<void> loadPrefs() async {
    SourceFilterPrefs.load().then((order) {
      if (_disposed) return;
      _sourceOrder = order;
      notifyListeners();
    });
    SearchSortPrefs.load().then((sort) {
      if (_disposed) return;
      _sortMode = sort;
      _applySort();
      notifyListeners();
    });
    if (useTitlesPref) {
      SearchTitlesPrefs.load().then((enabled) {
        if (_disposed) return;
        _searchInTitles = enabled;
        notifyListeners();
      });
    }
  }

  /// Reloads every persisted knob and re-runs the active search — called when
  /// returning from the Settings page, where a source-order/subset change
  /// affects which rows are fetched, not just their display order.
  Future<void> reloadPrefsAndRerun() async {
    final order = await SourceFilterPrefs.load();
    final sort = await SearchSortPrefs.load();
    final searchTitles =
        useTitlesPref ? await SearchTitlesPrefs.load() : _searchInTitles;
    if (_disposed) return;
    _sourceOrder = order;
    _sortMode = sort;
    _searchInTitles = searchTitles;
    _applySort();
    notifyListeners();
    rerunActiveSearch();
  }

  /// Dispatches a (debounced, already-settled) plain-box query. Typing in the
  /// plain box takes over from any active boolean search.
  void onQueryChanged(String raw) {
    final trimmed = raw.trim();
    _query = trimmed;
    _boolExpr = null;
    _boolDescription = null;
    _boolRaw = '';
    if (trimmed.isEmpty) {
      _clearResults();
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    _runSearch(trimmed);
  }

  /// Switches to boolean mode (clearing the plain query) and runs [expr].
  /// [raw] is the expression text as typed, kept for re-editing.
  Future<void> runBooleanSearch(String raw, BoolExpr expr) {
    _boolExpr = expr;
    _boolDescription = expr.describeArabic();
    _boolRaw = raw;
    _query = '';
    _isSearching = true;
    _page = 0;
    notifyListeners();
    return _runBooleanSearch(expr);
  }

  /// Clears the active boolean search and returns to the empty/plain state.
  void clearBooleanSearch() {
    _boolExpr = null;
    _boolDescription = null;
    _boolRaw = '';
    _rawTitleMatches = const [];
    _rawLineMatches = const [];
    _clearResults();
    notifyListeners();
  }

  /// Switches the result sort mode, reordering already-fetched results in
  /// memory (no query, no [_searchToken] change) and persisting the choice.
  Future<void> setSortMode(SearchSort mode) async {
    if (mode == _sortMode) return;
    _sortMode = mode;
    _applySort();
    notifyListeners();
    await SearchSortPrefs.save(mode);
  }

  /// Applies a new source order/subset, persists it, and re-runs the active
  /// search (the order affects which rows are fetched, not just display).
  Future<void> setSourceOrder(List<Source> order) async {
    _sourceOrder = order;
    _applySort();
    notifyListeners();
    await SourceFilterPrefs.save(order);
    rerunActiveSearch();
  }

  /// Jumps to [page] (clamped by [pageWindow] when rendering).
  void goToPage(int page) {
    _page = page;
    notifyListeners();
  }

  /// Re-runs whichever search is active (after a source-filter change).
  void rerunActiveSearch() {
    if (_boolExpr != null) {
      _runBooleanSearch(_boolExpr!);
    } else if (_query.isNotEmpty) {
      _runSearch(_query);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ------------------------------------------------------------- internals --

  void _clearResults() {
    _sortedTitles = const [];
    _sortedLines = const [];
    _titleGroups = const [];
    _lineGroups = const [];
    _isSearching = false;
    _page = 0;
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final titleFuture = searchInTitles
        ? api.searchTitles(query, poet: poet, sourceOrder: _sourceOrder)
        : Future<List<TitleResult>>.value(const []);
    final results = await Future.wait([
      titleFuture,
      api.searchLines(query, poet: poet, sourceOrder: _sourceOrder),
    ]);
    // Drop stale results (a newer query started, or the box changed/emptied).
    if (_disposed || token != _searchToken || query != _query) return;
    _rawTitleMatches = results[0] as List<TitleResult>;
    _rawLineMatches = results[1] as List<LineResult>;
    _applySort();
    _isSearching = false;
    _page = 0;
    notifyListeners();
  }

  /// Boolean-mode counterpart of [_runSearch], with the same stale guard.
  Future<void> _runBooleanSearch(BoolExpr expr) async {
    final token = ++_searchToken;
    final titleFuture = searchInTitles
        ? api.searchTitlesBoolean(expr, poet: poet, sourceOrder: _sourceOrder)
        : Future<List<TitleResult>>.value(const []);
    final results = await Future.wait([
      titleFuture,
      api.searchLinesBoolean(expr, poet: poet, sourceOrder: _sourceOrder),
    ]);
    // Drop stale results (a newer search started, or boolean mode was cleared).
    if (_disposed || token != _searchToken || !identical(expr, _boolExpr)) {
      return;
    }
    _rawTitleMatches = results[0] as List<TitleResult>;
    _rawLineMatches = results[1] as List<LineResult>;
    _applySort();
    _isSearching = false;
    _page = 0;
    notifyListeners();
  }

  /// Derives the display lists from the raw (relevance-ordered) results per
  /// the current [sortMode] and source order, then collapses same-wording
  /// results down to one tile per distinct poem/line for the grouped views.
  /// Cheap in-memory work — no DB hit.
  void _applySort() {
    _sortedTitles = sortTitleResults(_rawTitleMatches, _sortMode, _sourceOrder);
    _sortedLines = sortLineResults(_rawLineMatches, _sortMode, _sourceOrder);
    _titleGroups = groupTitleResults(_sortedTitles);
    _lineGroups = groupLineResults(_sortedLines);
  }
}
