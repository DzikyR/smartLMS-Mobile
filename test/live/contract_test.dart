// Uji kontrak terhadap server SmartTest SUNGGUHAN (repo smartTest, DB hasil seed).
// Dilewati kecuali dijalankan dengan:
//   flutter test test/live --dart-define=LIVE_API=http://localhost:3123 --dart-define=LIVE_USER=2401004 --dart-define=LIVE_PASSWORD=...
// Memakai ujian seed "Kuis 1 — Dasar Algoritma" (kelas IF-1A, kunci perangkat, 10 soal, 1 kesempatan).
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/core/api/api_client.dart';
import 'package:smartlms/core/storage/local_db.dart';
import 'package:smartlms/core/storage/secure_store.dart';
import 'package:smartlms/core/time/server_clock.dart';
import 'package:smartlms/features/auth/auth_repository.dart';
import 'package:smartlms/features/exam/exam_repository.dart';
import 'package:smartlms/features/lms/lms_repository.dart';
import 'dart:io';

import '../server_clock_test.dart' show FakeMono;

const live = String.fromEnvironment('LIVE_API');
const user = String.fromEnvironment('LIVE_USER', defaultValue: '2401004');
const password = String.fromEnvironment('LIVE_PASSWORD');

void main() {
  late SecureStore store;
  late ApiClient api;
  late LocalDb db;
  late ExamRepository exams;
  late AuthRepository auth;
  late LmsRepository lms;

  setUpAll(() {
    store = SecureStore(MemoryKeyValueStore());
    api = ApiClient(baseUrl: '$live/api/v1/mobile', store: store, platform: 'android', appVersion: '1.0.0');
    db = LocalDb.memory();
    final clock = ServerClock(FakeMono());
    exams = ExamRepository(api, db, clock);
    auth = AuthRepository(api, store, db);
    lms = LmsRepository(api, db, Directory.systemTemp.createTempSync('lms'));
  });

  test('alur lengkap: login → paket → mulai → jawab → sinkron → kumpul → nilai', () async {
    final cfg = await api.getJson('/config');
    expect(cfg['now'], isA<int>());

    await expectLater(auth.login(user, 'password-salah'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_CREDENTIALS')));
    final me = await auth.login(user, password);
    expect(me.isStudent, isTrue);

    final list = await exams.list();
    final kuis = list.firstWhere((e) => e['title'] == 'Kuis 1 — Dasar Algoritma');
    expect(kuis['mobile'], 'ok');

    final detail = await exams.detail(kuis['id'] as String);
    final version = (detail['package'] as Map)['version'] as String;
    await exams.prefetchPackage(kuis['id'] as String, version: version);
    expect(db.package(kuis['id'] as String)?.version, version);
    await exams.prefetchPackage(kuis['id'] as String); // versi tak diketahui → If-None-Match → 304
    expect(db.package(kuis['id'] as String)?.version, version);

    final session = await exams.start(kuis['id'] as String);
    expect(session.questions.length, 10);
    expect(session.deadline, greaterThan(DateTime.now().millisecondsSinceEpoch));
    expect(session.maxLeaves, 3);

    // Jawab semua soal (PG pilihan pertama, B/S "true", isian "def", esai teks).
    for (final q in session.questions) {
      final value = switch (q.type) { 'MULTIPLE_CHOICE' => q.options.first.id, 'TRUE_FALSE' => 'true', 'SHORT_ANSWER' => 'def', _ => 'Rekursi memanggil dirinya sendiri.' };
      db.setAnswer(session.attemptId, q.id, value);
    }
    db.addLeave(session.attemptId);
    expect(await exams.sync(session.attemptId), isA<Synced>());
    expect(db.dirty(session.attemptId).answers, isEmpty);

    // Lanjut dari "perangkat" yang sama → resumed, jawaban server ikut kembali.
    final again = await exams.start(kuis['id'] as String);
    expect(again.resumed, isTrue);
    expect(db.answers(session.attemptId).length, 10);

    final result = await exams.submit(session.attemptId);
    expect(result.pending, isFalse);
    expect(result.status, 'SUBMITTED', reason: 'ada soal esai → menunggu koreksi dosen');
    expect(db.attemptState(session.attemptId), isNull);

    // LMS ber-ETag: permintaan kedua dilayani 304 dari cache lokal.
    final d1 = await lms.dashboard();
    final d2 = await lms.dashboard();
    expect(d1.stale || d2.stale, isFalse);
    expect(d2.data['classes'], isNotEmpty);

    // Rotasi refresh token lalu logout.
    final before = await store.refreshToken();
    expect(await api.refreshSession(), isTrue);
    expect(await store.refreshToken(), isNot(before));
    await auth.logout();
    expect(await store.refreshToken(), isNull);
  }, skip: live.isEmpty ? 'set --dart-define=LIVE_API=... untuk uji terhadap server' : false);
}
