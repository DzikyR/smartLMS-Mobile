import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/local_db.dart';

/// Data dari cache lokal bila server menjawab 304 atau sedang offline.
class Cached<T> {
  Cached(this.data, {required this.stale});
  final T data;

  /// true = offline, ini data terakhir yang tersimpan.
  final bool stale;
}

/// LMS (baca): dashboard, postingan kelas, materi, berkas lampiran — semua ber-ETag
/// sehingga data yang tidak berubah tidak diunduh ulang (hemat kuota) dan tetap tampil saat offline.
class LmsRepository {
  LmsRepository(this.api, this.db, this.cacheDir);

  final ApiClient api;
  final LocalDb db;
  final Directory cacheDir;

  Future<Cached<Map<String, dynamic>>> _get(String path) async {
    final c = db.cached(path);
    try {
      final res = await api.send<Map<String, dynamic>>('GET', path, headers: c != null ? {'If-None-Match': c.etag} : null);
      if (res.statusCode == 304 && c != null) return Cached(jsonDecode(c.body) as Map<String, dynamic>, stale: false);
      final etag = res.headers.value('etag');
      if (etag != null) db.saveCache(path, etag, jsonEncode(res.data));
      return Cached(Map<String, dynamic>.from(res.data!), stale: false);
    } on ApiException catch (e) {
      if (e.isNetwork && c != null) return Cached(jsonDecode(c.body) as Map<String, dynamic>, stale: true);
      rethrow;
    }
  }

  Future<Cached<Map<String, dynamic>>> dashboard() => _get('/dashboard');

  Future<Cached<Map<String, dynamic>>> classPosts(String classId) => _get('/classes/$classId/posts');

  Future<Map<String, dynamic>> material(String id) => api.getJson('/materials/$id');

  Future<void> setDone(String id, bool done) => api.postJson('/materials/$id', {'done': done}, retry: true);

  /// Unduh lampiran ke cache aplikasi. Berkas dengan ETag yang sama tidak diunduh ulang.
  Future<File> downloadAttachment(String attachmentId, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final file = File('${cacheDir.path}/lampiran/$attachmentId/$safe');
    final meta = db.cached('file:$attachmentId');
    final exists = await file.exists();
    final res = await api.send<List<int>>('GET', '/files/$attachmentId', responseType: ResponseType.bytes, headers: {if (exists && meta != null) 'If-None-Match': meta.etag});
    if (res.statusCode == 304 && exists) return file;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(res.data!, flush: true);
    final etag = res.headers.value('etag');
    if (etag != null) db.saveCache('file:$attachmentId', etag, file.path);
    return file;
  }
}
