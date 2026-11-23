import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/local_db.dart';
import '../../core/time/server_clock.dart';
import 'exam_package.dart';

/// Lembar ujian yang siap dikerjakan.
class ExamSessionData {
  ExamSessionData({
    required this.attemptId,
    required this.examId,
    required this.questions,
    required this.deadline,
    required this.questionsPerPage,
    required this.maxLeaves,
    required this.resumed,
  });

  final String attemptId;
  final String examId;
  final List<PackageQuestion> questions;

  /// epoch ms server; null = tanpa batas waktu
  final int? deadline;
  final int questionsPerPage;
  final int? maxLeaves;
  final bool resumed;
}

/// Hasil satu kali sinkron jawaban.
sealed class SyncOutcome {
  const SyncOutcome();
}

class Synced extends SyncOutcome {
  const Synced(this.deadline);
  final int? deadline;
}

class SyncOffline extends SyncOutcome {
  const SyncOffline();
}

class SyncTimeUp extends SyncOutcome {
  const SyncTimeUp();
}

/// Dikumpulkan di server (pengawas, batas pelanggaran, waktu habis).
class SyncClosed extends SyncOutcome {
  const SyncClosed(this.result, this.message);
  final Map<String, dynamic> result;
  final String message;
}

class SyncRejected extends SyncOutcome {
  const SyncRejected(this.error);
  final ApiException error;
}

class SubmitResult {
  SubmitResult({required this.pending, this.status, this.score, this.late = false, this.message});

  /// true = belum terkirim (offline); tersimpan di antrean dan dikirim otomatis.
  final bool pending;
  final String? status;
  final num? score;
  final bool late;
  final String? message;
}

/// Ujian CBT: paket soal, mulai/lanjut, simpan delta bernomor urut, kumpul (dengan antrean offline).
class ExamRepository {
  ExamRepository(this.api, this.db, this.clock);

  final ApiClient api;
  final LocalDb db;
  final ServerClock clock;

