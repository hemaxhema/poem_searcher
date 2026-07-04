import 'package:flutter/material.dart';

import '../db/poem_repository.dart';
import 'poet_poems_page.dart';

/// Lists the distinct poets; tapping one opens their poems.
class PoetsPage extends StatelessWidget {
  const PoetsPage({super.key, required this.repo});

  final PoemRepository repo;

  @override
  Widget build(BuildContext context) {
    final poets = repo.poets;
    return Scaffold(
      appBar: AppBar(title: const Text('الشعراء')),
      body: ListView.separated(
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
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PoetPoemsPage(repo: repo, poet: poet),
              )),
            ),
          );
        },
      ),
    );
  }
}
