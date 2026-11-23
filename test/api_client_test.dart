import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/core/api/api_client.dart';

import 'fake_server.dart';

void main() {
  test('header perangkat & Bearer dikirim di setiap permintaan', () async {
    final (api, store, server) = await fakeClient((_) => reply(200, {'ok': true}));
    await store.saveTokens('akses-1', 'rt_1');
    await api.getJson('/me');
    final h = server.requests.single.headers;
    expect(h['Authorization'], 'Bearer akses-1');
    expect(h['X-Platform'], 'android');
    expect(h['X-App-Version'], '1.0.0');
    expect(RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(h['X-Device-Id'] as String), isTrue);
    expect(h['X-Device-Id'], await store.deviceId(), reason: 'id perangkat stabil');
  });

  test('401 → refresh SEKALI untuk permintaan bersamaan, lalu diulang dengan token baru', () async {
    var refreshes = 0;
    final (api, store, server) = await fakeClient((req) {
      if (req.path.endsWith('/auth/refresh')) {
        refreshes++;
        return reply(200, {'accessToken': 'akses-2', 'refreshToken': 'rt_2', 'expiresIn': 900});
      }
      return req.headers['Authorization'] == 'Bearer akses-2' ? reply(200, {'path': req.path}) : reply(401, {'error': 'UNAUTHENTICATED', 'message': 'x'});
    });
    await store.saveTokens('akses-1', 'rt_1');
    final results = await Future.wait([api.getJson('/a'), api.getJson('/b'), api.getJson('/c')]);
    expect(results.map((r) => r['path']), ['/a', '/b', '/c']);
    expect(refreshes, 1);
    expect(await store.refreshToken(), 'rt_2', reason: 'refresh token hasil rotasi disimpan');
    expect(server.requests.where((r) => r.path.endsWith('/auth/refresh')).single.data, {'refreshToken': 'rt_1'});
  });

  test('refresh ditolak → token dihapus & sesi berakhir; refresh gagal jaringan → token tetap', () async {
    var expired = 0;
    var offline = false;
    final (api, store, _) = await fakeClient((req) {
      if (req.path.endsWith('/auth/refresh')) return offline ? null : reply(401, {'error': 'SESSION_INVALID', 'message': 'x'});
      return reply(401, {'error': 'UNAUTHENTICATED', 'message': 'Sesi berakhir.'});
    }, onExpired: () => expired++);
    await store.saveTokens('a', 'rt_1');
    offline = true;
    await expectLater(api.getJson('/me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHENTICATED')));
    expect(await store.refreshToken(), 'rt_1', reason: 'offline tidak boleh melogout peserta (mis. di tengah ujian)');
    expect(expired, 0);
    offline = false;
    await expectLater(api.getJson('/me'), throwsA(isA<ApiException>()));
    expect(await store.refreshToken(), isNull);
    expect(expired, 1);
  });

  test('gangguan sementara (offline/503) diulang untuk permintaan aman; POST biasa tidak', () async {
    var calls = 0;
    final (api, _, _) = await fakeClient((req) {
      calls++;
      if (calls == 1) return null;
      if (calls == 2) return reply(503, {'error': 'X', 'message': 'sibuk'});
      return reply(200, {'ok': true});
    });
    expect((await api.getJson('/dashboard'))['ok'], true);
    expect(calls, 3);

    calls = 0;
    await expectLater(api.postJson('/x', {}), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
    expect(calls, 1);
  });

  test('mode perawatan tidak diulang; 426 memicu force update; kode error terbaca', () async {
    Map<String, dynamic>? upgrade;
    final server = FakeServer((req) => req.path == '/old' ? reply(426, {'error': 'UPGRADE_REQUIRED', 'message': 'Perbarui', 'minVersion': '2.0.0'}) : reply(503, {'error': 'MAINTENANCE', 'message': 'Perawatan'}));
    final (api0, store, _) = await fakeClient((_) => null);
    final api = ApiClient(baseUrl: 'http://uji', store: store, platform: 'ios', appVersion: '1.0.0', adapter: server, onUpgradeRequired: (i) => upgrade = i, retryDelays: const [Duration.zero]);
    await expectLater(api.getJson('/m'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'MAINTENANCE')));
    expect(server.requests.length, 1);
    await expectLater(api.getJson('/old'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 426)));
    expect(upgrade?['minVersion'], '2.0.0');
    api0.dio.close();
  });
}
