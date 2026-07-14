import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'database_bootstrap.dart';

/// Windows implementation: FFI SQLite, with the writable database stored next
/// to the executable (inside the install directory) rather than in per-user
/// app-data, so uninstalling the program — which removes its install directory
/// — takes the writable database with it. This requires the install directory
/// (or at least the `db` subfolder) to be writable by the user running the
/// app; a system-wide install under Program Files must grant that explicitly
/// (e.g. an Inno Setup `Permissions: users-modify` on this subfolder), since
/// standard users can't otherwise write there.
class WindowsDatabaseBootstrap implements DatabaseBootstrap {
  @override
  DatabaseFactory get databaseFactory {
    sqfliteFfiInit(); // Idempotent; keeps the init-at-open behavior.
    return databaseFactoryFfi;
  }

  @override
  Future<String> resolveDatabasePath() async {
    final installDir = p.dirname(Platform.resolvedExecutable);
    return p.join(installDir, 'db', 'DB_Poems.db');
  }

  /// Copies the bundled (lean) asset DB to [targetPath]. Prefers a streaming
  /// file copy of the on-disk asset — Flutter unpacks declared assets to real
  /// files under the executable's `data/flutter_assets/`, so this never holds
  /// the whole database in memory. Falls back to loading it through the asset
  /// bundle only for unusual packaging where that file can't be located.
  @override
  Future<void> copyBundledDatabaseTo(String targetPath) async {
    await Directory(p.dirname(targetPath)).create(recursive: true);
    final assetOnDisk = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      poemDbAssetPath,
    );
    if (await File(assetOnDisk).exists()) {
      await File(assetOnDisk).copy(targetPath);
      return;
    }
    final bytes = await rootBundle.load(poemDbAssetPath);
    await File(targetPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }
}
