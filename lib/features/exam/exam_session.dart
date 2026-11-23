import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../core/security/exam_guard.dart';
import '../../core/storage/local_db.dart';
import '../../core/time/server_clock.dart';
import 'exam_package.dart';
import 'exam_repository.dart';

enum SyncState { idle, syncing, offline, error }

/// Lembar ujian yang sedang dikerjakan: jawaban → database lokal (0 jaringan per klik),
/// sinkron delta tiap 60 dtk (15 dtk di 5 menit terakhir) + saat sinyal kembali + saat
/// aplikasi ke belakang; timer dari jam server; kumpul otomatis saat waktu habis.
class ExamSession extends ChangeNotifier {
  ExamSession({required this.data, required this.repo, required this.db, required this.clock, ExamGuard? guard, Stream<List<ConnectivityResult>>? connectivity})
      : _connectivity = connectivity {
    _answers = db.answers(data.attemptId);
    _flagged = db.attemptMeta(data.attemptId).flagged.toSet();
    _deadline = data.deadline;
    _guard = guard ?? ExamGuard(onViolation: _violation, onCover: (c) => _set(() => covered = c));
  }

  final ExamSessionData data;
  final ExamRepository repo;
  final LocalDb db;
  final ServerClock clock;
  final Stream<List<ConnectivityResult>>? _connectivity;
  late final ExamGuard _guard;

  late Map<String, String> _answers;
  late Set<String> _flagged;
  int? _deadline;
  int page = 0;
  bool covered = false;
  SyncState syncState = SyncState.idle;
  DateTime? lastSyncedAt;
  String? notice;

  /// Terisi setelah dikumpulkan (oleh peserta, waktu habis, pengawas, atau batas pelanggaran).
  SubmitResult? result;
  bool submitting = false;

  Timer? _tick;
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _net;
  bool _disposed = false;
  bool _autoSubmitScheduled = false;

  List<PackageQuestion> get questions => data.questions;
  int get perPage => max(1, data.questionsPerPage);
  int get pageCount => (questions.length / perPage).ceil();
  List<PackageQuestion> get pageQuestions => questions.skip(page * perPage).take(perPage).toList();
  String? answerOf(String qid) => _answers[qid];
  bool isFlagged(String qid) => _flagged.contains(qid);
  int get answeredCount => _answers.values.where((v) => v.trim().isNotEmpty).length;
  Duration? get remaining => clock.remaining(_deadline);
  int get leaveCount => db.attemptMeta(data.attemptId).leaveCount;
  bool get finished => result != null;

  void _set(VoidCallback f) {
    if (_disposed) return;
    f();
    notifyListeners();
  }

  Future<void> begin() async {
    await _guard.enable();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _net = (_connectivity ?? Connectivity().onConnectivityChanged).listen((r) {
      if (r.contains(ConnectivityResult.none)) return;
      if (result?.pending == true) {
        retryPendingSubmit();
      } else {
        sync();
      }
    });
    // Jitter awal: peserta yang mulai bersamaan tidak menyimpan di detik yang sama.
    _syncTimer = Timer(Duration(seconds: Random().nextInt(AppConfig.syncInterval.inSeconds)), _scheduledSync);
  }

  Future<void> _onTick() async {
    await clock.tick();
    final left = remaining;
    if (left != null && left == Duration.zero && !finished && !_autoSubmitScheduled) {
      _autoSubmitScheduled = true;
      // Jitter 0–10 dtk (masih di dalam toleransi 2 menit server) agar kumpul serentak tersebar.
      Timer(Duration(milliseconds: Random().nextInt(10000)), () => submit(auto: true));
    }
    _set(() {});
  }

  void _scheduledSync() {
    if (_disposed || finished) return;
    sync();
    final left = remaining;
    final next = left != null && left <= AppConfig.finalPhase ? AppConfig.syncIntervalFinal : AppConfig.syncInterval;
    _syncTimer = Timer(next, _scheduledSync);
  }

  void answer(String qid, String? value) {
    if (finished) return;
    final v = (value == null || value.isEmpty) ? null : value;
    db.setAnswer(data.attemptId, qid, v);
    _set(() => v == null ? _answers.remove(qid) : _answers[qid] = v);
  }

  void toggleFlag(String qid) {
    if (finished) return;
    _set(() => _flagged.contains(qid) ? _flagged.remove(qid) : _flagged.add(qid));
    db.setFlagged(data.attemptId, _flagged.toList());
  }

  void goTo(int p) => _set(() => page = p.clamp(0, pageCount - 1));

  void _violation(String kind) {
    if (finished) return;
    final total = db.addLeave(data.attemptId);
    final max = data.maxLeaves;
    _set(() => notice = max != null
        ? 'Pelanggaran tercatat ($total dari $max): ${_label(kind)}. Batas tercapai → jawaban dikumpulkan otomatis.'
        : 'Pelanggaran tercatat: ${_label(kind)}. Pengawas dapat melihatnya.');
    sync(); // server yang memutuskan batasnya (sama dengan web)
  }

  static String _label(String kind) => switch (kind) {
        'bg' => 'keluar dari aplikasi',
        'split' => 'layar terbagi / jendela mengambang',
        'shot' => 'tangkapan layar',
        'rec' => 'rekam layar',
        _ => kind,
      };

  Future<void> sync() async {
    if (finished || syncState == SyncState.syncing) return;
    _set(() => syncState = SyncState.syncing);
    final outcome = await repo.sync(data.attemptId);
    switch (outcome) {
      case Synced(:final deadline):
        _set(() {
          _deadline = deadline;
          syncState = SyncState.idle;
          lastSyncedAt = DateTime.now();
        });
      case SyncOffline():
        _set(() => syncState = SyncState.offline);
      case SyncTimeUp():
        await submit(auto: true);
      case SyncClosed(:final result, :final message):
        db.finishAttempt(data.attemptId);
        await _finish(SubmitResult(pending: false, status: result['status'] as String?, score: result['score'] as num?, message: message));
      case SyncRejected(:final error):
        _set(() {
          syncState = SyncState.error;
          notice = error.message;
        });
    }
  }

  /// Kumpulkan. Offline → tersimpan di antrean & dikirim otomatis (result.pending = true).
  Future<void> submit({bool auto = false}) async {
    if (finished || submitting) return;
    _set(() => submitting = true);
    try {
      final r = await repo.submit(data.attemptId);
      await _finish(r);
    } catch (e) {
      _set(() {
        submitting = false;
        notice = '$e';
      });
    }
  }

  /// Kumpul tertunda (offline) dikirim ulang — aman diulang, server idempotent.
  Future<void> retryPendingSubmit() async {
    if (result?.pending != true || submitting) return;
    _set(() => submitting = true);
    try {
      final r = await repo.submit(data.attemptId);
      _set(() {
        result = r;
        submitting = false;
      });
    } catch (e) {
      _set(() {
        submitting = false;
        notice = '$e';
      });
    }
  }

  Future<void> _finish(SubmitResult r) async {
    _tick?.cancel();
    _syncTimer?.cancel();
    await _guard.disable();
    _set(() {
      result = r;
      submitting = false;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _syncTimer?.cancel();
    _net?.cancel();
    if (!finished) {
      _guard.disable();
      // Keluar dari layar ujian tanpa kumpul: simpan yang tersisa (best effort).
      repo.sync(data.attemptId);
    }
    super.dispose();
  }
}
