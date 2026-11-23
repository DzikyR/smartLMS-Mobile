import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../features/auth/auth_repository.dart';
import 'services.dart';

/// Disuntikkan di main.dart (ProviderScope overrides).
final servicesProvider = Provider<AppServices>((ref) => throw UnimplementedError('servicesProvider belum di-override'));

/// true selama lembar ujian terbuka: notifikasi tidak ditampilkan & tidak menavigasi.
final examActiveProvider = StateProvider<bool>((ref) => false);

enum AuthStatus { loading, signedOut, signedIn, upgrade, maintenance }

class AuthState {
  const AuthState(this.status, {this.user, this.notice, this.upgrade});

  final AuthStatus status;
  final AppUser? user;

  /// Pesan untuk layar login (mis. "Sesi berakhir").
  final String? notice;

  /// Info force update dari server: minVersion, storeUrl, message.
  final Map<String, dynamic>? upgrade;
}

/// "1.2.10" < "1.3.0"? (versi tidak sah dianggap paling lama) — sama dengan versionLess di server.
bool versionLess(String a, String b) {
  List<int>? parse(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  final x = parse(a), y = parse(b);
  if (y == null) return false;
  if (x == null) return true;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] < y[i];
  }
  return false;
}

class AuthController extends Notifier<AuthState> {
  static const _meCache = 'me';

  AppServices get _s => ref.read(servicesProvider);

  @override
  AuthState build() {
    AppServices.sessionExpired = () => state = const AuthState(AuthStatus.signedOut, notice: 'Sesi berakhir. Silakan masuk kembali.');
    AppServices.upgradeRequired = (info) => state = AuthState(AuthStatus.upgrade, upgrade: info);
    Future.microtask(_boot);
    return const AuthState(AuthStatus.loading);
  }

  Future<void> _boot() async {
    final s = _s;
    // Konfigurasi publik: force update, mode perawatan, jam server.
    try {
      final cfg = await s.api.getJson('/config');
      await s.clock.sync(cfg['now'] as int);
      final min = cfg['minVersion'] as String?;
      if (min != null && versionLess(s.appVersion, min)) {
        state = AuthState(AuthStatus.upgrade, upgrade: cfg);
        return;
      }
      if (cfg['maintenance'] == true) {
        state = AuthState(AuthStatus.maintenance, notice: cfg['message'] as String? ?? 'Aplikasi sedang dalam perawatan.');
        return;
      }
    } on ApiException {
      // offline: lanjut dengan data lokal
    }
    // Antrean kumpul ujian yang tertunda dikirim secepatnya.
    s.exams.flushPending();
    if (!await s.auth.hasSession()) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    try {
      final me = await s.auth.me();
      s.db.saveCache(_meCache, '-', jsonEncode(_userJson(me)));
      state = AuthState(AuthStatus.signedIn, user: me);
    } on ApiException catch (e) {
      final cached = s.db.cached(_meCache);
      if (e.isNetwork && cached != null) {
        // Offline (mis. di tengah ujian): pakai profil terakhir; jawaban tetap tersimpan lokal.
        state = AuthState(AuthStatus.signedIn, user: AppUser.fromJson(jsonDecode(cached.body) as Map<String, dynamic>));
      } else if (e.isNetwork) {
        state = const AuthState(AuthStatus.signedOut, notice: 'Tidak ada koneksi. Sambungkan internet untuk masuk.');
      } else if (state.status != AuthStatus.upgrade) {
        state = const AuthState(AuthStatus.signedOut);
      }
    }
  }

  Map<String, dynamic> _userJson(AppUser u) =>
      {'id': u.id, 'name': u.name, 'email': u.email, 'username': u.username, 'role': u.role, 'mustChangePassword': u.mustChangePassword};

  Future<void> login(String identifier, String password) async {
    final user = await _s.auth.login(identifier, password);
    _s.db.saveCache(_meCache, '-', jsonEncode(_userJson(user)));
    state = AuthState(AuthStatus.signedIn, user: user);
  }

  Future<void> changePassword(String current, String next) async {
    await _s.auth.changePassword(current, next);
    final me = await _s.auth.me();
    _s.db.saveCache(_meCache, '-', jsonEncode(_userJson(me)));
    state = AuthState(AuthStatus.signedIn, user: me);
  }

  Future<void> logout() async {
    await _s.auth.logout();
    state = const AuthState(AuthStatus.signedOut);
  }

  Future<void> retry() async {
    state = const AuthState(AuthStatus.loading);
    await _boot();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
