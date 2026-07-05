import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/poem_repository.dart';
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

  List<String> get _poets =>
      _query.isEmpty ? widget.repo.poets : widget.repo.searchPoets(_query);

  @override
  void dispose() {
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
      appBar: AppBar(title: const Text('الشعراء')),
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
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(poet),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PoetPoemsPage(
                                    repo: widget.repo, poet: poet),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
