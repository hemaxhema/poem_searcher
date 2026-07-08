import 'source.dart';

/// A poem record from the `poem` table.
class Poem {
  const Poem({
    required this.id,
    required this.poet,
    required this.title,
    this.book,
    this.page,
    this.type,
    this.sourceUrl,
    this.sourceName,
  });

  final int id;
  final String poet;
  final String title;
  final String? book;
  final String? page;
  final String? type;
  final String? sourceUrl;

  /// The [Source.displayName] derived from the stored `poem.source_id`.
  final String? sourceName;

  /// Which data source this poem was drawn from, derived from the stored
  /// [sourceName]; `null` if absent or unrecognized.
  Source? get source => Source.fromName(sourceName);

  /// Builds a [Poem] from a query row. Expects `book`/`type` to already be
  /// resolved to display names (via a `LEFT JOIN` on the `book`/`type`
  /// lookup tables) and `source_id` to be present so the stored `source_url`
  /// suffix can be expanded back to a full URL via [Source.urlPrefix].
  factory Poem.fromRow(Map<String, Object?> row) {
    final sourceId = row['source_id'] as int?;
    final source = (sourceId != null && sourceId >= 0 && sourceId < Source.values.length)
        ? Source.values[sourceId]
        : null;
    final urlSuffix = row['source_url'] as String?;
    final expandedUrl =
        (source?.urlPrefix != null && urlSuffix != null)
            ? '${source!.urlPrefix}$urlSuffix'
            : urlSuffix;
    return Poem(
      id: row['id'] as int,
      poet: (row['poet'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      book: row['book'] as String?,
      page: row['page'] as String?,
      type: row['type'] as String?,
      sourceUrl: expandedUrl,
      sourceName: source?.displayName,
    );
  }
}
