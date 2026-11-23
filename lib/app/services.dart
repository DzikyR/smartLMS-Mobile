import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import '../core/storage/local_db.dart';
import '../core/storage/secure_store.dart';
import '../core/time/server_clock.dart';
import '../features/auth/auth_repository.dart';
import '../features/exam/exam_repository.dart';
import '../features/lms/lms_repository.dart';

/// Semua layanan aplikasi, dibuat sekali saat start (main.dart) lalu disuntikkan ke Riverpod.
class AppServices {
  AppServices({
    required this.store,
    required this.db,
    required this.api,
    required this.clock,
    required this.auth,
    required this.exams,
    required this.lms,
    required this.appVersion,
  });

  final SecureStore store;
  final LocalDb db;
  final ApiClient api;
  final ServerClock clock;
  final AuthRepository auth;
  final ExamRepository exams;
  final LmsRepository lms;
  final String appVersion;

  /// Callback diisi setelah state Riverpod siap (sesi berakhir → layar login, 426 → layar update).
  static void Function()? sessionExpired;
  static void Function(Map<String, dynamic> info)? upgradeRequired;

  static Future<AppServices> create() async {
    final store = SecureStore(SecureKeyValueStore());
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final db = LocalDb.open('${support.path}${Platform.pathSeparator}smartlms.db', await store.databaseKey());
    final info = await PackageInfo.fromPlatform();
    final api = ApiClient(
      baseUrl: AppConfig.apiRoot,
      store: store,
      platform: Platform.isIOS ? 'ios' : 'android',
      appVersion: info.version,
      onSessionExpired: () => sessionExpired?.call(),
      onUpgradeRequired: (i) => upgradeRequired?.call(i),
    );
    final clock = ServerClock(PlatformMonotonic());
    return AppServices(
      store: store,
      db: db,
      api: api,
      clock: clock,
      auth: AuthRepository(api, store, db),
      exams: ExamRepository(api, db, clock),
      lms: LmsRepository(api, db, cache),
      appVersion: info.version,
    );
  }
}
