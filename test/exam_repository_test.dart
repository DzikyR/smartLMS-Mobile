import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/core/storage/local_db.dart';
import 'package:smartlms/core/time/server_clock.dart';
import 'package:smartlms/features/exam/exam_repository.dart';

import 'fake_server.dart';
import 'server_clock_test.dart' show FakeMono;

void main() {
  late LocalDb db;
  setUp(() {
    db = LocalDb.memory();
    db.saveAttempt('a1', 'e1', {'seq': 3, 'leaveCount': 0, 'answers': <String, dynamic>{}, 'flagged': <String>[], 'deadline': 9_000_000});
  });
  tearDown(() => db.close());

  test('simpan delta: seq naik, hanya perubahan yang dikirim, deadline dari server', () async {
    final (api, _, server) = await fakeClient((req) => reply(200, {'seq': (req.data as Map)['seq'], 'deadline': 9_600_000, 'now': 1_000, 'savedAt': 1_000, 'duplicate': false}));
    final repo = ExamRepository(api, db, ServerClock(FakeMono()));
    db.setAnswer('a1', 'q1', 'b');
    db.setAnswer('a1', 'q2', null);
    db.setFlagged('a1', ['q1']);
    final out = await repo.sync('a1');
    expect(out, isA<Synced>().having((s) => s.deadline, 'deadline', 9_600_000), reason: 'tambah waktu pengawas terbaca');
    final body = server.requests.single.data as Map;
    expect(body['seq'], 4);
    expect(body['answers'], {'q1': 'b'});
    expect(body['cleared'], ['q2']);
    expect(body['flagged'], ['q1']);
    expect(db.dirty('a1').answers, isEmpty);
    expect(db.attemptMeta('a1').seq, 4);

    await repo.sync('a1'); // detak tanpa perubahan: tetap dikirim (monitoring), tanpa flagged
    final beat = server.requests.last.data as Map;
    expect(beat['seq'], 5);
    expect(beat['answers'], isEmpty);
    expect(beat.containsKey('flagged'), isFalse);
  });

  test('respons hilang sebelumnya (duplicate) → dikirim ulang dengan seq berikutnya, tidak dianggap tersimpan', () async {
    final (api, _, server) = await fakeClient((req) {
      final seq = (req.data as Map)['seq'] as int;
      return seq == 4 ? reply(200, {'seq': 4, 'deadline': null, 'now': 1, 'duplicate': true}) : reply(200, {'seq': seq, 'deadline': null, 'now': 1, 'duplicate': false});
    });
    final repo = ExamRepository(api, db, ServerClock(FakeMono()));
    db.setAnswer('a1', 'q1', 'b');
    expect(await repo.sync('a1'), isA<Synced>());
    expect(server.requests.map((r) => (r.data as Map)['seq']), [4, 5]);
    expect((server.requests.last.data as Map)['answers'], {'q1': 'b'});
  });

  test('STALE_SEQ → ikut seq server lalu kirim ulang; offline → jawaban tetap dirty', () async {
    var offline = false;
    final (api, _, server) = await fakeClient((req) {
      if (offline) return null;
      final seq = (req.data as Map)['seq'] as int;
      return seq <= 10 ? reply(409, {'error': 'STALE_SEQ', 'message': 'x', 'seq': 10}) : reply(200, {'seq': seq, 'deadline': null, 'now': 1, 'duplicate': false});
    });
    final repo = ExamRepository(api, db, ServerClock(FakeMono()));
    db.setAnswer('a1', 'q1', 'a');
    expect(await repo.sync('a1'), isA<Synced>());
    expect((server.requests.last.data as Map)['seq'], 11);

    offline = true;
    db.setAnswer('a1', 'q2', 'true');
    expect(await repo.sync('a1'), isA<SyncOffline>());
    expect(db.dirty('a1').answers, {'q2': 'true'});
  });

  test('ditutup server (pengawas/batas pelanggaran) & waktu habis dikenali', () async {
    var code = 'ATTEMPT_CLOSED';
    final (api, _, _) = await fakeClient((_) => reply(409, {'error': code, 'message': 'Dikumpulkan pengawas', 'result': {'status': 'GRADED', 'score': 80, 'reason': 'PROCTOR'}}));
    final repo = ExamRepository(api, db, ServerClock(FakeMono()));
    final closed = await repo.sync('a1');
    expect(closed, isA<SyncClosed>().having((c) => c.result['reason'], 'reason', 'PROCTOR'));
    code = 'TIME_UP';
    expect(await repo.sync('a1'), isA<SyncTimeUp>());
  });

  test('kumpul offline → antrean lokal; dikirim otomatis saat online & data lokal dibersihkan', () async {
    var offline = true;
    final (api, _, server) = await fakeClient((req) => offline ? null : reply(200, {'status': 'GRADED', 'score': 100, 'late': false, 'message': 'ok', 'duplicate': false}));
    final repo = ExamRepository(api, db, ServerClock(FakeMono()));
    db.setAnswer('a1', 'q1', 'b');
    final pending = await repo.submit('a1');
    expect(pending.pending, isTrue);
    expect(db.pendingSubmits()['a1']?['answers'], {'q1': 'b'});

    offline = false;
    await repo.flushPending();
    expect(db.pendingSubmits(), isEmpty);
    expect(db.attemptState('a1'), isNull);
    expect((server.requests.last.data as Map)['answers'], {'q1': 'b'});
  });
}
