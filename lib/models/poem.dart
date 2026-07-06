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

  /// The stored `poem.source_name` label (see [Source.displayName]).
  final String? sourceName;

  /// Which data source this poem was drawn from, derived from the stored
  /// [sourceName]; `null` if absent or unrecognized.
  Source? get source => Source.fromName(sourceName);

  factory Poem.fromRow(Map<String, Object?> row) => Poem(
        id: row['id'] as int,
        poet: (row['poet'] as String?) ?? '',
        title: (row['title'] as String?) ?? '',
        book: row['book'] as String?,
        page: row['page'] as String?,
        type: row['type'] as String?,
        sourceUrl: row['source_url'] as String?,
        sourceName: row['source_name'] as String?,
      );
}
