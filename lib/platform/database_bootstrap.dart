import 'package:sqflite_common/sqlite_api.dart';

/// Path of the database bundled as a Flutter asset (shared by all platforms).
const String poemDbAssetPath = 'assets/database/DB_Poems.db';

/// The platform-specific pieces of getting the poem database onto local disk
/// and opened. Everything else — the version-marker crash-safety rule, the
/// first-run index build, PRAGMA tuning, and all queries — is shared code
/// (see `db/database_preparer.dart` and [PoemRepository]); only *where* the
/// writable copy lives and *how the asset's bytes arrive* differ per platform.
///
/// New platforms add an implementation here and one branch in
/// `bootstrap_selector.dart`, touching nothing else.
abstract interface class DatabaseBootstrap {
  /// The sqflite-compatible factory every database open on this platform goes
  /// through. Windows: `sqflite_common_ffi`'s [databaseFactoryFfi]. Android
  /// (later): `package:sqflite`'s factory.
  DatabaseFactory get databaseFactory;

  /// Absolute path where the writable, indexed copy of the database lives.
  /// Windows: `<dir of Platform.resolvedExecutable>/db/DB_Poems.db`. Android
  /// (later): under the app-support directory via `path_provider`.
  Future<String> resolveDatabasePath();

  /// Materializes the bundled lean database asset at [targetPath] (parent
  /// directories may not exist yet — create them).
  ///
  /// Contract: the asset is ~835 MB, so implementations must not require
  /// holding the whole file in memory as their primary path — copy on-disk
  /// files or stream in chunks. (The Windows implementation file-copies the
  /// unpacked asset from `data/flutter_assets/`; its whole-file `rootBundle`
  /// fallback is tolerable only because the fast path always exists and
  /// desktop RAM absorbs the rare miss.)
  Future<void> copyBundledDatabaseTo(String targetPath);
}
