import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../storage/secure_store.dart';

/// Kesalahan API dengan kode stabil dari server (`error`), lihat docs/API-MOBILE.md di repo web.
class ApiException implements Exception {
  ApiException({required this.status, required this.code, required this.message, this.data = const {}});

  /// null = gagal jaringan (tidak ada respons).
  final int? status;
  final String code;
  final String message;
  final Map<String, dynamic> data;

  bool get isNetwork => status == null;

  /// Pesan per field dari error VALIDATION.
  Map<String, String> get fields => (data['fields'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {};

  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    if (res == null) {
      return ApiException(status: null, code: 'NETWORK', message: 'Tidak ada koneksi ke server. Periksa sinyal/internet Anda.');
    }
    final body = res.data;
    if (body is Map && body['error'] is String) {
      return ApiException(status: res.statusCode, code: body['error'] as String, message: '${body['message'] ?? 'Terjadi kesalahan.'}', data: Map<String, dynamic>.from(body));
    }
    return ApiException(status: res.statusCode, code: 'HTTP_${res.statusCode}', message: 'Server sedang bermasalah (${res.statusCode}). Coba lagi.');
  }

  @override
  String toString() => 'ApiException($status $code: $message)';
}

typedef SessionExpired = void Function();
typedef UpgradeRequired = void Function(Map<String, dynamic> info);

/// Klien HTTP aplikasi:
///  - header perangkat (X-Device-Id, X-Platform, X-App-Version) di setiap permintaan;
///  - Bearer token + refresh otomatis SEKALI saat 401 (satu refresh untuk semua permintaan yang gagal bersamaan);
///  - coba ulang dengan jeda bertambah + jitter untuk gangguan jaringan/5xx/429 pada permintaan yang aman diulang.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.store,
    required this.platform,
    required this.appVersion,
    this.onSessionExpired,
    this.onUpgradeRequired,
    HttpClientAdapter? adapter,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 8)],
  }) {
    BaseOptions options() => BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      // 304 = pakai cache lokal (ETag), bukan error.
      validateStatus: (s) => s != null && (s < 300 || s == 304),
    );
    dio = Dio(options());
    _bare = Dio(options());
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      _bare.httpClientAdapter = adapter;
    }
    dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
    _bare.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          o.headers.addAll(await _deviceHeaders());
          h.next(o);
        },
      ),
    );
  }

  final SecureStore store;
  final String platform;
  final String appVersion;
  final SessionExpired? onSessionExpired;
  final UpgradeRequired? onUpgradeRequired;
  final List<Duration> retryDelays;

  late final Dio dio;
  late final Dio _bare;
  Future<bool>? _refreshing;
  final _random = Random();

  Future<Map<String, String>> _deviceHeaders() async => {'X-Device-Id': await store.deviceId(), 'X-Platform': platform, 'X-App-Version': appVersion};

  Future<void> _onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    o.headers.addAll(await _deviceHeaders());
    final token = await store.accessToken();
    if (token != null && o.extra['noAuth'] != true) o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final res = e.response;
    final code = res?.data is Map ? (res!.data as Map)['error'] : null;
    if (res?.statusCode == 426 && res?.data is Map) onUpgradeRequired?.call(Map<String, dynamic>.from(res!.data as Map));
    if (res?.statusCode != 401 || code != 'UNAUTHENTICATED' || e.requestOptions.extra['retried'] == true || e.requestOptions.extra['noAuth'] == true) {
      return h.next(e);
    }
    final refreshed = await refreshSession();
    if (!refreshed) return h.next(e);
    try {
      final retry = e.requestOptions..extra['retried'] = true;
      retry.headers['Authorization'] = 'Bearer ${await store.accessToken()}';
      h.resolve(await dio.fetch(retry));
    } on DioException catch (again) {
      h.next(again);
    }
  }

  /// Tukar refresh token (rotasi). Satu permintaan untuk semua pemanggil yang bersamaan.
  /// false bila sesi berakhir (pengguna diarahkan ke login) atau jaringan gagal (sesi TIDAK dihapus).
  Future<bool> refreshSession() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final refresh = await store.refreshToken();
    if (refresh == null) return false;
    try {
      final res = await _bare.post<Map<String, dynamic>>('/auth/refresh', data: {'refreshToken': refresh});
      await store.saveTokens(res.data!['accessToken'] as String, res.data!['refreshToken'] as String);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await store.clearTokens();
        onSessionExpired?.call();
      }
      return false;
    }
  }

  static bool _transient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final body = e.response?.data;
        final maintenance = body is Map && body['error'] == 'MAINTENANCE';
        return const [429, 502, 503, 504].contains(status) && !maintenance;
      default:
        return false;
    }
  }

  Duration _delay(int attempt, DioException e) {
    final retryAfter = int.tryParse(e.response?.headers.value('retry-after') ?? '');
    final base = retryAfter != null ? Duration(seconds: retryAfter) : retryDelays[attempt];
    // Jitter ±30%: ratusan HP yang putus bersamaan tidak menyerbu server di detik yang sama.
    return base * (0.7 + _random.nextDouble() * 0.6);
  }

  /// Kirim permintaan. [retry] hanya untuk permintaan yang aman diulang (GET, simpan delta
  /// bernomor urut, kumpul ujian — semuanya idempotent di server).
  Future<Response<T>> send<T>(String method, String path, {Object? data, Map<String, String>? headers, bool? retry, ResponseType? responseType, bool auth = true}) async {
    final canRetry = retry ?? method == 'GET';
    for (var attempt = 0; ; attempt++) {
      try {
        return await dio.request<T>(
          path,
          data: data,
          options: Options(method: method, headers: headers, responseType: responseType, extra: {if (!auth) 'noAuth': true}),
        );
      } on DioException catch (e) {
        if (!canRetry || !_transient(e) || attempt >= retryDelays.length) throw ApiException.fromDio(e);
        await Future<void>.delayed(_delay(attempt, e));
      }
    }
  }

  Future<Map<String, dynamic>> getJson(String path) async => Map<String, dynamic>.from((await send<Map<String, dynamic>>('GET', path)).data!);

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {bool retry = false, bool auth = true}) async =>
      Map<String, dynamic>.from((await send<Map<String, dynamic>>('POST', path, data: body, retry: retry, auth: auth)).data ?? const {});

  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body, {bool retry = false}) async =>
      Map<String, dynamic>.from((await send<Map<String, dynamic>>('PUT', path, data: body, retry: retry)).data ?? const {});
}
