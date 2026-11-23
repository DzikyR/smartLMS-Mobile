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

/// Menu bawaan (sama dengan sidebar web untuk Peserta) bila /me belum pernah termuat.
final defaultNav = [
  NavSection(null, [(href: '/dashboard', label: 'Dashboard'), (href: '/kelas', label: 'Kelas')]),
  NavSection('Ujian', [(href: '/ujian', label: 'Ujian Saya'), (href: '/hasil', label: 'Hasil Ujian')]),
  NavSection('Akun', [(href: '/profil', label: 'Profil & Password')]),
];

class AuthState {
  const AuthState(this.status, {this.user, this.notice, this.upgrade, this.nav, this.features = const []});

  final AuthStatus status;
  final AppUser? user;

  /// Pesan untuk layar login (mis. "Sesi berakhir").
  final String? notice;

  /// Info force update dari server: minVersion, storeUrl, message.
  final Map<String, dynamic>? upgrade;

  final List<NavSection>? nav;
  final List<String> features;

  List<NavSection> get menu => nav ?? defaultNav;
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
      _signedIn(await s.auth.me());
    } on ApiException catch (e) {
      final cached = s.db.cached(_meCache);
      if (e.isNetwork && cached != null) {
        // Offline (mis. di tengah ujian): pakai profil & menu terakhir; jawaban tetap tersimpan lokal.
        final j = jsonDecode(cached.body) as Map<String, dynamic>;
        state = AuthState(
          AuthStatus.signedIn,
          user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
          nav: NavSection.listFrom(j['nav']),
          features: (j['features'] as List? ?? const []).cast<String>(),
        );
      } else if (e.isNetwork) {
        state = const AuthState(AuthStatus.signedOut, notice: 'Tidak ada koneksi. Sambungkan internet untuk masuk.');
      } else if (state.status != AuthStatus.upgrade) {
        state = const AuthState(AuthStatus.signedOut);
      }
    }
  }

  void _signedIn(MeData me) {
    final u = me.user;
    _s.db.saveCache(
      _meCache,
      '-',
      jsonEncode({
        'user': {'id': u.id, 'name': u.name, 'email': u.email, 'username': u.username, 'role': u.role, 'mustChangePassword': u.mustChangePassword},
        'nav': [for (final s in me.nav) s.toJson()],
        'features': me.features,
      }),
    );
    state = AuthState(AuthStatus.signedIn, user: u, nav: me.nav, features: me.features);
  }

  Future<void> login(String identifier, String password) async {
    await _s.auth.login(identifier, password);
    _signedIn(await _s.auth.me());
  }

  Future<void> changePassword(String current, String next) async {
    await _s.auth.changePassword(current, next);
    _signedIn(await _s.auth.me());
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
