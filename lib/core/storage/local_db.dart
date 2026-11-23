import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Database lokal TERENKRIPSI (SQLite3MultipleCiphers, ChaCha20) — kunci di secure storage.
/// Menyimpan paket soal (tetap terenkripsi kunci server), jawaban yang belum tersinkron,
/// antrean kumpul ujian (outbox), dan cache respons ber-ETag.
class LocalDb {
  LocalDb._(this._db);
  final Database _db;

  static const _schemaVersion = 1;

  factory LocalDb.open(String path, String hexKey) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) throw ArgumentError('kunci database tidak sah');
    final db = sqlite3.open(path)..execute("PRAGMA key = '$hexKey'");
    final cipher = db.select('PRAGMA cipher');
    if (cipher.isEmpty) {
      db.close();
      throw StateError('SQLite tanpa enkripsi termuat — periksa hooks.user_defines.sqlite3.source di pubspec.yaml');
    }
    return LocalDb._(db).._migrate();
  }

  /// Untuk uji.
  factory LocalDb.memory() => LocalDb._(sqlite3.openInMemory()).._migrate();

  void _migrate() {
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version >= _schemaVersion) return;
    _db.execute('''
      CREATE TABLE IF NOT EXISTS packages (exam_id TEXT PRIMARY KEY, version TEXT NOT NULL, blob BLOB NOT NULL, saved_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS attempts (
        attempt_id TEXT PRIMARY KEY, exam_id TEXT NOT NULL, state TEXT NOT NULL,
        seq INTEGER NOT NULL DEFAULT 0, leave_count INTEGER NOT NULL DEFAULT 0, flagged TEXT NOT NULL DEFAULT '[]',
        flagged_dirty INTEGER NOT NULL DEFAULT 0, deadline INTEGER, updated_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS answers (
        attempt_id TEXT NOT NULL, qid TEXT NOT NULL, value TEXT, dirty INTEGER NOT NULL DEFAULT 1, changed_at INTEGER NOT NULL,
        PRIMARY KEY (attempt_id, qid));
      CREATE TABLE IF NOT EXISTS submits (attempt_id TEXT PRIMARY KEY, payload TEXT NOT NULL, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS http_cache (key TEXT PRIMARY KEY, etag TEXT NOT NULL, body TEXT NOT NULL, saved_at INTEGER NOT NULL);
      PRAGMA user_version = $_schemaVersion;
    ''');
  }

  void close() => _db.close();

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- paket soal

  ({String version, Uint8List blob})? package(String examId) {
    final r = _db.select('SELECT version, blob FROM packages WHERE exam_id = ?', [examId]);
    return r.isEmpty ? null : (version: r.first['version'] as String, blob: r.first['blob'] as Uint8List);
  }

  void savePackage(String examId, String version, Uint8List blob) => _db.execute('INSERT OR REPLACE INTO packages VALUES (?, ?, ?, ?)', [examId, version, blob, _now]);

  // ---------------------------------------------------------------- percobaan

  /// Simpan keadaan dari server (respons start). Jawaban server digabung TANPA menimpa
  /// jawaban lokal yang belum tersinkron (dirty).
  void saveAttempt(String attemptId, String examId, Map<String, dynamic> state) {
    final answers = Map<String, dynamic>.from(state['answers'] as Map? ?? const {});
    final copy = Map<String, dynamic>.from(state)..remove('answers');
    _db.execute('BEGIN');
    try {
      final existing = _db.select('SELECT seq, leave_count FROM attempts WHERE attempt_id = ?', [attemptId]);
      final seq = state['seq'] as int? ?? 0;
      final localLeaves = existing.isEmpty ? 0 : existing.first['leave_count'] as int;
      final serverLeaves = state['leaveCount'] as int? ?? 0;
      _db.execute(
        '''INSERT INTO attempts (attempt_id, exam_id, state, seq, leave_count, flagged, deadline, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(attempt_id) DO UPDATE SET state = excluded.state, seq = MAX(attempts.seq, excluded.seq),
             leave_count = MAX(attempts.leave_count, excluded.leave_count), deadline = excluded.deadline, updated_at = excluded.updated_at,
             flagged = CASE WHEN attempts.flagged_dirty = 1 THEN attempts.flagged ELSE excluded.flagged END''',
        [attemptId, examId, jsonEncode(copy), seq, localLeaves > serverLeaves ? localLeaves : serverLeaves, jsonEncode(state['flagged'] ?? const []), state['deadline'], _now],
      );
      for (final e in answers.entries) {
        _db.execute(
          '''INSERT INTO answers (attempt_id, qid, value, dirty, changed_at) VALUES (?, ?, ?, 0, ?)
             ON CONFLICT(attempt_id, qid) DO UPDATE SET value = excluded.value WHERE answers.dirty = 0''',
          [attemptId, e.key, '${e.value}', _now],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, dynamic>? attemptState(String attemptId) {
    final r = _db.select('SELECT state FROM attempts WHERE attempt_id = ?', [attemptId]);
    return r.isEmpty ? null : jsonDecode(r.first['state'] as String) as Map<String, dynamic>;
  }

  ({int seq, int leaveCount, List<String> flagged, bool flaggedDirty, int? deadline}) attemptMeta(String attemptId) {
    final r = _db.select('SELECT seq, leave_count, flagged, flagged_dirty, deadline FROM attempts WHERE attempt_id = ?', [attemptId]);
    if (r.isEmpty) return (seq: 0, leaveCount: 0, flagged: <String>[], flaggedDirty: false, deadline: null);
    final row = r.first;
    return (
      seq: row['seq'] as int,
      leaveCount: row['leave_count'] as int,
      flagged: (jsonDecode(row['flagged'] as String) as List).cast<String>(),
      flaggedDirty: row['flagged_dirty'] == 1,
      deadline: row['deadline'] as int?,
    );
  }

  void setDeadline(String attemptId, int? deadline) => _db.execute('UPDATE attempts SET deadline = ? WHERE attempt_id = ?', [deadline, attemptId]);

  // ---------------------------------------------------------------- jawaban

  /// Jawaban lokal (yang dihapus tidak ikut).
  Map<String, String> answers(String attemptId) => {
    for (final r in _db.select('SELECT qid, value FROM answers WHERE attempt_id = ? AND value IS NOT NULL', [attemptId])) r['qid'] as String: r['value'] as String,
  };

  /// [value] null = jawaban dihapus.
  void setAnswer(String attemptId, String qid, String? value) => _db.execute(
    '''INSERT INTO answers (attempt_id, qid, value, dirty, changed_at) VALUES (?, ?, ?, 1, ?)
           ON CONFLICT(attempt_id, qid) DO UPDATE SET value = excluded.value, dirty = 1, changed_at = excluded.changed_at''',
    [attemptId, qid, value, _now],
  );

  void setFlagged(String attemptId, List<String> flagged) => _db.execute('UPDATE attempts SET flagged = ?, flagged_dirty = 1 WHERE attempt_id = ?', [jsonEncode(flagged), attemptId]);

  /// Pelanggaran (keluar aplikasi / split-screen) — hanya bertambah.
  int addLeave(String attemptId) {
    _db.execute('UPDATE attempts SET leave_count = leave_count + 1 WHERE attempt_id = ?', [attemptId]);
    return attemptMeta(attemptId).leaveCount;
  }

  /// Perubahan yang belum tersinkron: dijawab, dihapus, dan waktu perubahan terakhir (untuk menandai tersinkron).
  ({Map<String, String> answers, List<String> cleared, int upTo}) dirty(String attemptId) {
    final rows = _db.select('SELECT qid, value, changed_at FROM answers WHERE attempt_id = ? AND dirty = 1', [attemptId]);
    final answers = <String, String>{};
    final cleared = <String>[];
    var upTo = 0;
    for (final r in rows) {
      final v = r['value'] as String?;
      v == null ? cleared.add(r['qid'] as String) : answers[r['qid'] as String] = v;
      final t = r['changed_at'] as int;
      if (t > upTo) upTo = t;
    }
    return (answers: answers, cleared: cleared, upTo: upTo);
  }

  /// Tandai tersinkron hanya perubahan sampai [upTo] — yang diubah selama permintaan berjalan tetap dirty.
  void markSynced(String attemptId, int seq, int upTo, {required bool flaggedSent}) {
    _db.execute('BEGIN');
    _db.execute('UPDATE answers SET dirty = 0 WHERE attempt_id = ? AND dirty = 1 AND changed_at <= ?', [attemptId, upTo]);
    _db.execute('UPDATE attempts SET seq = MAX(seq, ?) ${flaggedSent ? ', flagged_dirty = 0' : ''} WHERE attempt_id = ?', [seq, attemptId]);
    _db.execute('COMMIT');
  }

  void setSeq(String attemptId, int seq) => _db.execute('UPDATE attempts SET seq = MAX(seq, ?) WHERE attempt_id = ?', [seq, attemptId]);

  // ---------------------------------------------------------------- outbox kumpul

  void queueSubmit(String attemptId, Map<String, dynamic> payload) => _db.execute('INSERT OR REPLACE INTO submits VALUES (?, ?, ?)', [attemptId, jsonEncode(payload), _now]);

  Map<String, Map<String, dynamic>> pendingSubmits() => {
    for (final r in _db.select('SELECT attempt_id, payload FROM submits')) r['attempt_id'] as String: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
  };

  /// Percobaan selesai: hapus jawaban & antrean lokalnya (paket soal tetap untuk ujian berikutnya bila diperlukan).
  void finishAttempt(String attemptId) {
    _db.execute('BEGIN');
    _db.execute('DELETE FROM submits WHERE attempt_id = ?', [attemptId]);
    _db.execute('DELETE FROM answers WHERE attempt_id = ?', [attemptId]);
    _db.execute('DELETE FROM attempts WHERE attempt_id = ?', [attemptId]);
    _db.execute('COMMIT');
  }

  // ---------------------------------------------------------------- cache HTTP (ETag)

  ({String etag, String body})? cached(String key) {
    final r = _db.select('SELECT etag, body FROM http_cache WHERE key = ?', [key]);
    return r.isEmpty ? null : (etag: r.first['etag'] as String, body: r.first['body'] as String);
  }

  void saveCache(String key, String etag, String body) => _db.execute('INSERT OR REPLACE INTO http_cache VALUES (?, ?, ?, ?)', [key, etag, body, _now]);

  void clearCache() => _db.execute('DELETE FROM http_cache');
}
