import 'package:dio/dio.dart' show RequestOptions;

import 'fake_server.dart';

/// Data palsu berbentuk respons server /api/v1/mobile (dipakai smoke test & test visual).
final _subject = {'code': 'IF101', 'name': 'Algoritma & Pemrograman yang Namanya Cukup Panjang'};
Map<String, dynamic> _exam(String id, String state, {String kind = 'KUIS', String? mobile}) => {
      'id': id,
      'title': 'Ujian $id dengan judul yang cukup panjang untuk diuji',
      'kind': kind,
      'category': null,
      'workType': 'QUIZ',
      'subject': _subject,
      'startAt': null,
      'endAt': 1_800_000_000_000,
      'dueAt': null,
      'timed': true,
      'durationMinutes': 20,
      'questionCount': 10,
      'maxAttempts': 3,
      'attempts': state == 'done' ? 1 : 0,
      'state': state,
      'best': state == 'done' ? 85 : null,
      'pendingScore': false,
      'passingScore': 70,
      'mobile': mobile ?? 'ok',
    };

final fakeClass = {'id': 'k1', 'name': 'IF-1A', 'description': 'Informatika angkatan 2024 kelas A', 'term': '2026/2027 Ganjil', 'owner': 'Dr. Rina Kartika', 'subject': _subject, 'members': 30, 'status': 'ACTIVE'};

FakeReply fakeRoute(RequestOptions req) {
  final path = req.uri.path.replaceFirst('/api/v1/mobile', '');
  return switch (path) {
    '/config' => reply(200, {'minVersion': null, 'maintenance': false, 'now': 1_700_000_000_000}),
    '/site' => reply(200, {'name': 'SmartTest', 'theme': {'light': {}, 'dark': {}}, 'logo': {'light': null, 'dark': null}, 'texts': <String, String>{}, 'registrationOpen': true}),
    '/me' => reply(200, {
        'user': {'id': 'u1', 'name': 'Peserta Uji Coba', 'email': 'trial@smarttest.local', 'username': 'trial.mobile', 'role': 'PESERTA', 'mustChangePassword': false},
        'nav': [
          {'title': null, 'items': [{'href': '/dashboard', 'label': 'Dashboard'}, {'href': '/kelas', 'label': 'Kelas'}]},
          {'title': 'Ujian', 'items': [{'href': '/ujian', 'label': 'Ujian Saya'}, {'href': '/hasil', 'label': 'Hasil Ujian'}]},
          {'title': 'Akun', 'items': [{'href': '/profil', 'label': 'Profil & Password'}]},
        ],
        'features': ['kelas.gabung', 'hasil.lihat'],
      }),
    '/dashboard' => reply(200, {
        'classes': [fakeClass, {...fakeClass, 'id': 'k2', 'name': 'IF-1B', 'status': 'PENDING'}],
        'stats': {'available': 2, 'upcoming': 1, 'mean': 82.5, 'scored': 2},
        'exams': [_exam('e1', 'available', kind: 'TRYOUT'), _exam('e2', 'running', kind: 'LATIHAN'), _exam('e3', 'upcoming', mobile: 'integrity_required')],
        'posts': [{'id': 'm1', 'kind': 'MATERI', 'title': 'Materi rekursi', 'classId': 'k1', 'className': 'IF-1A', 'publishedAt': 1_700_000_000_000, 'examId': null, 'dueAt': null}],
      }),
    '/exams' => reply(200, {'exams': [_exam('e1', 'available'), _exam('e2', 'running'), _exam('e3', 'upcoming'), _exam('e4', 'done'), _exam('e5', 'missed', mobile: 'not_allowed')], 'now': 1}),
    '/exams/e1' => reply(200, {
        'exam': {
          ..._exam('e1', 'available'),
          'instructions': 'Kerjakan dengan jujur. Matikan notifikasi aplikasi lain sebelum memulai ujian ini.',
          'questionsPerPage': 2,
          'maxLeaves': 3,
          'showScore': true,
          'needsToken': true,
          'sessionActive': true,
          'window': 'open',
          'rules': [{'text': 'Terdiri dari 10 soal; waktu pengerjaan 20 menit dihitung sejak tombol Mulai ditekan.', 'source': 'system'}, {'text': 'Dilarang bekerja sama.', 'source': 'author'}],
        },
        'running': null,
        'attempts': [{'id': 'a0', 'no': 1, 'status': 'GRADED', 'score': 90, 'submittedAt': 1_700_000_000_000}],
        'package': null,
        'now': 1,
      }),
    '/classes/k1/posts' => reply(200, {
        'topics': [{'id': 't1', 'name': 'Minggu 1 — Pengantar'}],
        'posts': [
          {'id': 'm1', 'kind': 'MATERI', 'title': 'Materi rekursi', 'content': 'Isi', 'topicId': 't1', 'publishedAt': 1, 'attachments': [{'id': 'f1', 'type': 'FILE', 'name': 'a.pdf', 'url': '/x', 'mimeType': 'application/pdf', 'size': 2048}], 'work': null, 'comments': 0, 'done': true},
          {'id': 'm2', 'kind': 'TUGAS', 'title': 'Tugas ERD', 'content': null, 'topicId': null, 'publishedAt': 1, 'attachments': [], 'work': {'examId': 'e9', 'workType': 'ASSIGNMENT', 'dueAt': 1_800_000_000_000, 'maxPoints': 100, 'statuses': []}, 'comments': 2, 'done': false},
        ],
      }),
    '/materials/m1' => reply(200, {
        'id': 'm1', 'classId': 'k1', 'kind': 'MATERI', 'title': 'Materi rekursi', 'content': 'Rekursi adalah fungsi yang memanggil dirinya sendiri.', 'topic': 'Minggu 1', 'publishedAt': 1,
        'attachments': [{'id': 'f1', 'type': 'FILE', 'name': 'ringkasan-rekursi-yang-sangat-panjang-sekali.pdf', 'url': '/x', 'mimeType': 'application/pdf', 'size': 20480}, {'id': 'l1', 'type': 'YOUTUBE', 'name': 'Video', 'url': 'https://youtu.be/x', 'mimeType': null, 'size': null}],
        'work': null, 'done': false, 'comments': 0,
      }),
    _ => reply(200, {'exams': <Object>[], 'now': 1}),
  };
}

