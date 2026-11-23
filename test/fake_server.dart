import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:smartlms/core/api/api_client.dart';
import 'package:smartlms/core/storage/secure_store.dart';

/// Balasan palsu: status + body JSON (+ header). `null` = gagal jaringan.
typedef FakeReply = ({int status, Object? body, Map<String, String> headers})?;

FakeReply reply(int status, [Object? body, Map<String, String> headers = const {}]) => (status: status, body: body, headers: headers);

/// Adapter Dio di memori: setiap permintaan dicatat & dijawab oleh [handler].
class FakeServer implements HttpClientAdapter {
  FakeServer(this.handler);

  FakeReply Function(RequestOptions req) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final r = handler(options);
    if (r == null) throw DioException.connectionError(requestOptions: options, reason: 'offline (uji)');
    final headers = {
      for (final h in r.headers.entries) h.key: [h.value],
      if (r.body != null) Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    return ResponseBody.fromString(r.body == null ? '' : jsonEncode(r.body), r.status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, SecureStore, FakeServer)> fakeClient(FakeReply Function(RequestOptions req) handler, {void Function()? onExpired}) async {
  final server = FakeServer(handler);
  final store = SecureStore(MemoryKeyValueStore());
  final api = ApiClient(
    baseUrl: 'http://uji/api/v1/mobile',
    store: store,
    platform: 'android',
    appVersion: '1.0.0',
    adapter: server,
    onSessionExpired: onExpired,
    retryDelays: const [Duration(milliseconds: 1), Duration(milliseconds: 1), Duration(milliseconds: 1)],
  );
  return (api, store, server);
}
