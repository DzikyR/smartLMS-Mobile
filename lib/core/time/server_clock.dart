import 'package:flutter/services.dart';

/// Jam monotonic perangkat dalam milidetik — TIDAK berubah bila pengguna mengubah jam HP.
/// Android: SystemClock.elapsedRealtime (ikut berjalan saat layar mati/deep sleep).
/// iOS: clock_gettime(CLOCK_MONOTONIC) (di Darwin termasuk waktu sleep).
abstract class MonotonicSource {
  Future<int> nowMs();
}

class PlatformMonotonic implements MonotonicSource {
  static const _ch = MethodChannel('smartlms/guard');
  final Stopwatch _fallback = Stopwatch()..start();

  @override
  Future<int> nowMs() async {
    try {
      final v = await _ch.invokeMethod<int>('elapsed');
      if (v != null) return v;
    } on MissingPluginException {
      // uji / platform tanpa kanal native
    } on PlatformException {
      // jatuh ke Stopwatch
    }
    return _fallback.elapsedMilliseconds;
  }
}

/// Waktu server: `server_now` dari respons + selisih jam monotonic sejak respons itu.
/// Dipakai untuk timer ujian, sehingga mengubah jam/zona waktu HP tidak berpengaruh.
/// Batas waktu tetap ditegakkan server; ini hanya agar tampilan timer jujur.
class ServerClock {
  ServerClock(this._mono);
  final MonotonicSource _mono;

  int? _serverAnchor;
  int? _monoAnchor;
  int _lastMono = 0;

  bool get synced => _serverAnchor != null;

  /// [serverNow] dari server (epoch ms), [rttMs] = lama permintaan pulang-pergi.
  Future<void> sync(int serverNow, {int rttMs = 0}) async {
    final mono = await _mono.nowMs();
    _serverAnchor = serverNow + rttMs ~/ 2;
    _monoAnchor = mono;
    _lastMono = mono;
  }

  /// Perbarui pembacaan jam monotonic (dipanggil tiap detik oleh timer ujian).
  Future<void> tick() async => _lastMono = await _mono.nowMs();

  /// Waktu server saat ini (epoch ms). Sebelum sinkron pertama: jam perangkat.
  int nowMs() {
    if (_serverAnchor == null) return DateTime.now().millisecondsSinceEpoch;
    return _serverAnchor! + (_lastMono - _monoAnchor!);
  }

  /// Sisa waktu menuju [deadline] (epoch ms server); null = tanpa batas.
  Duration? remaining(int? deadline) {
    if (deadline == null) return null;
    final ms = deadline - nowMs();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }
}
