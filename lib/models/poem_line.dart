/// A single line (bayt) from the `lines` table.
class PoemLine {
  const PoemLine({
    required this.id,
    required this.poemId,
    required this.line,
    required this.lineNumber,
    this.lineType,
  });

  final int id;
  final int poemId;

  /// Full bayt text; its two hemistichs are separated by `=`.
  final String line;
  final int lineNumber;
  final String? lineType;

  /// The first (right-hand) hemistich, or the whole line if there is no `=`.
  String get sadr => _split().$1;

  /// The second (left-hand) hemistich, or empty if there is no `=`.
  String get ajz => _split().$2;

  /// True when the line actually splits into two hemistichs.
  bool get hasTwoHemistichs => line.contains('=');

  (String, String) _split() {
    final idx = line.indexOf('=');
    if (idx < 0) return (line.trim(), '');
    return (line.substring(0, idx).trim(), line.substring(idx + 1).trim());
  }

  factory PoemLine.fromRow(Map<String, Object?> row) => PoemLine(
        id: row['id'] as int,
        poemId: row['poem_id'] as int,
        line: (row['line'] as String?) ?? '',
        lineNumber: (row['line_number'] as int?) ?? 0,
        lineType: row['line_type'] as String?,
      );
}

/// Groups consecutive rows sharing the same [PoemLine.lineNumber] (rows are
/// already ordered by `line_number, id`), so alternate readings (riwayat)
/// of the same bayt end up in one group instead of separate tiles.
List<List<PoemLine>> groupByLineNumber(List<PoemLine> lines) {
  final groups = <List<PoemLine>>[];
  for (final line in lines) {
    if (groups.isNotEmpty && groups.last.first.lineNumber == line.lineNumber) {
      groups.last.add(line);
    } else {
      groups.add([line]);
    }
  }
  return groups;
}
