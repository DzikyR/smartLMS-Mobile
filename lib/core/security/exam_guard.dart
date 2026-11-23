import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Penjaga lembar ujian di perangkat:
///  - Android: FLAG_SECURE (screenshot/rekam layar = hitam), sembunyikan overlay aplikasi lain
///    (API 31+), screen pinning (startLockTask), deteksi split-screen.
///  - iOS: deteksi screenshot & rekam layar (layar soal ditutup).
///  - Semua: keluar aplikasi > 1,5 detik = pelanggaran (dikirim sebagai leaveCount, batasnya dari server).
/// Pengamanan ini menyulitkan, bukan mustahil ditembus — keputusan akhir tetap di server.
class ExamGuard {
  ExamGuard({required this.onViolation, required this.onCover});

  static const _ch = MethodChannel('smartlms/guard');

  /// [kind]: bg (keluar aplikasi), split, shot (screenshot), rec (rekam layar)
  final void Function(String kind) onViolation;

  /// true = tutup soal (aplikasi di belakang / sedang direkam / split-screen)
  final void Function(bool covered) onCover;

  AppLifecycleListener? _life;
  DateTime? _hiddenAt;

  Future<void> enable() async {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'multiWindow':
          final on = call.arguments == true;
          onCover(on);
          if (on) onViolation('split');
        case 'screenshot':
          onViolation('shot');
        case 'captured':
          final on = call.arguments == true;
          onCover(on);
          if (on) onViolation('rec');
      }
    });
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('enable');
      if (r?['multiWindow'] == true) {
        onCover(true);
        onViolation('split');
      }
    } on MissingPluginException {
      // platform tanpa kanal native (uji)
    }
    _life = AppLifecycleListener(
      // `inactive` saja (tarik notifikasi, dialog sistem) tidak dihitung agar tidak salah tuduh.
      onHide: () {
        _hiddenAt = DateTime.now();
        onCover(true);
      },
      onShow: () {
        onCover(false);
        final since = _hiddenAt;
        _hiddenAt = null;
        if (since != null && DateTime.now().difference(since) > const Duration(milliseconds: 1500)) onViolation('bg');
      },
    );
  }

  Future<void> disable() async {
    _life?.dispose();
    _life = null;
    _ch.setMethodCallHandler(null);
    try {
      await _ch.invokeMethod<void>('disable');
    } on MissingPluginException {
      // uji
    }
  }
}
