import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/poem_repository.dart';
import '../models/poem.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/search_field.dart';
import 'poem_detail_page.dart';

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
  List<LineResult> _matches = const [];
  Timer? _debounce;
  int _searchToken = 0;
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _poemsFuture = widget.repo.poemsByPoet(widget.poet);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  void _focusFirstResult() {
    if (_matches.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    _query = trimmed;
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      setState(() => _matches = const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final matches = await widget.repo.searchLines(query, poet: widget.poet);
    if (!mounted || token != _searchToken || query != _query) return;
    setState(() => _matches = matches);
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
      appBar: AppBar(title: Text(widget.poet)),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            _searchFocusNode.requestFocus();
          },
        },
        child: FutureBuilder<List<Poem>>(
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
                    onChanged: _onQueryChanged,
                    onSubmitted: _focusFirstResult,
                  ),
                ),
                Expanded(
                  child: _query.isEmpty
                      ? _buildPoemList(poems)
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
    if (_matches.isEmpty) {
      return const Center(child: Text('لا توجد نتائج.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _matches.length,
      itemBuilder: (context, i) {
        final match = _matches[i];
        return Card(
          child: InkWell(
            focusNode: i == 0 ? _firstResultFocusNode : null,
            onTap: () => _openPoem(poemId: match.poemId, lineId: match.lineId),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HighlightedText(
                    text: match.original,
                    start: match.start,
                    end: match.end,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(height: 1.8),
                  ),
                  if (match.title.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      match.title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
