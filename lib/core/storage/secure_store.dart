import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan kunci-nilai kecil yang rahasia (Android Keystore / iOS Keychain).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore() : _s = const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String? value) => value == null ? _s.delete(key: key) : _s.write(key: key, value: value);
}

/// Untuk uji: di memori.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? data.remove(key) : data[key] = value;
}

/// Rahasia aplikasi: id perangkat, token sesi, kunci database lokal.
class SecureStore {
  SecureStore(this._kv);
  final KeyValueStore _kv;

  static const _deviceId = 'device_id';
  static const _access = 'access_token';
  static const _refresh = 'refresh_token';
  static const _dbKey = 'db_key';

  static String _random(int bytes) {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  /// Id perangkat rahasia (dibuat sekali per instalasi). Server memakai hash-nya untuk
  /// kunci perangkat ujian & mengikat refresh token — jangan pernah ditampilkan/dibagikan.
  Future<String> deviceId() async {
    final existing = await _kv.read(_deviceId);
    if (existing != null) return existing;
    final id = _random(32);
    await _kv.write(_deviceId, id);
    return id;
  }

  /// Kunci enkripsi database lokal (hex 64 karakter).
  Future<String> databaseKey() async {
    final existing = await _kv.read(_dbKey);
    if (existing != null) return existing;
    final r = Random.secure();
    final key = List<int>.generate(32, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _kv.write(_dbKey, key);
    return key;
  }

  Future<String?> accessToken() => _kv.read(_access);
  Future<String?> refreshToken() => _kv.read(_refresh);

  Future<void> saveTokens(String access, String refresh) async {
    await _kv.write(_access, access);
    await _kv.write(_refresh, refresh);
  }

  Future<void> clearTokens() async {
    await _kv.write(_access, null);
    await _kv.write(_refresh, null);
  }
}
