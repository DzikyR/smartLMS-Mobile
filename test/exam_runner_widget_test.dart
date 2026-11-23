import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smartlms/app/providers.dart';
import 'package:smartlms/app/services.dart';
import 'package:smartlms/app/site.dart';
import 'package:smartlms/app/theme.dart';
import 'package:smartlms/core/storage/local_db.dart';
import 'package:smartlms/core/time/server_clock.dart';
import 'package:smartlms/features/auth/auth_repository.dart';
import 'package:smartlms/features/exam/exam_package.dart';
import 'package:smartlms/features/exam/exam_repository.dart';
import 'package:smartlms/features/exam/exam_runner_page.dart';
import 'package:smartlms/features/lms/lms_repository.dart';

import 'fake_server.dart';
import 'server_clock_test.dart' show FakeMono;

/// Lembar ujian dirender seperti di HP (paket dari server asli, 2 soal per halaman, PG/BS/esai).
void main() {
  setUpAll(() async {
    await initializeDateFormatting('id');
    const status = EventChannel('dev.fluttercommunity.plus/connectivity_status');
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockStreamHandler(status, MockStreamHandler.inline(onListen: (_, sink) => sink.success(['wifi'])));
  });

  testWidgets('lembar ujian: render, jawab, ragu-ragu, pindah halaman, kumpul', (tester) async {
    // Layar tinggi agar semua soal + navigasi halaman terbangun (ListView membangun yang terlihat saja).
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final fx = jsonDecode(File('test/fixtures/package_fixture.json').readAsStringSync()) as Map<String, dynamic>;
    final db = LocalDb.memory()
      ..savePackage('exam-fixture', fx['version'] as String, Uint8List.fromList(base64Decode(fx['blob'] as String)))
      ..saveAttempt('att1', 'exam-fixture', {'seq': 0, 'answers': <String, dynamic>{}, 'flagged': <String>[], 'deadline': 4_000_000_000_000});
    final (api, store, server) = await fakeClient((req) => req.path.endsWith('/submit')
        ? reply(200, {'status': 'SUBMITTED', 'score': null, 'late': false, 'message': 'Ujian terkumpul. Soal esai menunggu penilaian.', 'duplicate': false})
        : reply(200, {'seq': 1, 'deadline': 4_000_000_000_000, 'now': 1, 'duplicate': false}));
    final clock = ServerClock(FakeMono());
    final exams = ExamRepository(api, db, clock);
    final services = AppServices(store: store, db: db, api: api, clock: clock, auth: AuthRepository(api, store, db), exams: exams, lms: LmsRepository(api, db, Directory.systemTemp), appVersion: '1.0.0');
    final pkg = await openPackage(db.package('exam-fixture')!.blob, fx['key'] as String);
    final data = ExamSessionData(attemptId: 'att1', examId: 'exam-fixture', questions: pkg.questions, deadline: 4_000_000_000_000, questionsPerPage: 2, maxLeaves: 3, resumed: false);

    await tester.pumpWidget(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: MaterialApp(theme: buildTheme(Brightness.light, const SiteConfig()), home: ExamRunnerPage(data: data)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('dari 3'), findsNWidgets(2), reason: '2 soal per halaman');
    expect(find.text('Halaman 1 dari 2'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);

    await tester.tap(find.textContaining('Stack'));
    await tester.tap(find.text('Benar'));
    await tester.tap(find.text('Ragu-ragu').first);
    await tester.pump();
    expect(db.answers('att1'), {'q1': 'b', 'q2': 'true'});

    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byTooltip('Berikutnya'));
    await tester.pump();
    expect(find.text('Halaman 2 dari 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Rekursi memanggil dirinya sendiri.');
    await tester.pump();
    expect(db.answers('att1')['q3'], startsWith('Rekursi'));

    await tester.tap(find.text('Kumpulkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Kumpulkan')));
    for (var i = 0; i < 30 && find.text('Ujian terkumpul').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (find.text('Ujian terkumpul').evaluate().isEmpty) {
      // ignore: avoid_print
      print([for (final e in find.byType(Text).evaluate()) (e.widget as Text).data].join(' | '));
    }
    expect(find.text('Ujian terkumpul'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(server.requests.any((r) => r.path.endsWith('/submit')), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
