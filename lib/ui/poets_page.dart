import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/poem_repository.dart';
import '../search/search_sort.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/global_control_shortcuts.dart';
import '../widgets/search_field.dart';
import 'poet_poems_page.dart';

/// Lists the distinct poets; tapping one opens their poems.
class PoetsPage extends StatefulWidget {
  const PoetsPage({super.key, required this.repo});

  final PoemRepository repo;

  @override
  State<PoetsPage> createState() => _PoetsPageState();
}

class _PoetsPageState extends State<PoetsPage> {
  String _query = '';
  final FocusNode _searchFocusNode = FocusNode();

  /// Ctrl+F works regardless of what (if anything) currently has keyboard
  /// focus — see [GlobalControlShortcuts].
  late final GlobalControlShortcuts _shortcuts = GlobalControlShortcuts(
    bindings: {
      LogicalKeyboardKey.keyF: () => _searchFocusNode.requestFocus(),
    },
    isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
  );

  List<String> get _poets {
    final base = _query.isEmpty
        ? widget.repo.poets
        : widget.repo.searchPoets(_query);
    return sortPoetsByCount(base, widget.repo.poemCountFor);
  }

  @override
  void initState() {
    super.initState();
    _shortcuts.attach();
  }

  @override
  void dispose() {
    _shortcuts.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() => _query = query.trim());
  }

  @override
  Widget build(BuildContext context) {
    final poets = _poets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الشعراء'),
        actions: const [CommonAppBarActions()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              hintText: 'ابحث عن شاعر…',
              autofocus: false,
              focusNode: _searchFocusNode,
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(
            child: poets.isEmpty
                ? const Center(child: Text('لا توجد نتائج.'))
                : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: poets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final poet = poets[i];
                    final count = widget.repo.poemCountFor(poet);
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(poet),
                        subtitle: Text('$count قصيدة'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PoetPoemsPage(repo: widget.repo, poet: poet),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