  Future<List<Map<String, dynamic>>> list() async {
    final res = await api.getJson('/exams');
    if (res['now'] is int) await clock.sync(res['now'] as int);
    return (res['exams'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> detail(String examId) => api.getJson('/exams/$examId');

  /// Unduh paket soal bila belum ada / versinya berubah. Dipanggil sebelum ujian
  /// (dengan jitter dari pemanggil) agar saat Mulai hanya kunci yang dikirim server.
  Future<void> prefetchPackage(String examId, {String? version}) async {
    final local = db.package(examId);
    if (local != null && local.version == version) return;
    final res = await api.send<List<int>>('GET', '/exams/$examId/package',
        responseType: ResponseType.bytes, headers: {if (local != null) 'If-None-Match': '"${local.version}"'});
    if (res.statusCode == 304) return;
    final v = res.headers.value('x-package-version');
    if (v == null) throw ApiException(status: res.statusCode, code: 'BAD_PACKAGE', message: 'Paket soal tidak valid.');
    db.savePackage(examId, v, Uint8List.fromList(res.data!));
  }

  /// Mulai / lanjutkan. Melempar ApiException (TOKEN, OTHER_DEVICE, INTEGRITY_REQUIRED, ...).
  Future<ExamSessionData> start(String examId, {String? token}) async {
    final sw = Stopwatch()..start();
    final state = await api.postJson('/exams/$examId/start', {if (token != null && token.isNotEmpty) 'token': token}, retry: true);
    await clock.sync(state['now'] as int, rttMs: sw.elapsedMilliseconds);
    final attemptId = state['attemptId'] as String;
    // Disimpan (terenkripsi) termasuk kunci paket: aplikasi bisa dibuka ulang saat offline.
    db.saveAttempt(attemptId, examId, {...state, 'examId': examId});
    final pkgInfo = state['package'] as Map<String, dynamic>;
    if (db.package(examId)?.version != pkgInfo['version']) await prefetchPackage(examId, version: pkgInfo['version'] as String);
    return _open(attemptId, examId, state, resumed: state['resumed'] == true);
  }

  /// Buka kembali dari data lokal (mis. aplikasi ditutup saat offline). null bila tidak ada.
  Future<ExamSessionData?> reopenOffline(String attemptId) async {
    final state = db.attemptState(attemptId);
    if (state == null) return null;
    return _open(attemptId, state['examId'] as String? ?? '', state, resumed: true);
  }

  Future<ExamSessionData> _open(String attemptId, String examId, Map<String, dynamic> state, {required bool resumed}) async {
    final local = db.package(examId);
    final key = (state['package'] as Map)['key'] as String;
    if (local == null) throw ApiException(status: null, code: 'NO_PACKAGE', message: 'Paket soal belum terunduh. Sambungkan internet lalu coba lagi.');
    final pkg = await openPackage(local.blob, key);
    return ExamSessionData(
      attemptId: attemptId,
      examId: examId,
      questions: applyLayout(pkg.questions, state['layout'] as Map<String, dynamic>?),
      deadline: db.attemptMeta(attemptId).deadline,
      questionsPerPage: state['questionsPerPage'] as int? ?? 1,
      maxLeaves: state['maxLeaves'] as int?,
      resumed: resumed,
    );
  }

  /// Kirim perubahan yang belum tersinkron (juga berfungsi sebagai detak untuk Monitoring Ujian).
  Future<SyncOutcome> sync(String attemptId) async {
    for (var round = 0; round < 3; round++) {
      final meta = db.attemptMeta(attemptId);
      final dirty = db.dirty(attemptId);
      final seq = meta.seq + 1;
      final sw = Stopwatch()..start();
      try {
        final res = await api.putJson(
            '/attempts/$attemptId/answers',
            {
              'seq': seq,
              'answers': dirty.answers,
              'cleared': dirty.cleared,
              if (meta.flaggedDirty) 'flagged': meta.flagged,
              'leaveCount': meta.leaveCount,
            },
            retry: true);
        await clock.sync(res['now'] as int, rttMs: sw.elapsedMilliseconds);
        if (res['duplicate'] == true) {
          // Seq ini sudah tercatat oleh permintaan sebelumnya yang responsnya hilang; isinya
          // mungkin lebih sedikit dari perubahan sekarang → kirim ulang dengan seq berikutnya.
          db.setSeq(attemptId, res['seq'] as int);
          continue;
        }
        db.markSynced(attemptId, seq, dirty.upTo, flaggedSent: meta.flaggedDirty);
        db.setDeadline(attemptId, res['deadline'] as int?);
        return Synced(res['deadline'] as int?);
      } on ApiException catch (e) {
        if (e.isNetwork || e.status == 502 || e.status == 503 || e.status == 504 || e.status == 429) return const SyncOffline();
        if (e.code == 'STALE_SEQ') {
          db.setSeq(attemptId, e.data['seq'] as int);
          continue;
        }
        if (e.code == 'TIME_UP') return const SyncTimeUp();
        if (e.code == 'ATTEMPT_CLOSED') return SyncClosed(Map<String, dynamic>.from(e.data['result'] as Map? ?? const {}), e.message);
        return SyncRejected(e);
      }
    }
    return const SyncOffline();
  }

  /// Kumpulkan: masuk antrean lokal DULU, lalu dikirim. Offline → dikirim otomatis nanti
  /// ([flushPending]). Server idempotent: kiriman ganda mengembalikan hasil yang sama.
  Future<SubmitResult> submit(String attemptId) async {
    final meta = db.attemptMeta(attemptId);
    db.queueSubmit(attemptId, {'answers': db.answers(attemptId), 'flagged': meta.flagged, 'leaveCount': meta.leaveCount});
    return _send(attemptId, db.pendingSubmits()[attemptId]!);
  }

  Future<SubmitResult> _send(String attemptId, Map<String, dynamic> payload) async {
    try {
      final res = await api.postJson('/attempts/$attemptId/submit', payload, retry: true);
      db.finishAttempt(attemptId);
      return SubmitResult(pending: false, status: res['status'] as String?, score: res['score'] as num?, late: res['late'] == true, message: res['message'] as String?);
    } on ApiException catch (e) {
      if (e.isNetwork || (e.status ?? 0) >= 500 || e.status == 429) return SubmitResult(pending: true, message: 'Jawaban tersimpan di perangkat dan akan dikirim otomatis saat koneksi kembali.');
      if (e.code == 'NOT_FOUND') db.finishAttempt(attemptId);
      rethrow;
    }
  }

  /// Kirim semua kumpulan yang tertunda (dipanggil saat aplikasi dibuka & saat sinyal kembali).
  Future<void> flushPending() async {
    for (final e in db.pendingSubmits().entries) {
      try {
        await _send(e.key, e.value);
      } on ApiException {
        // ditolak permanen (mis. bukan lagi peserta) — biarkan, ditampilkan di layar ujian
      }
    }
  }
}
