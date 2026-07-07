/// How much memory the database connection is tuned to use for reads (see
/// `_tuneForReads` in `poem_repository.dart`), as a user-chosen trade-off
/// between search speed and RAM footprint on constrained machines.
enum MemoryPreset {
  low('low', 'منخفض', 536870912, -32768),
  balanced('balanced', 'متوازن', 2147483648, -131072),
  high('high', 'عالٍ', 4294967296, -262144);

  const MemoryPreset(this.id, this.label, this.mmapSize, this.cacheSizeKb);

  /// Stable identifier used for persistence (see `MemoryPresetPrefs`).
  final String id;

  /// Arabic label shown in the settings page.
  final String label;

  /// Bytes for `PRAGMA mmap_size`.
  final int mmapSize;

  /// Negative KB for `PRAGMA cache_size` (SQLite's convention: negative means
  /// kibibytes rather than pages).
  final int cacheSizeKb;

  /// The preset with the given [id], or [high] (today's default) for an
  /// unknown/absent id.
  static MemoryPreset byId(String? id) =>
      values.firstWhere((p) => p.id == id, orElse: () => high);
}
