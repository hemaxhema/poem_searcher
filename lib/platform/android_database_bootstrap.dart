import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import 'database_bootstrap.dart';

/// Android implementation: the `sqflite` plugin factory, with the writable
/// database under the app-private support directory (no storage permission
/// needed). The bundled asset is ~835 MB, so it is streamed to disk by native
/// code (a whole-file `rootBundle.load` would hold it all in memory and OOM
/// the app) — see the `poem_searcher/asset_copy` channel in `MainActivity.kt`.
class AndroidDatabaseBootstrap implements DatabaseBootstrap {
  static const MethodChannel _channel =
      MethodChannel('poem_searcher/asset_copy');

  @override
  DatabaseFactory get databaseFactory => sqflite.databaseFactory;

  @override
  Future<String> resolveDatabasePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'db', 'DB_Poems.db');
  }

  @override
  Future<void> copyBundledDatabaseTo(String targetPath) async {
    await Directory(p.dirname(targetPath)).create(recursive: true);
    await _channel.invokeMethod<void>('copyAsset', <String, String>{
      'assetKey': poemDbAssetPath,
      'targetPath': targetPath,
    });
  }
}
