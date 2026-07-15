import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/search_controller.dart';
import '../db/poem_repository.dart';
import '../services/app_fonts.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/count_badge.dart';
import '../widgets/global_control_shortcuts.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/search_field.dart';
import '../widgets/section_header.dart';
import '../widgets/source_badge.dart';
import '../widgets/source_filter_dialog.dart';
import 'boolean_search_page.dart';
import 'poem_detail_page.dart';
import 'poets_page.dart';
import 'settings_page.dart';

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

  /// All search state and orchestration; this widget only renders it and
  /// forwards user intent (see [PoemSearchController]).
  late final PoemSearchController _search = PoemSearchController(
    api: widget.repo,
    pageSize: _pageSize,
  );

  /// Bumped to force the plain [SearchField] to reset its text (e.g. when a
  /// boolean search takes over) via a changing [ValueKey].
  int _searchFieldEpoch = 0;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  /// Tracks the previous [PoemSearchController.isSearching] so we can detect
  /// the moment a search finishes (true → false) and auto-focus its first
  /// result — sort changes and pref reloads don't flip this flag, so they
  /// don't steal focus.
  bool _wasSearching = false;

  /// Drives the results list so a page change can jump back to the top.
  final ScrollController _resultsController = ScrollController();

  /// Ctrl+F/Ctrl+E work regardless of what (if anything) currently has
  /// keyboard focus — see [GlobalKeyboardShortcuts].
  late final GlobalKeyboardShortcuts _shortcuts = GlobalKeyboardShortcuts(
    controlBindings: {
      LogicalKeyboardKey.keyF: () => _searchFocusNode.requestFocus(),
      LogicalKeyboardKey.keyE: () => _openBooleanSearch(),
    },
    isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
  );

  @override
  void initState() {
    super.initState();
    _shortcuts.attach();
    _search.addListener(_onSearchStateChanged);
    _search.loadPrefs();
  }

  @override
  void dispose() {
    _shortcuts.dispose();
    _search.removeListener(_onSearchStateChanged);
    _search.dispose();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    _resultsController.dispose();
    super.dispose();
  }

  /// Quick-access shortcut to reorder/filter sources directly from the
  /// AppBar, without navigating into the full Settings page.
  Future<void> _openSourceFilter() async {
    final result = await showSourceFilterDialog(context, _search.sourceOrder);
    if (result == null) return;
    await _search.setSourceOrder(result);
  }

  /// Opens the consolidated Settings page; on return, reloads the source
  /// order/sort mode/titles toggle (mutated there now, not via an inline
  /// dialog/popup here) and re-runs the active search.
  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    await _search.reloadPrefsAndRerun();
  }

  /// Opens the boolean-search window; on confirm, switches to boolean mode
  /// (clearing the plain box) and runs it.
  Future<void> _openBooleanSearch() async {
    final result = await Navigator.of(context).push<BooleanSearchResult>(
      MaterialPageRoute(
        builder: (_) => BooleanSearchPage(initialExpression: _search.boolRaw),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _searchFieldEpoch++); // reset the plain box text
    _search.runBooleanSearch(result.raw, result.expr);
  }

  /// When a search finishes (isSearching flips true → false), auto-select its
  /// first result so the arrow keys navigate the list straight away (Down goes
  /// to the second result). Covers both live plain-box searches and the
  /// boolean search returning from its own window.
  void _onSearchStateChanged() {
    final searching = _search.isSearching;
    if (_wasSearching && !searching) {
      // The first tile mounts with its focus node during this frame's build;
      // request focus after it so the node is actually attached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusFirstResult();
      });
    }
    _wasSearching = searching;
  }

  void _focusFirstResult() {
    if (_search.titleGroups.isNotEmpty || _search.lineGroups.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
  }

  /// Jumps to [page] and scrolls the results list back to the top so each page
  /// reads from the first result down.
  void _goToPage(int page) {
    _search.goToPage(page);
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
            icon: const Icon(Icons.sort),
            tooltip: 'ترتيب المصادر',
            onPressed: _openSourceFilter,
          ),
          CommonAppBarActions(onOpenSettings: _openSettings),
        ],
      ),
      body: ListenableBuilder(
        listenable: _search,
        builder: (context, _) {
          final window = _search.pageWindow;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SearchField(
                  key: ValueKey(_searchFieldEpoch),
                  focusNode: _searchFocusNode,
                  debounce: const Duration(seconds: 1),
                  onChanged: _search.onQueryChanged,
                  onSubmitted: _focusFirstResult,
                ),
              ),
              if (_search.boolDescription != null)
                _BooleanSearchBanner(
                  description: _search.boolDescription!,
                  onEdit: _openBooleanSearch,
                  onClear: _search.clearBooleanSearch,
                ),
              Expanded(child: _buildResults()),
              if (!_search.isSearching &&
                  _search.hasActiveSearch &&
                  (_search.titleGroups.isNotEmpty ||
                      _search.lineGroups.isNotEmpty))
                _ResultsPager(
                  page: window.page,
                  totalPages: window.totalPages,
                  onPrev: window.page > 0
                      ? () => _goToPage(window.page - 1)
                      : null,
                  onNext: window.page < window.totalPages - 1
                      ? () => _goToPage(window.page + 1)
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResults() {
    if (!_search.hasActiveSearch) {
      return const _EmptyHint(
        icon: Icons.search,
        message: 'اكتب كلمة للبحث في الأبيات.\n'
            'التشكيل اختياري: بدون تشكيل يُطابق كل الحركات، '
            'ومع التشكيل يلتزم به.',
      );
    }
    if (_search.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    final titleGroups = _search.titleGroups;
    final lineGroups = _search.lineGroups;
    if (titleGroups.isEmpty && lineGroups.isEmpty) {
      return const _EmptyHint(
        icon: Icons.search_off,
        message: 'لا توجد نتائج.',
      );
    }

    // Only the current page's slice of each section is rendered; section
    // headers keep showing the full totals. Flattened item model so the list
    // builds lazily: [titles header, title tiles…], then [lines header, line
    // tiles…], with the first tile on the page taking keyboard focus.
    final window = _search.pageWindow;
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
            return SectionHeader('عناوين (${titleGroups.length})');
          }
          final i = index - 1;
          final group = titleGroups[window.titleStart + i];
          return _TitleResultTile(
            match: group.shown,
            duplicates: group.duplicates,
            focusNode: i == 0 ? _firstResultFocusNode : null,
            onOpen: _openPoem,
          );
        }
        if (index == lineHeaderIndex) {
          return SectionHeader('أبيات (${lineGroups.length})');
        }
        final i = index - lineHeaderIndex - 1;
        final group = lineGroups[window.lineStart + i];
        return _LineResultTile(
          match: group.shown,
          duplicates: group.duplicates,
          focusNode: (!hasTitles && i == 0) ? _firstResultFocusNode : null,
          onOpen: _openPoem,
        );
      },
    );
  }
}

