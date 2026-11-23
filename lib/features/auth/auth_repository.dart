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

  Future<AppUser> me() async => AppUser.fromJson((await api.getJson('/me'))['user'] as Map<String, dynamic>);

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
