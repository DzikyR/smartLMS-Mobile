// Tangkapan layar aplikasi (PNG) dengan font & ikon asli, untuk dibandingkan dengan tampilan web.
// Dilewati kecuali: flutter test test/visual --dart-define=SCREENS=build/screens
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smartlms/app/providers.dart';
import 'package:smartlms/app/router.dart';
import 'package:smartlms/app/services.dart';
import 'package:smartlms/core/storage/local_db.dart';
import 'package:smartlms/core/time/server_clock.dart';
import 'package:smartlms/features/auth/auth_repository.dart';
import 'package:smartlms/features/exam/exam_package.dart';
import 'package:smartlms/features/exam/exam_repository.dart';
import 'package:smartlms/features/exam/prefetch.dart';
import 'package:smartlms/features/lms/lms_repository.dart';
import 'package:smartlms/main.dart';

import '../fake_routes.dart';
import '../fake_server.dart';
import '../server_clock_test.dart' show FakeMono;

const out = String.fromEnvironment('SCREENS');

Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    jakarta.addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync())));
  }
  await jakarta.load();
  // Lokasi paket ikon dari package_config.
  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  final lucide = (config['packages'] as List).firstWhere((p) => p['name'] == 'lucide_icons_flutter');
  final root = Uri.parse(lucide['rootUri'] as String).toFilePath();
  final icons = FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(Future.value(ByteData.sublistView(File('$root/assets/lucide.ttf').readAsBytesSync())));
  await icons.load();
}

void main() {
  testWidgets('tangkapan layar', (tester) async {
    await tester.runAsync(_loadFonts);
    await initializeDateFormatting('id');
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, sink) => sink.success(['wifi'])));
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Directory(out).createSync(recursive: true);

    final db = LocalDb.memory();
    final (api, store, _) = await fakeClient(fakeRoute);
    await store.saveTokens('akses', 'rt_x');
    final clock = ServerClock(FakeMono());
    final exams = ExamRepository(api, db, clock);
    final services = AppServices(store: store, db: db, api: api, clock: clock, auth: AuthRepository(api, store, db), exams: exams, lms: LmsRepository(api, db, Directory.systemTemp), appVersion: '1.0.0');
    final key = GlobalKey();

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> shot(String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    late ProviderContainer container;
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const SmartLmsApp();
        }),
      ),
    ));
    await settle();

    Future<void> page(String name, String path, {Object? extra}) async {
      container.read(routerProvider).go(path, extra: extra);
      await settle();
      await shot(name);
    }

    await page('02-dashboard', '/dashboard');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle();
    await shot('03-dashboard-bawah');
    container.read(routerProvider).go('/dashboard');
    await settle();
    await tester.tap(find.byTooltip('Menu'));
    await settle();
    await shot('04-menu');
    await page('05-kelas', '/kelas');
    await page('06-kelas-detail', '/kelas/k1', extra: Map<String, dynamic>.from(fakeClass));
    await tester.tap(find.text('Materi'));
    await settle();
    await shot('07-kelas-materi');
    await page('08-ujian', '/ujian');
    await page('09-ujian-detail', '/ujian/e1');
    await page('13-hasil', '/hasil');
    await page('14-profil', '/profil');

    // Lembar ujian dari paket fixture server.
    final fx = jsonDecode(File('test/fixtures/package_fixture.json').readAsStringSync()) as Map<String, dynamic>;
    db
      ..savePackage('exam-fixture', fx['version'] as String, base64Decode(fx['blob'] as String))
      ..saveAttempt('att1', 'exam-fixture', {'seq': 0, 'answers': {'q1': 'b'}, 'flagged': ['q2'], 'deadline': 1_700_001_190_000});
    await clock.sync(1_700_000_000_000);
    final pkg = await tester.runAsync(() => openPackage(db.package('exam-fixture')!.blob, fx['key'] as String));
    final data = ExamSessionData(attemptId: 'att1', examId: 'exam-fixture', questions: pkg!.questions, deadline: 1_700_001_190_000, questionsPerPage: 2, maxLeaves: 3, resumed: false);
    await page('16-lembar-ujian', '/ujian/exam-fixture/kerjakan', extra: data);

    // Layar masuk.
    await tester.runAsync(() => store.clearTokens());
    await container.read(authProvider.notifier).logout();
    await settle();
    await shot('01-login');

    cancelScheduledPrefetch();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }, skip: out.isEmpty); // aktifkan dengan --dart-define=SCREENS=<folder>
}
