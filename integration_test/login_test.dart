// Uji di emulator/HP sungguhan terhadap server SmartTest (bukan data palsu):
//   flutter test integration_test -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:3123 \
//     --dart-define=LIVE_USER=trial.mobile --dart-define=LIVE_PASSWORD=...
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartlms/main.dart' as app;

const user = String.fromEnvironment('LIVE_USER', defaultValue: 'trial.mobile');
const password = String.fromEnvironment('LIVE_PASSWORD');

Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 30}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Tidak muncul dalam $seconds dtk: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login → dashboard → ujian → mulai → jawab → kumpul', (tester) async {
    app.main();
    // Sesi lama (bila ada) → langsung dashboard; selain itu layar masuk.
    await waitFor(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'Masuk' || (w.data ?? '').startsWith('Halo,'))));
    if (find.text('Masuk').evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField).at(0), user);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.tap(find.text('Masuk'));
    }
    await waitFor(tester, find.textContaining('Halo,'));
    expect(find.textContaining('Halo,'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ujian Saya'));
    await waitFor(tester, find.text('Uji Coba Aplikasi Mobile'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Uji Coba Aplikasi Mobile'));
    await waitFor(tester, find.text('Tata tertib'));
    final start = find.byWidgetPredicate((w) => w is Text && (w.data == 'Mulai ujian' || w.data == 'Lanjutkan ujian'));
    // Tunggu animasi perpindahan halaman selesai sebelum mengetuk.
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(start, 300, scrollable: find.byType(Scrollable).last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(start);

    // Lembar ujian (paket soal didekripsi di perangkat, pengaman native aktif).
    await waitFor(tester, find.text('dari 10'));
    expect(find.textContaining('Halaman 1 dari'), findsNothing, reason: 'navigasi halaman di bawah');
    await tester.tap(find.text('A').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(LucideIcons.layoutGrid));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kumpulkan ujian'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Kumpulkan')));
    await waitFor(tester, find.text('Ujian terkumpul'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Selesai'));
    await tester.pumpAndSettle();
  });
}
