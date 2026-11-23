import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/app/site.dart';
import 'package:smartlms/app/theme.dart';
import 'package:smartlms/core/config.dart';

/// Tampilan aplikasi mengikuti Administrasi → Tampilan Situs di web (GET /api/v1/mobile/site).
void main() {
  final site = SiteConfig.fromJson({
    'name': 'InfoTSU',
    'theme': {
      'light': {'primary': '#0f766e', 'background': '#fafafa'},
      'dark': {'primary': '#facc15'},
    },
    'logo': {'light': '/branding/logo-light?v=abc', 'dark': null},
    'texts': {'login.title': 'Masuk ke InfoTSU', 'nav.ujian': 'Ujian Kuliah', 'dashboard.participant.available': 'Ada {n} ujian dibuka'},
    'registrationOpen': false,
  });

  test('warna tema dari web; teks di atas primary dipilih agar kontras (seperti pickForeground web)', () {
    final light = Palette.of(Brightness.light, site);
    expect(light.primary, const Color(0xFF0F766E));
    expect(light.onPrimary, Colors.white);
    expect(light.background, const Color(0xFFFAFAFA));
    final dark = Palette.of(Brightness.dark, site);
    expect(dark.primary, const Color(0xFFFACC15));
    expect(dark.onPrimary, isNot(Colors.white), reason: 'kuning terang → teks gelap');
    expect(buildTheme(Brightness.light, site).colorScheme.primary, const Color(0xFF0F766E));
  });

  test('tanpa pengaturan / nilai rusak → warna bawaan web', () {
    expect(Palette.of(Brightness.light, const SiteConfig()).primary, const Color(0xFF5B4FE9));
    final broken = SiteConfig.fromJson({'theme': {'light': {'primary': 'red; }'}}});
    expect(Palette.of(Brightness.light, broken).primary, const Color(0xFF5B4FE9));
  });

  test('nama, logo, teks, & pendaftaran dari web', () {
    expect(site.name, 'InfoTSU');
    expect(site.logoUrl(dark: false), '${AppConfig.apiBase}/branding/logo-light?v=abc');
    expect(site.logoUrl(dark: true), '${AppConfig.apiBase}/branding/logo-light?v=abc', reason: 'mode gelap memakai logo terang bila tak ada');
    expect(site.t('nav.ujian'), 'Ujian Kuliah');
    expect(site.t('nav.hasil'), 'Hasil Ujian', reason: 'bawaan bila tidak diubah');
    expect(site.t('dashboard.participant.available', {'n': 3}), 'Ada 3 ujian dibuka');
    expect(site.registrationOpen, isFalse);
    expect(const SiteConfig().logoUrl(dark: false), isNull);
  });
}
