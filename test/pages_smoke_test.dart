import 'dart:io';


import 'package:flutter/material.dart';
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
import 'package:smartlms/features/exam/exam_repository.dart';
import 'package:smartlms/features/exam/prefetch.dart';
import 'package:smartlms/features/lms/lms_repository.dart';
import 'package:smartlms/main.dart';

import 'fake_routes.dart';
import 'fake_server.dart';
import 'server_clock_test.dart' show FakeMono;

/// Semua halaman dirender di lebar HP (390 px) dengan data seperti server: tidak boleh ada
/// error tata letak (overflow) atau exception. Navigasi lewat router seperti dari menu.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('id');
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, sink) => sink.success(['wifi'])));
  });

  testWidgets('semua halaman tampil di lebar HP tanpa error', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 logis
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = LocalDb.memory();
    final (api, store, _) = await fakeClient(fakeRoute);
    await store.saveTokens('akses', 'rt_x');
    final clock = ServerClock(FakeMono());
    final services = AppServices(store: store, db: db, api: api, clock: clock, auth: AuthRepository(api, store, db), exams: ExamRepository(api, db, clock), lms: LmsRepository(api, db, Directory.systemTemp), appVersion: '1.0.0');

    Future<void> settle() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return const SmartLmsApp();
      }),
    ));
    await settle();

    final pages = {
      '/dashboard': 'Halo, Peserta!',
      '/ujian': 'Sedang berlangsung',
      '/hasil': 'Hasil Ujian',
      '/kelas': 'Kelas Saya',
      '/kelas/k1': 'Ujian & Tugas',
      '/ujian/e1': 'Tata tertib',
      '/materi/m1': 'Lampiran',
      '/profil': 'Ganti password',
    };
    for (final MapEntry(key: path, value: marker) in pages.entries) {
      container.read(routerProvider).go(path, extra: path == '/kelas/k1' ? Map<String, dynamic>.from(fakeClass) : null);
      await settle();
      expect(find.textContaining(marker), findsWidgets, reason: path);
      expect(tester.takeException(), isNull, reason: 'error tata letak di $path');
    }

    // Laci navigasi seperti web.
    container.read(routerProvider).go('/dashboard');
    await settle();
    await tester.tap(find.byTooltip('Menu'));
    await settle();
    expect(find.text('Ujian Saya'), findsOneWidget);
    expect(find.text('UJIAN'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tab Materi di halaman kelas.
    container.read(routerProvider).go('/kelas/k1', extra: Map<String, dynamic>.from(fakeClass));
    await settle();
    await tester.tap(find.text('Materi'));
    await settle();
    expect(find.text('Minggu 1 — Pengantar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    cancelScheduledPrefetch();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('server versi lama (tanpa /site & menu) → tetap tampil dengan bawaan, tanpa error', (tester) async {
    tester.view.physicalSize = const Size(1170, 7000); // layar tinggi: kartu ujian di bawah ikut terbangun
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = LocalDb.memory();
    final (api, store, _) = await fakeClient(fakeRouteOldServer);
    await store.saveTokens('akses', 'rt_x');
    final clock = ServerClock(FakeMono());
    final services = AppServices(store: store, db: db, api: api, clock: clock, auth: AuthRepository(api, store, db), exams: ExamRepository(api, db, clock), lms: LmsRepository(api, db, Directory.systemTemp), appVersion: '1.0.0');
    await tester.pumpWidget(ProviderScope(overrides: [servicesProvider.overrideWithValue(services)], child: const SmartLmsApp()));
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Halo, Peserta!'), findsOneWidget);
    expect(find.text('Ujian lama'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hasil Ujian'), findsOneWidget, reason: 'menu bawaan');
    cancelScheduledPrefetch();
    await tester.pumpWidget(const SizedBox());
  });
}
