import '../models/source.dart';
import '../search/boolean_query.dart';
import 'poem_repository.dart';

/// The narrow search surface `PoemSearchController` needs from the repository.
///
/// Exists so search orchestration can be unit-tested against a fake with no
/// SQLite behind it; [PoemRepository] is the production implementation.
abstract interface class PoemSearchApi {
  Future<List<LineResult>> searchLines(
    String query, {
    String? poet,
    List<Source>? sourceOrder,
  });

  Future<List<TitleResult>> searchTitles(
    String query, {
    String? poet,
    List<Source>? sourceOrder,
  });

  Future<List<LineResult>> searchLinesBoolean(
    BoolExpr expr, {
    String? poet,
    List<Source>? sourceOrder,
  });

  Future<List<TitleResult>> searchTitlesBoolean(
    BoolExpr expr, {
    String? poet,
    List<Source>? sourceOrder,
  });
}
