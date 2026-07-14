import 'package:flutter/foundation.dart';

import '../db/poem_repository.dart';
import '../search/search_sort.dart';

/// Holds the poets page's query state and derives its display list: all
/// poets (or the name-search matches), ordered by poem count then name.
class PoetsController extends ChangeNotifier {
  PoetsController({required this.repo});

  final PoemRepository repo;

  String _query = '';

  /// The trimmed poet-name query ('' shows every poet).
  String get query => _query;

  void setQuery(String raw) {
    _query = raw.trim();
    notifyListeners();
  }

  /// Poets to list for the current [query], sorted by poem count (desc) then
  /// name (see [sortPoetsByCount]).
  List<String> get poets {
    final base = _query.isEmpty ? repo.poets : repo.searchPoets(_query);
    return sortPoetsByCount(base, repo.poemCountFor);
  }
}
