import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/poem_repository.dart';
import '../models/poem.dart';
import '../models/source.dart';
import '../search/search_sort.dart';
import '../services/search_sort_prefs.dart';
import '../services/source_filter_prefs.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/search_field.dart';
import '../widgets/section_header.dart';
import '../widgets/source_badge.dart';
import 'poem_detail_page.dart';
import 'settings_page.dart';

/// Shows one poet's poems, with a search field scoped to that poet's verses.
class PoetPoemsPage extends StatefulWidget {
  const PoetPoemsPage({super.key, required this.repo, required this.poet});

  final PoemRepository repo;
  final String poet;

  @override
  State<PoetPoemsPage> createState() => _PoetPoemsPageState();
}

class _PoetPoemsPageState extends State<PoetPoemsPage> {
  late Future<List<Poem>> _poemsFuture;
  String _query = '';

  /// Repository output, in relevance order. Display lists are derived from these
  /// by [_applySort].
  List<TitleResult> _rawTitleMatches = const [];
  List<LineResult> _rawMatches = const [];

  /// Display lists (sorted per [_sortMode]) that the result views read.
  List<TitleResult> _titleMatches = const [];
  List<LineResult> _matches = const [];

  /// How results are ordered. Loaded from persisted prefs (shared with home).
  SearchSort _sortMode = SearchSort.lineCountDesc;

  /// True while a search is in flight, so the results area can show a
  /// loading spinner instead of stale results during the DB query.
  bool _isSearching = false;

  int _searchToken = 0;

  /// Selected sources, in search priority order. Read from persisted prefs
  /// (the source of truth, set via the home page's filter dialog).
  List<Source> _sourceOrder = Source.values;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _poemsFuture = widget.repo.poemsByPoet(widget.poet);
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
    _matches = sortLineResults(_rawMatches, _sortMode, _sourceOrder);
  }

  /// Switches the result sort mode, reordering already-fetched results in memory
  /// (no query, no [_searchToken] change) and persisting the choice.
  Future<void> _setSortMode(SearchSort mode) async {
    if (mode == _sortMode) return;
    setState(() {
      _sortMode = mode;
      _applySort();
    });
    await SearchSortPrefs.save(mode);
  }

  /// Opens the consolidated Settings page; on return, reloads the source
  /// order/sort mode (may have changed there) and re-runs the active search.
  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    final order = await SourceFilterPrefs.load();
    final sort = await SearchSortPrefs.load();
    setState(() {
      _sourceOrder = order;
      _sortMode = sort;
      _applySort();
    });
    if (_query.isNotEmpty) _runSearch(_query);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  void _focusFirstResult() {
    if (_titleMatches.isNotEmpty || _matches.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
  }

  // SearchField already debounces keystrokes (see its `debounce` parameter
  // below), so this only needs to dispatch the (already-settled) query.
  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    _query = trimmed;
    if (trimmed.isEmpty) {
      setState(() {
        _titleMatches = const [];
        _matches = const [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _runSearch(trimmed);
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final results = await Future.wait([
      widget.repo
          .searchTitles(query, poet: widget.poet, sourceOrder: _sourceOrder),
      widget.repo
          .searchLines(query, poet: widget.poet, sourceOrder: _sourceOrder),
    ]);
    if (!mounted || token != _searchToken || query != _query) return;
    setState(() {
      _rawTitleMatches = results[0] as List<TitleResult>;
      _rawMatches = results[1] as List<LineResult>;
      _applySort();
      _isSearching = false;
    });
  }

  void _openPoem({required int poemId, int? lineId}) {
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
        title: Text(widget.poet),
        actions: [
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
          CommonAppBarActions(onOpenSettings: _openSettings),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            _searchFocusNode.requestFocus();
          },
        },
        // CallbackShortcuts only fires while focus is within its subtree, so
        // wrap the content in an autofocus node that acts as a fallback focus
        // holder whenever nothing else (search field, a list item) has focus.
        child: FutureBuilder<List<Poem>>(
          future: _poemsFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final poems = snapshot.data!;
            return Focus(
              autofocus: true,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SearchField(
                      autofocus: false,
                      hintText: 'ابحث في قصائد ${widget.poet}…',
                      focusNode: _searchFocusNode,
                      debounce: const Duration(seconds: 1),
                      onChanged: _onQueryChanged,
                      onSubmitted: _focusFirstResult,
                    ),
                  ),
                  Expanded(
                    child: _query.isEmpty
                        ? _buildPoemList(poems)
                        : _isSearching
                            ? const Center(child: CircularProgressIndicator())
                            : _buildMatchList(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPoemList(List<Poem> poems) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: poems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        final poem = poems[i];
        final subtitle = [
          if ((poem.book ?? '').isNotEmpty) poem.book!,
          if ((poem.page ?? '').isNotEmpty) poem.page!,
        ].join(' — ');
        return Card(
          child: ListTile(
            leading: const Icon(Icons.menu_book),
            title: Text(poem.title),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _openPoem(poemId: poem.id),
          ),
        );
      },
    );
  }

  Widget _buildMatchList() {
    if (_titleMatches.isEmpty && _matches.isEmpty) {
      return const Center(child: Text('لا توجد نتائج.'));
    }

    // Flattened item model so the results list builds lazily:
    // [titles header, title tiles…], then [lines header, line tiles…].
    final hasTitles = _titleMatches.isNotEmpty;
    final titleBlock = hasTitles ? 1 + _titleMatches.length : 0;
    final lineHeaderIndex = titleBlock;
    final itemCount = lineHeaderIndex + 1 + _matches.length;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasTitles && index < titleBlock) {
          if (index == 0) {
            return SectionHeader('عناوين (${_titleMatches.length})');
          }
          final i = index - 1;
          final match = _titleMatches[i];
          return Card(
            child: InkWell(
              focusNode: i == 0 ? _firstResultFocusNode : null,
              onTap: () => _openPoem(poemId: match.poemId),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HighlightedText(
                      text: match.title,
                      spans: match.spans,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(height: 1.8),
                    ),
                    const SizedBox(height: 8),
                    SourceBadge(source: match.source),
                  ],
                ),
              ),
            ),
          );
        }
        if (index == lineHeaderIndex) {
          return SectionHeader('أبيات (${_matches.length})');
        }
        final i = index - lineHeaderIndex - 1;
        final match = _matches[i];
        return Card(
          child: InkWell(
            focusNode: (!hasTitles && i == 0) ? _firstResultFocusNode : null,
            onTap: () => _openPoem(poemId: match.poemId, lineId: match.lineId),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HighlightedText(
                    text: match.original,
                    spans: match.spans,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(height: 1.8),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SourceBadge(source: match.source),
                      if (match.title.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            match.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
