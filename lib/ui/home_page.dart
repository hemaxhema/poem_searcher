import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/poem_repository.dart';
import '../widgets/help_dialog.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/search_field.dart';
import 'poem_detail_page.dart';
import 'poet_poems_page.dart';
import 'poets_page.dart';

/// Main screen: a search bar with live tashkeel-aware results underneath.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repo});

  final PoemRepository repo;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';
  List<LineResult> _lineMatches = const [];
  List<String> _poetMatches = const [];

  /// Debounces keystrokes so each pause fires at most one (async) DB search.
  Timer? _debounce;

  /// Monotonic token so a slow search that resolves after a newer one has
  /// started is discarded instead of overwriting fresher results.
  int _searchToken = 0;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  void _focusFirstResult() {
    if (_poetMatches.isNotEmpty || _lineMatches.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    _query = trimmed;
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      setState(() {
        _lineMatches = const [];
        _poetMatches = const [];
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final poets = widget.repo.searchPoets(query);
    final lines = await widget.repo.searchLines(query);
    // Drop stale results (a newer query started, or the box changed/emptied).
    if (!mounted || token != _searchToken || query != _query) return;
    setState(() {
      _poetMatches = poets;
      _lineMatches = lines;
    });
  }

  void _openPoem(LineResult match) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PoemDetailPage(
        repo: widget.repo,
        poemId: match.poemId,
        highlightLineId: match.lineId,
      ),
    ));
  }

  void _openPoet(String poet) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PoetPoemsPage(repo: widget.repo, poet: poet),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث في الشعر'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'الشعراء',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PoetsPage(repo: widget.repo),
            )),
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
              padding: const EdgeInsets.all(16),
              child: SearchField(
                focusNode: _searchFocusNode,
                onChanged: _onQueryChanged,
                onSubmitted: _focusFirstResult,
              ),
            ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_query.isEmpty) {
      return const _EmptyHint(
        icon: Icons.search,
        message: 'اكتب كلمة للبحث في الأبيات.\n'
            'التشكيل اختياري: بدون تشكيل يُطابق كل الحركات، '
            'ومع التشكيل يلتزم به.',
      );
    }
    if (_lineMatches.isEmpty && _poetMatches.isEmpty) {
      return const _EmptyHint(
        icon: Icons.search_off,
        message: 'لا توجد نتائج.',
      );
    }

    // Flattened item model so the (potentially long) results list builds
    // lazily: [poets header, poet tiles…], then [lines header, line tiles…].
    final hasPoets = _poetMatches.isNotEmpty;
    final poetBlock = hasPoets ? 1 + _poetMatches.length : 0;
    final lineHeaderIndex = poetBlock; // "أبيات" header sits right after poets
    final itemCount = lineHeaderIndex + 1 + _lineMatches.length;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasPoets && index < poetBlock) {
          if (index == 0) {
            return _SectionHeader('شعراء (${_poetMatches.length})');
          }
          final i = index - 1;
          final poet = _poetMatches[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(poet),
              trailing: const Icon(Icons.chevron_left),
              focusNode: i == 0 ? _firstResultFocusNode : null,
              onTap: () => _openPoet(poet),
            ),
          );
        }
        if (index == lineHeaderIndex) {
          return _SectionHeader('أبيات (${_lineMatches.length})');
        }
        final i = index - lineHeaderIndex - 1;
        final match = _lineMatches[i];
        return _LineResultTile(
          match: match,
          focusNode: (!hasPoets && i == 0) ? _firstResultFocusNode : null,
          onTap: () => _openPoem(match),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HighlightedText(
                text: match.original,
                start: match.start,
                end: match.end,
                style: theme.textTheme.titleMedium?.copyWith(height: 1.8),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