class _LineResultTile extends StatelessWidget {
  const _LineResultTile({
    required this.match,
    required this.onOpen,
    this.duplicates = const [],
    this.focusNode,
  });

  final LineResult match;

  /// Opens the poem this tile (or, from the duplicates dialog, one of its
  /// duplicates) refers to.
  final void Function(int poemId, {int? lineId}) onOpen;

  /// Other confirmed matches with the same verse text, hidden behind a
  /// [CountBadge] that opens [_showLineDuplicatesDialog].
  final List<LineResult> duplicates;
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
        onTap: () => onOpen(match.poemId, lineId: match.lineId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: AppFonts.currentResultsFamily,
                builder: (context, family, _) => ValueListenableBuilder<double>(
                  valueListenable: AppFonts.currentResultsFontSize,
                  builder: (context, fontSize, _) => HighlightedText(
                    text: match.original,
                    spans: match.spans,
                    style: theme.textTheme.titleLarge?.copyWith(
                      height: 1.8,
                      fontFamily: family,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SourceBadge(source: match.source),
                  if (duplicates.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    CountBadge(
                      count: duplicates.length,
                      tooltip: 'نتائج أخرى لهذا البيت',
                      onTap: () => _showLineDuplicatesDialog(
                        context,
                        [match, ...duplicates],
                        onOpen,
                      ),
                    ),
                  ],
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
    required this.onOpen,
    this.duplicates = const [],
    this.focusNode,
  });

  final TitleResult match;

  /// Opens the poem this tile (or, from the duplicates dialog, one of its
  /// duplicates) refers to.
  final void Function(int poemId, {int? lineId}) onOpen;

  /// Other confirmed matches with the same title text, hidden behind a
  /// [CountBadge] that opens [_showTitleDuplicatesDialog].
  final List<TitleResult> duplicates;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        focusNode: focusNode,
        onTap: () => onOpen(match.poemId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: AppFonts.currentResultsFamily,
                builder: (context, family, _) => ValueListenableBuilder<double>(
                  valueListenable: AppFonts.currentResultsFontSize,
                  builder: (context, fontSize, _) => HighlightedText(
                    text: match.title,
                    spans: match.spans,
                    style: theme.textTheme.titleLarge?.copyWith(
                      height: 1.8,
                      fontFamily: family,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SourceBadge(source: match.source),
                  if (duplicates.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    CountBadge(
                      count: duplicates.length,
                      tooltip: 'نتائج أخرى لهذا العنوان',
                      onTap: () => _showTitleDuplicatesDialog(
                        context,
                        [match, ...duplicates],
                        onOpen,
                      ),
                    ),
                  ],
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

/// Shows every confirmed title match collapsed into one tile — the shown one
/// plus its hidden duplicates — as full result tiles (same look as the main
/// list), so picking one still opens its poem.
void _showTitleDuplicatesDialog(
  BuildContext context,
  List<TitleResult> results,
  void Function(int poemId, {int? lineId}) onOpen,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('نتائج أخرى لهذا العنوان'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TitleResultTile(
                    match: r,
                    onOpen: (poemId, {lineId}) {
                      Navigator.of(dialogContext).pop();
                      onOpen(poemId);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}

/// [_showTitleDuplicatesDialog]'s counterpart for verse-line results.
void _showLineDuplicatesDialog(
  BuildContext context,
  List<LineResult> results,
  void Function(int poemId, {int? lineId}) onOpen,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('نتائج أخرى لهذا البيت'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LineResultTile(
                    match: r,
                    onOpen: (poemId, {lineId}) {
                      Navigator.of(dialogContext).pop();
                      onOpen(poemId, lineId: lineId);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
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
