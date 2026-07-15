import 'dart:io';

import 'android_database_bootstrap.dart';
import 'database_bootstrap.dart';
import 'windows_database_bootstrap.dart';

/// The single composition point for platform database bootstrapping. Adding a
/// platform means one new implementation file plus one branch here — nothing
/// else changes.
DatabaseBootstrap createDatabaseBootstrap() {
  if (Platform.isWindows) return WindowsDatabaseBootstrap();
  if (Platform.isAndroid) return AndroidDatabaseBootstrap();
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
