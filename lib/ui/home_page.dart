import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/poem_repository.dart';
import '../models/source.dart';
import '../search/boolean_query.dart';
import '../search/search_sort.dart';
import '../services/app_fonts.dart';
import '../services/search_sort_prefs.dart';
import '../services/source_filter_prefs.dart';
import '../widgets/help_dialog.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/search_field.dart';
import '../widgets/section_header.dart';
import '../widgets/source_badge.dart';
import '../widgets/source_filter_dialog.dart';
import 'boolean_search_page.dart';
import 'poem_detail_page.dart';
import 'poets_page.dart';
import 'results_pagination.dart';

/// Main screen: a search bar with live tashkeel-aware results underneath.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repo});

  final PoemRepository repo;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Number of result tiles shown per page.
  static const int _pageSize = 100;

  String _query = '';

  /// The active boolean-search expression, or `null` when searching via the
  /// plain box. When set, [_runSearch] uses the boolean repository methods and a
  /// banner explaining it (in Arabic) is shown above the results.
  BoolExpr? _boolExpr;
  String? _boolDescription;

  /// The raw boolean expression text, kept so the window reopens pre-filled.
  String _boolRaw = '';

  /// Bumped to force the plain [SearchField] to reset its text (e.g. when a
  /// boolean search takes over) via a changing [ValueKey].
  int _searchFieldEpoch = 0;

  /// Repository output, in relevance order — the source of truth from the last
  /// search. Display lists are derived from these by [_applySort].
  List<LineResult> _rawLineMatches = const [];
  List<TitleResult> _rawTitleMatches = const [];

  /// Display lists (sorted per [_sortMode]) that the list/pager read.
  List<LineResult> _lineMatches = const [];
  List<TitleResult> _titleMatches = const [];

  /// How results are ordered. Loaded from (and saved to) persisted prefs.
  SearchSort _sortMode = SearchSort.relevance;

  /// Current 0-based results page. Reset to 0 on every new search.
  int _page = 0;

  /// True while a search is in flight, so the results area can show a
  /// loading spinner instead of stale results during the DB query.
  bool _isSearching = false;

  /// Monotonic token so a slow search that resolves after a newer one has
  /// started is discarded instead of overwriting fresher results.
  int _searchToken = 0;

  /// Selected sources, in search priority order. Loaded from (and saved to)
  /// persisted prefs so the choice survives app restarts.
  List<Source> _sourceOrder = Source.values;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  /// Drives the results list so a page change can jump back to the top.
  final ScrollController _resultsController = ScrollController();

  @override
  void initState() {
    super.initState();
    SourceFilterPrefs.load().then((order) {
      if (mounted) setState(() => _sourceOrder = order);
    });
    SearchSortPrefs.load().then((sort) {
      if (mounted) {
        setState(() {
          _sortMode = sort;
          _applySort();
        });
      }
    });
  }

  /// Derives the display lists from the raw (relevance-ordered) results per the
  /// current [_sortMode] and source order. Cheap in-memory reorder — no DB hit.
  void _applySort() {
    _titleMatches = sortTitleResults(_rawTitleMatches, _sortMode, _sourceOrder);
    _lineMatches = sortLineResults(_rawLineMatches, _sortMode, _sourceOrder);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    _resultsController.dispose();
    super.dispose();
  }

  Future<void> _openSourceFilter() async {
    final result = await showSourceFilterDialog(context, _sourceOrder);
    if (result == null) return;
    setState(() => _sourceOrder = result);
    await SourceFilterPrefs.save(result);
    _rerunActiveSearch();
  }

  /// True when a search (plain box or boolean) is currently driving the results
  /// area — used to decide between the empty hint and the results list/pager.
  bool get _hasActiveSearch => _query.isNotEmpty || _boolExpr != null;

  /// Re-runs whichever search is active (after a source-filter change).
  void _rerunActiveSearch() {
    if (_boolExpr != null) {
      _runBooleanSearch(_boolExpr!);
    } else if (_query.isNotEmpty) {
      _runSearch(_query);
    }
  }

  /// Opens the boolean-search window; on confirm, switches to boolean mode
  /// (clearing the plain box) and runs it.
  Future<void> _openBooleanSearch() async {
    final result = await Navigator.of(context).push<BooleanSearchResult>(
      MaterialPageRoute(
        builder: (_) => BooleanSearchPage(initialExpression: _boolRaw),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _boolExpr = result.expr;
      _boolDescription = result.expr.describeArabic();
      _boolRaw = result.raw;
      _query = '';
      _searchFieldEpoch++; // reset the plain box text
      _isSearching = true;
      _page = 0;
    });
    _runBooleanSearch(result.expr);
  }

  /// Clears the active boolean search and returns to the empty/plain state.
  void _clearBooleanSearch() {
    setState(() {
      _boolExpr = null;
      _boolDescription = null;
      _boolRaw = '';
      _titleMatches = const [];
      _lineMatches = const [];
      _rawTitleMatches = const [];
      _rawLineMatches = const [];
      _isSearching = false;
      _page = 0;
    });
  }

  /// Switches the result sort mode. Reorders the already-fetched results in
  /// memory (no database query, no [_searchToken] change) and persists the
  /// choice. Result counts are unchanged, so [_pageWindow] stays valid.
  Future<void> _setSortMode(SearchSort mode) async {
    if (mode == _sortMode) return;
    setState(() {
      _sortMode = mode;
      _applySort();
      _page = 0;
    });
    if (_resultsController.hasClients) _resultsController.jumpTo(0);
    await SearchSortPrefs.save(mode);
  }

  void _focusFirstResult() {
    if (_titleMatches.isNotEmpty || _lineMatches.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
  }

  // SearchField already debounces keystrokes (see its `debounce` parameter
  // below), so this only needs to dispatch the (already-settled) query.
  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    _query = trimmed;
    // Typing in the plain box takes over from any active boolean search.
    _boolExpr = null;
    _boolDescription = null;
    _boolRaw = '';
    if (trimmed.isEmpty) {
      setState(() {
        _titleMatches = const [];
        _lineMatches = const [];
        _isSearching = false;
        _page = 0;
      });
      return;
    }
    setState(() => _isSearching = true);
    _runSearch(trimmed);
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final results = await Future.wait([
      widget.repo.searchTitles(query, sourceOrder: _sourceOrder),
      widget.repo.searchLines(query, sourceOrder: _sourceOrder),
    ]);
    // Drop stale results (a newer query started, or the box changed/emptied).
    if (!mounted || token != _searchToken || query != _query) return;
    setState(() {
      _rawTitleMatches = results[0] as List<TitleResult>;
      _rawLineMatches = results[1] as List<LineResult>;
      _applySort();
      _isSearching = false;
      _page = 0;
    });
  }

  /// Boolean-mode counterpart of [_runSearch]: runs the parsed [expr] against
  /// the boolean repository methods, with the same stale-result guard.
  Future<void> _runBooleanSearch(BoolExpr expr) async {
    final token = ++_searchToken;
    final results = await Future.wait([
      widget.repo.searchTitlesBoolean(expr, sourceOrder: _sourceOrder),
      widget.repo.searchLinesBoolean(expr, sourceOrder: _sourceOrder),
    ]);
    // Drop stale results (a newer search started, or boolean mode was cleared).
    if (!mounted || token != _searchToken || !identical(expr, _boolExpr)) return;
    setState(() {
      _rawTitleMatches = results[0] as List<TitleResult>;
      _rawLineMatches = results[1] as List<LineResult>;
      _applySort();
      _isSearching = false;
      _page = 0;
    });
  }

  /// Page geometry for the current results and selected page. Cheap to compute,
  /// so both the list and the pager derive from it fresh each build.
  PageWindow get _pageWindow => PageWindow.compute(
        titleCount: _titleMatches.length,
        lineCount: _lineMatches.length,
        page: _page,
        pageSize: _pageSize,
      );

  /// Jumps to [page] and scrolls the results list back to the top so each page
  /// reads from the first result down.
  void _goToPage(int page) {
    setState(() => _page = page);
    if (_resultsController.hasClients) _resultsController.jumpTo(0);
  }

  void _openPoem(int poemId, {int? lineId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PoemDetailPage(
        repo: widget.repo,
        poemId: poemId,
        highlightLineId: lineId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 12,
        title: Text(
          'البحث في الشعر',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'الشعراء',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PoetsPage(repo: widget.repo),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.rule),
            tooltip: 'بحث منطقي',
            onPressed: _openBooleanSearch,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'المصادر',
            onPressed: _openSourceFilter,
          ),
          PopupMenuButton<SearchSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'ترتيب النتائج',
            initialValue: _sortMode,
            onSelected: _setSortMode,
            itemBuilder: (_) => [
              for (final sort in SearchSort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: sort == _sortMode,
                  child: Text(sort.label),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'مساعدة',
            onPressed: () => showHelpDialog(context),
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            _searchFocusNode.requestFocus();
          },
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SearchField(
                key: ValueKey(_searchFieldEpoch),
                focusNode: _searchFocusNode,
                debounce: const Duration(seconds: 1),
                onChanged: _onQueryChanged,
                onSubmitted: _focusFirstResult,
              ),
            ),
            if (_boolDescription != null)
              _BooleanSearchBanner(
                description: _boolDescription!,
                onEdit: _openBooleanSearch,
                onClear: _clearBooleanSearch,
              ),
            Expanded(child: _buildResults()),
            if (!_isSearching && _hasActiveSearch && _pageWindow.totalPages > 1)
              _ResultsPager(
                page: _pageWindow.page,
                totalPages: _pageWindow.totalPages,
                onPrev: _pageWindow.page > 0
                    ? () => _goToPage(_pageWindow.page - 1)
                    : null,
                onNext: _pageWindow.page < _pageWindow.totalPages - 1
                    ? () => _goToPage(_pageWindow.page + 1)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (!_hasActiveSearch) {
      return const _EmptyHint(
        icon: Icons.search,
        message: 'اكتب كلمة للبحث في الأبيات.\n'
            'التشكيل اختياري: بدون تشكيل يُطابق كل الحركات، '
            'ومع التشكيل يلتزم به.',
      );
    }
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_titleMatches.isEmpty && _lineMatches.isEmpty) {
      return const _EmptyHint(
        icon: Icons.search_off,
        message: 'لا توجد نتائج.',
      );
    }

    // Only the current page's slice of each section is rendered; section
    // headers keep showing the full totals. Flattened item model so the list
    // builds lazily: [titles header, title tiles…], then [lines header, line
    // tiles…], with the first tile on the page taking keyboard focus.
    final window = _pageWindow;
    final hasTitles = window.titleCountOnPage > 0;
    final titleBlock = hasTitles ? 1 + window.titleCountOnPage : 0;
    final lineHeaderIndex = titleBlock;
    final itemCount =
        titleBlock + (window.lineCountOnPage > 0 ? 1 + window.lineCountOnPage : 0);

    return ListView.builder(
      controller: _resultsController,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasTitles && index < titleBlock) {
          if (index == 0) {
            return SectionHeader('عناوين (${_titleMatches.length})');
          }
          final i = index - 1;
          final match = _titleMatches[window.titleStart + i];
          return _TitleResultTile(
            match: match,
            focusNode: i == 0 ? _firstResultFocusNode : null,
            onTap: () => _openPoem(match.poemId),
          );
        }
        if (index == lineHeaderIndex) {
          return SectionHeader('أبيات (${_lineMatches.length})');
        }
        final i = index - lineHeaderIndex - 1;
        final match = _lineMatches[window.lineStart + i];
        return _LineResultTile(
          match: match,
          focusNode: (!hasTitles && i == 0) ? _firstResultFocusNode : null,
          onTap: () => _openPoem(match.poemId, lineId: match.lineId),
        );
      },
    );
  }
}

