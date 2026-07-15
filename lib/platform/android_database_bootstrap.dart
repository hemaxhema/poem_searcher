import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'database_bootstrap.dart';

/// Android implementation, with the writable database under the app-private
/// support directory (no storage permission needed). The bundled asset is
/// ~835 MB, so it is streamed to disk by native code (a whole-file
/// `rootBundle.load` would hold it all in memory and OOM the app) — see the
/// `poem_searcher/asset_copy` channel in `MainActivity.kt`.
///
/// Uses the FFI factory over the modern SQLite bundled by `sqlite3_flutter_libs`
/// (the same one Windows uses), NOT the `sqflite` plugin — the plugin runs on
/// Android's *system* SQLite, which lacks the FTS5 module and the trigram
/// tokenizer that `buildSearchIndex` needs.
class AndroidDatabaseBootstrap implements DatabaseBootstrap {
  static const MethodChannel _channel =
      MethodChannel('poem_searcher/asset_copy');

  @override
  DatabaseFactory get databaseFactory {
    sqfliteFfiInit(); // Idempotent.
    return databaseFactoryFfi;
  }

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
