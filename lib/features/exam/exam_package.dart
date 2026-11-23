import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Soal dari paket (tanpa kunci jawaban).
class PackageQuestion {
  PackageQuestion({required this.id, required this.type, required this.prompt, required this.options, required this.points});

  final String id;

  /// MULTIPLE_CHOICE | TRUE_FALSE | SHORT_ANSWER | ESSAY
  final String type;
  final String prompt;
  final List<({String id, String text})> options;
  final double points;

  factory PackageQuestion.fromJson(Map<String, dynamic> j) => PackageQuestion(
    id: j['id'] as String,
    type: j['type'] as String,
    prompt: j['prompt'] as String,
    options: [for (final o in (j['options'] as List? ?? const [])) (id: o['id'] as String, text: o['text'] as String)],
    points: (j['points'] as num).toDouble(),
  );
}

class ExamPackage {
  ExamPackage({required this.version, required this.examId, required this.questions});
  final String version;
  final String examId;
  final List<PackageQuestion> questions;
}

/// Membuka paket soal dari server: [12 byte IV][ciphertext AES-256-GCM][16 byte tag], plaintext = gzip(JSON).
/// Sama dengan `openPackage` di smartTest/src/lib/mobile/package.ts. Gagal (kunci salah / isi diubah) → melempar.
Future<ExamPackage> openPackage(Uint8List blob, String keyBase64) async {
  if (blob.length < 12 + 16) throw const FormatException('paket soal rusak');
  final box = SecretBox(blob.sublist(12, blob.length - 16), nonce: blob.sublist(0, 12), mac: Mac(blob.sublist(blob.length - 16)));
  final clear = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(base64Decode(keyBase64)));
  final json = jsonDecode(utf8.decode(gzip.decode(clear))) as Map<String, dynamic>;
  return ExamPackage(version: json['v'] as String, examId: json['examId'] as String, questions: [for (final q in json['questions'] as List) PackageQuestion.fromJson(q as Map<String, dynamic>)]);
}

/// Urutan tampil peserta = `layout` dari server (diacak sekali saat Mulai, sama dengan web).
/// Soal yang tidak tercantum ditaruh di akhir; pilihan diurutkan menurut layout.options.
List<PackageQuestion> applyLayout(List<PackageQuestion> questions, Map<String, dynamic>? layout) {
  if (layout == null) return questions;
  final byId = {for (final q in questions) q.id: q};
  final order = (layout['questions'] as List? ?? const []).cast<String>();
  final options = (layout['options'] as Map? ?? const {}).map((k, v) => MapEntry('$k', (v as List).cast<String>()));
  final ordered = [
    for (final id in order)
      if (byId[id] != null) byId[id]!,
    ...questions.where((q) => !order.contains(q.id)),
  ];
  return [
    for (final q in ordered)
      if (options[q.id] case final opt?)
        PackageQuestion(id: q.id, type: q.type, prompt: q.prompt, points: q.points, options: [...q.options]..sort((a, b) => _rank(opt, a.id).compareTo(_rank(opt, b.id))))
      else
        q,
  ];
}

int _rank(List<String> order, String id) {
  final i = order.indexOf(id);
  return i == -1 ? 1 << 30 : i;
}
