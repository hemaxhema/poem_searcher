import 'dart:io';

import '../platform/database_bootstrap.dart';
import 'search_index.dart';

/// Bump this whenever a new database asset ships so the previously copied
/// writable file is refreshed on next launch (see [prepareDatabase]).
const String dbAssetVersion = '10';

/// Ensures a fully-indexed, writable copy of the database exists and returns
/// its path. The version marker is written only *after* a successful index
/// build, so an interrupted first run re-copies and rebuilds on the next
/// launch instead of leaving a half-built database in use.
///
/// This orchestration is shared by every platform; [bootstrap] supplies the
/// platform-specific pieces (where the copy lives, how the asset's bytes
/// arrive, and which SQLite factory to open with).
Future<String> prepareDatabase(
  DatabaseBootstrap bootstrap, {
  IndexProgress? onProgress,
}) async {
  final target = await bootstrap.resolveDatabasePath();
  final marker = File('$target.version');

  final ready = await File(target).exists() &&
      await marker.exists() &&
      (await marker.readAsString()).trim() == dbAssetVersion;
  if (ready) return target;

  await bootstrap.copyBundledDatabaseTo(target);

  // Build the search index in the writable copy (opened read-write).
  final db = await bootstrap.databaseFactory.openDatabase(target);
  try {
    await buildSearchIndex(db, onProgress: onProgress);
  } finally {
    await db.close();
  }
  await marker.writeAsString(dbAssetVersion, flush: true);
  return target;
}
