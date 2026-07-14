import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/search_controller.dart';
import '../db/poem_repository.dart';
import '../models/poem.dart';
import '../search/search_sort.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/global_control_shortcuts.dart';
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

  /// All search state and orchestration, scoped to this poet; titles are
  /// always searched here (no titles-toggle pref, unlike the home page).
  late final PoemSearchController _search = PoemSearchController(
    api: widget.repo,
    poet: widget.poet,
    useTitlesPref: false,
  );

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  /// Ctrl+F works regardless of what (if anything) currently has keyboard
  /// focus — see [GlobalControlShortcuts].
  late final GlobalControlShortcuts _shortcuts = GlobalControlShortcuts(
    bindings: {
      LogicalKeyboardKey.keyF: () => _searchFocusNode.requestFocus(),
    },
    isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
  );

  @override
  void initState() {
    super.initState();
    _shortcuts.attach();
    _poemsFuture = widget.repo.poemsByPoet(widget.poet);
    _search.loadPrefs();
  }

  /// Opens the consolidated Settings page; on return, reloads the source
  /// order/sort mode (may have changed there) and re-runs the active search.
  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    await _search.reloadPrefsAndRerun();
  }

  @override
  void dispose() {
    _shortcuts.dispose();
    _search.dispose();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  void _focusFirstResult() {
    if (_search.sortedTitles.isNotEmpty || _search.sortedLines.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
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
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(widget.poet),
          actions: [
            PopupMenuButton<SearchSort>(
              icon: const Icon(Icons.sort),
              tooltip: 'ترتيب النتائج',
              initialValue: _search.sortMode,
              onSelected: _search.setSortMode,
              itemBuilder: (_) => [
                for (final sort in SearchSort.values)
                  CheckedPopupMenuItem(
                    value: sort,
                    checked: sort == _search.sortMode,
                    child: Text(sort.label),
                  ),
              ],
            ),
            CommonAppBarActions(onOpenSettings: _openSettings),
          ],
        ),
        body: FutureBuilder<List<Poem>>(
          future: _poemsFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final poems = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SearchField(
                    autofocus: false,
                    hintText: 'ابحث في قصائد ${widget.poet}…',
                    focusNode: _searchFocusNode,
                    debounce: const Duration(seconds: 1),
                    onChanged: _search.onQueryChanged,
                    onSubmitted: _focusFirstResult,
                  ),
                ),
                Expanded(
                  child: _search.query.isEmpty
                      ? _buildPoemList(poems)
                      : _search.isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : _buildMatchList(),
                ),
              ],
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
    final titleMatches = _search.sortedTitles;
    final matches = _search.sortedLines;
    if (titleMatches.isEmpty && matches.isEmpty) {
      return const Center(child: Text('لا توجد نتائج.'));
    }

    // Flattened item model so the results list builds lazily:
    // [titles header, title tiles…], then [lines header, line tiles…].
    final hasTitles = titleMatches.isNotEmpty;
    final titleBlock = hasTitles ? 1 + titleMatches.length : 0;
    final lineHeaderIndex = titleBlock;
    final itemCount = lineHeaderIndex + 1 + matches.length;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasTitles && index < titleBlock) {
          if (index == 0) {
            return SectionHeader('عناوين (${titleMatches.length})');
          }
          final i = index - 1;
          final match = titleMatches[i];
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
          return SectionHeader('أبيات (${matches.length})');
        }
        final i = index - lineHeaderIndex - 1;
        final match = matches[i];
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