class _LineResultTile extends StatelessWidget {
  const _LineResultTile({
    required this.match,
    required this.onTap,
    this.focusNode,
  });

  final LineResult match;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = <String>[
      if (match.title.isNotEmpty) match.title,
      if (match.poet.isNotEmpty) match.poet,
    ].join(' — ');

    return Card(
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: AppFonts.currentFamily,
                builder: (context, family, _) => HighlightedText(
                  text: match.original,
                  start: match.start,
                  end: match.end,
                  style: theme.textTheme.titleLarge?.copyWith(
                    height: 1.8,
                    fontFamily: family,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SourceBadge(source: match.source),
                  const SizedBox(width: 8),
                  if (match.lineCount > 0) ...[
                    _LineCountBadge(count: match.lineCount),
                    const SizedBox(width: 8),
                  ],
                  if (subtitle.isNotEmpty)
                    Expanded(
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleResultTile extends StatelessWidget {
  const _TitleResultTile({
    required this.match,
    required this.onTap,
    this.focusNode,
  });

  final TitleResult match;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: AppFonts.currentFamily,
                builder: (context, family, _) => HighlightedText(
                  text: match.title,
                  start: match.start,
                  end: match.end,
                  style: theme.textTheme.titleLarge?.copyWith(
                    height: 1.8,
                    fontFamily: family,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SourceBadge(source: match.source),
                  const SizedBox(width: 8),
                  if (match.lineCount > 0) ...[
                    _LineCountBadge(count: match.lineCount),
                    const SizedBox(width: 8),
                  ],
                  if (match.poet.isNotEmpty)
                    Expanded(
                      child: Text(
                        match.poet,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill showing how many lines the poem has.
class _LineCountBadge extends StatelessWidget {
  const _LineCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.format_list_numbered,
            size: 14,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            '$count بيت',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom pager bar for the results list: «السابق  صفحة X / Y  التالي».
/// A `null` callback disables the corresponding button (first/last page).
class _ResultsPager extends StatelessWidget {
  const _ResultsPager({
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // In RTL the chevron points toward the previous page (rightward).
              TextButton.icon(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
                label: const Text('السابق'),
              ),
              Text(
                'صفحة ${page + 1} / $totalPages',
                style: theme.textTheme.bodyMedium,
              ),
              Directionality(
                textDirection:.ltr,
                child:TextButton.icon(
                onPressed: onNext,
                
                icon: const Icon(Icons.chevron_left),
                label: const Text('التالي'),
              ),)
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner shown above the results while a boolean search is active: the
/// plain-Arabic explanation of the expression, with edit and clear actions.
class _BooleanSearchBanner extends StatelessWidget {
  const _BooleanSearchBanner({
    required this.description,
    required this.onEdit,
    required this.onClear,
  });

  final String description;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.rule,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'بحث منطقي: $description',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: 'تعديل',
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSecondaryContainer,
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'إلغاء البحث المنطقي',
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSecondaryContainer,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
