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
  });

  final int id;
  final String poet;
  final String title;
  final String? book;
  final String? page;
  final String? type;
  final String? sourceUrl;

  /// Which of the 3 data sources this poem was drawn from, derived from
  /// [sourceUrl]; `null` if absent or unrecognized.
  Source? get source => Source.fromUrl(sourceUrl);

  factory Poem.fromRow(Map<String, Object?> row) => Poem(
        id: row['id'] as int,
        poet: (row['poet'] as String?) ?? '',
        title: (row['title'] as String?) ?? '',
        book: row['book'] as String?,
        page: row['page'] as String?,
        type: row['type'] as String?,
        sourceUrl: row['source_url'] as String?,
      );
}
