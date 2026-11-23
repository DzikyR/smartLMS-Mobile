import '../../core/api/api_client.dart';
import '../../core/storage/local_db.dart';
import '../../core/storage/secure_store.dart';

class AppUser {
  AppUser({required this.id, required this.name, required this.email, required this.username, required this.role, required this.mustChangePassword});

  final String id;
  final String name;
  final String email;
  final String? username;
  final String role;
  final bool mustChangePassword;

  bool get isStudent => role == 'PESERTA';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: j['id'] as String,
    name: j['name'] as String,
    email: j['email'] as String,
    username: j['username'] as String?,
    role: j['role'] as String,
    mustChangePassword: j['mustChangePassword'] == true,
  );
}

/// Menu navigasi dari server (navFor() web: label Tampilan Situs + Kontrol Fitur).
class NavSection {
  NavSection(this.title, this.items);
  final String? title;
  final List<({String href, String label})> items;

  static List<NavSection> listFrom(Object? raw) => [
    for (final s in (raw as List? ?? const [])) NavSection(s['title'] as String?, [for (final i in (s['items'] as List)) (href: i['href'] as String, label: i['label'] as String)]),
  ];

  Map<String, dynamic> toJson() => {
    'title': title,
    'items': [
      for (final i in items) {'href': i.href, 'label': i.label},
    ],
  };
}

class MeData {
  MeData(this.user, this.nav, this.features);
  final AppUser user;
  final List<NavSection> nav;
  final List<String> features;
}

class AuthRepository {
  AuthRepository(this.api, this.store, this.db);

  final ApiClient api;
  final SecureStore store;
  final LocalDb db;

  Future<bool> hasSession() async => await store.refreshToken() != null;

  /// Login (aturan sama dengan web: kunci 5× gagal, rate limit). Melempar ApiException.
  Future<AppUser> login(String identifier, String password) async {
    final res = await api.postJson('/auth/login', {'identifier': identifier.trim(), 'password': password}, auth: false);
    await store.saveTokens(res['accessToken'] as String, res['refreshToken'] as String);
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<MeData> me() async {
    final r = await api.getJson('/me');
    return MeData(AppUser.fromJson(r['user'] as Map<String, dynamic>), NavSection.listFrom(r['nav']), (r['features'] as List? ?? const []).cast<String>());
  }

  /// Semua sesi lain dicabut server; perangkat ini langsung mendapat sesi baru.
  Future<void> changePassword(String current, String next) async {
    final res = await api.postJson('/auth/password', {'currentPassword': current, 'newPassword': next});
    await store.saveTokens(res['accessToken'] as String, res['refreshToken'] as String);
  }

  Future<void> logout() async {
    final refresh = await store.refreshToken();
    if (refresh != null) {
      try {
        await api.postJson('/auth/logout', {'refreshToken': refresh}, auth: false);
      } on ApiException {
        // offline: token tetap dihapus dari perangkat
      }
    }
    await store.clearTokens();
    db.clearCache();
  }
}
