import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/core/storage/local_db.dart';

void main() {
  const key = 'aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233';

  test('database terenkripsi: teks tidak terbaca di berkas, kunci salah ditolak', () {
    final dir = Directory.systemTemp.createTempSync('smartlms');
    final path = '${dir.path}/t.db';
    final db = LocalDb.open(path, key)..savePackage('e1', 'v1', Uint8List.fromList([1, 2, 3]));
    db.saveAttempt('a1', 'e1', {'seq': 0, 'answers': <String, dynamic>{}, 'deadline': null});
    db.setAnswer('a1', 'q1', 'JAWABAN-RAHASIA');
    db.close();
    expect(String.fromCharCodes(File(path).readAsBytesSync()).contains('JAWABAN-RAHASIA'), isFalse);
    expect(() => LocalDb.open(path, 'ff' * 32), throwsA(anything));
    final again = LocalDb.open(path, key);
    expect(again.answers('a1'), {'q1': 'JAWABAN-RAHASIA'});
    again.close();
    expect(() => LocalDb.open(path, 'bukan-hex'), throwsArgumentError);
  });

  group('jawaban & sinkron', () {
    late LocalDb db;
    setUp(() {
      db = LocalDb.memory();
      db.saveAttempt('a1', 'e1', {'seq': 2, 'leaveCount': 1, 'answers': {'q1': 'a'}, 'flagged': ['q1'], 'deadline': 1000});
    });
    tearDown(() => db.close());

    test('jawaban dari server tidak dihitung sebagai perubahan lokal', () {
      expect(db.answers('a1'), {'q1': 'a'});
      expect(db.dirty('a1').answers, isEmpty);
      final m = db.attemptMeta('a1');
      expect((m.seq, m.leaveCount, m.deadline), (2, 1, 1000));
      expect(m.flagged, ['q1']);
    });

    test('ubah & hapus → dirty; markSynced hanya sampai waktu snapshot', () async {
      db.setAnswer('a1', 'q1', 'b');
      db.setAnswer('a1', 'q2', null);
      final d = db.dirty('a1');
      expect(d.answers, {'q1': 'b'});
      expect(d.cleared, ['q2']);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      db.setAnswer('a1', 'q3', 'x'); // diubah selama permintaan berjalan
      db.markSynced('a1', 3, d.upTo, flaggedSent: false);
      expect(db.dirty('a1').answers, {'q3': 'x'});
      expect(db.attemptMeta('a1').seq, 3);
      expect(db.answers('a1'), {'q1': 'b', 'q3': 'x'});
    });

    test('lanjut dari server tidak menimpa perubahan lokal yang belum terkirim', () {
      db.setAnswer('a1', 'q1', 'c');
      db.setFlagged('a1', ['q9']);
      db.saveAttempt('a1', 'e1', {'seq': 1, 'leaveCount': 0, 'answers': {'q1': 'a', 'q2': 'true'}, 'flagged': <String>[], 'deadline': 2000});
      expect(db.answers('a1'), {'q1': 'c', 'q2': 'true'});
      final m = db.attemptMeta('a1');
      expect(m.seq, 2, reason: 'seq tidak mundur');
      expect(m.leaveCount, 1, reason: 'pelanggaran tidak berkurang');
      expect(m.flagged, ['q9']);
      expect(m.deadline, 2000);
    });

    test('pelanggaran hanya bertambah; antrean kumpul; selesai = dibersihkan', () {
      expect(db.addLeave('a1'), 2);
      db.queueSubmit('a1', {'answers': db.answers('a1')});
      expect(db.pendingSubmits().keys, ['a1']);
      db.finishAttempt('a1');
      expect(db.pendingSubmits(), isEmpty);
      expect(db.answers('a1'), isEmpty);
      expect(db.attemptState('a1'), isNull);
    });

    test('cache ETag', () {
      db.saveCache('/dashboard', 'W/"x"', '{"a":1}');
      expect(db.cached('/dashboard')?.etag, 'W/"x"');
      db.clearCache();
      expect(db.cached('/dashboard'), isNull);
    });
  });
}
