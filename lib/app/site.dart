import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import 'providers.dart';

/// Tampilan situs dari web (Administrasi → Tampilan Situs): nama, warna tema, logo, teks.
/// Disimpan lokal sehingga aplikasi tetap tampil sama saat offline.
class SiteConfig {
  const SiteConfig({this.name = 'SmartTest', this.light = const {}, this.dark = const {}, this.logoLight, this.logoDark, this.texts = const {}, this.registrationOpen = true});

  final String name;

  /// Warna yang diubah Super Admin (primary/secondary/accent/background, #RRGGBB). Kosong = bawaan web.
  final Map<String, String> light;
  final Map<String, String> dark;
  final String? logoLight;
  final String? logoDark;
  final Map<String, String> texts;
  final bool registrationOpen;

  /// Teks situs; bawaan sama dengan src/content/texts.ts di web.
  String t(String key, [Map<String, Object>? vars]) {
    var s = texts[key] ?? _defaults[key] ?? key;
    vars?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// URL absolut logo (path relatif /branding/... dari server).
  String? logoUrl({required bool dark}) {
    final path = dark ? (logoDark ?? logoLight) : (logoLight ?? logoDark);
    return path == null ? null : '${AppConfig.apiBase}$path';
  }

  factory SiteConfig.fromJson(Map<String, dynamic> j) {
    Map<String, String> colors(Object? v) => (v as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    final theme = j['theme'] as Map? ?? const {};
    final logo = j['logo'] as Map? ?? const {};
    return SiteConfig(
      name: j['name'] as String? ?? 'SmartTest',
      light: colors(theme['light']),
      dark: colors(theme['dark']),
      logoLight: logo['light'] as String?,
      logoDark: logo['dark'] as String?,
      texts: (j['texts'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      registrationOpen: j['registrationOpen'] != false,
    );
  }

  static const _defaults = {
    'app.name': 'SmartTest',
    'login.title': 'Selamat datang 👋',
    'login.subtitle': 'Masuk untuk mengelola atau mengerjakan ujian.',
    'login.cta': 'Masuk',
    'dashboard.greeting': 'Selamat datang kembali',
    'dashboard.participant.available': 'Ada {n} ujian yang bisa Anda kerjakan sekarang. Semoga sukses!',
    'dashboard.participant.idle': 'Belum ada ujian yang dibuka saat ini.',
    'dashboard.participant.cta': 'Kerjakan sekarang',
    'nav.dashboard': 'Dashboard',
    'nav.kelas': 'Kelas',
    'nav.section.ujian': 'Ujian',
    'nav.ujian': 'Ujian Saya',
    'nav.hasil': 'Hasil Ujian',
    'nav.section.akun': 'Akun',
    'nav.profil': 'Profil & Password',
    'role.PESERTA': 'Peserta',
  };
}

class SiteController extends Notifier<SiteConfig> {
  static const _cacheKey = 'site';

  @override
  SiteConfig build() {
    final db = ref.read(servicesProvider).db;
    final cached = db.cached(_cacheKey);
    Future.microtask(refresh);
    return cached == null ? const SiteConfig() : SiteConfig.fromJson(jsonDecode(cached.body) as Map<String, dynamic>);
  }

  /// Ambil ulang dari server (ETag → 304 bila tidak berubah). Gagal jaringan: tetap memakai salinan lokal.
  Future<void> refresh() async {
    final s = ref.read(servicesProvider);
    final cached = s.db.cached(_cacheKey);
    try {
      final res = await s.api.send<Map<String, dynamic>>('GET', '/site', auth: false, headers: {if (cached != null) 'If-None-Match': cached.etag});
      if (res.statusCode == 304) return;
      s.db.saveCache(_cacheKey, res.headers.value('etag') ?? '-', jsonEncode(res.data));
      state = SiteConfig.fromJson(res.data!);
    } on ApiException {
      // offline
    }
  }
}

final siteProvider = NotifierProvider<SiteController, SiteConfig>(SiteController.new);
