import 'dart:async';
import 'dart:math';

import '../../app/services.dart';

final _scheduled = <String>{};
final _timers = <Timer>[];

/// Untuk uji: batalkan unduhan yang masih menunggu jeda acaknya.
void cancelScheduledPrefetch() {
  for (final t in _timers) {
    t.cancel();
  }
  _timers.clear();
  _scheduled.clear();
}

/// Unduh paket soal ujian yang akan/sedang dibuka, tersebar acak 0–2 menit agar ratusan
/// peserta tidak mengunduh di detik yang sama (thundering herd). Sekali per ujian per sesi aplikasi.
void schedulePrefetch(AppServices s, Iterable<Map<String, dynamic>> exams) {
  for (final e in exams) {
    final id = e['id'] as String;
    final ready = e['mobile'] == 'ok' && e['workType'] != 'ASSIGNMENT' && const ['available', 'upcoming', 'running'].contains(e['state']);
    if (!ready || !_scheduled.add(id)) continue;
    _timers.add(Timer(Duration(seconds: Random().nextInt(120)), () async {
      try {
        final detail = await s.exams.detail(id);
        final pkg = detail['package'] as Map?;
        if (pkg != null) await s.exams.prefetchPackage(id, version: pkg['version'] as String);
      } catch (_) {
        _scheduled.remove(id); // dicoba lagi saat daftar dimuat ulang
      }
    }));
  }
}
