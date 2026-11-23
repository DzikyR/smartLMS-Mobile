import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/features/exam/exam_package.dart';

/// Fixture dibuat dari kode server asli (smartTest/src/lib/mobile/package.ts → sealPackage),
/// jadi uji ini membuktikan format biner Node ↔ Dart cocok.
void main() {
  final fx = jsonDecode(File('test/fixtures/package_fixture.json').readAsStringSync()) as Map<String, dynamic>;
  final blob = Uint8List.fromList(base64Decode(fx['blob'] as String));

  test('paket dari server dibuka dengan kuncinya (termasuk teks unicode)', () async {
    final pkg = await openPackage(blob, fx['key'] as String);
    expect(pkg.version, fx['version']);
    expect(pkg.examId, 'exam-fixture');
    expect(pkg.questions.map((q) => q.id), ['q1', 'q2', 'q3']);
    expect(pkg.questions[0].options.map((o) => o.text), ['Queue', 'Stack']);
    expect(pkg.questions[1].prompt, contains('ünïcödé'));
    expect(pkg.questions[2].points, 5);
  });

  test('kunci salah / isi diubah → ditolak (AES-GCM)', () async {
    final wrongKey = base64Encode(List.filled(32, 7));
    await expectLater(openPackage(blob, wrongKey), throwsA(anything));
    final tampered = Uint8List.fromList(blob)..[20] ^= 1;
    await expectLater(openPackage(tampered, fx['key'] as String), throwsA(anything));
    await expectLater(openPackage(Uint8List(10), fx['key'] as String), throwsA(isA<FormatException>()));
  });

  test('applyLayout: urutan soal & pilihan dari server, soal di luar layout di akhir', () async {
    final pkg = await openPackage(blob, fx['key'] as String);
    final ordered = applyLayout(pkg.questions, {
      'questions': ['q3', 'q1'],
      'options': {
        'q1': ['b', 'a'],
      },
    });
    expect(ordered.map((q) => q.id), ['q3', 'q1', 'q2']);
    expect(ordered[1].options.map((o) => o.id), ['b', 'a']);
    expect(applyLayout(pkg.questions, null).map((q) => q.id), ['q1', 'q2', 'q3']);
  });
}
