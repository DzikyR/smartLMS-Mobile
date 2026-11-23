/// Konfigurasi build. Ganti server saat build/run:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:3000
/// (10.0.2.2 = localhost komputer dari emulator Android).
class AppConfig {
  AppConfig._();

  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://informatikatsu.my.id');

  static String get apiRoot => '$apiBase/api/v1/mobile';

  /// Interval simpan otomatis jawaban. Monitoring Ujian di web menandai peserta
  /// "Tersendat" setelah 90 detik tanpa simpan, jadi jangan lebih jarang dari ini.
  static const syncInterval = Duration(seconds: 60);

  /// Pada menit-menit terakhir simpan lebih sering: setelah batas waktu (+2 menit
  /// toleransi) server hanya menilai jawaban yang SUDAH tersimpan.
  static const syncIntervalFinal = Duration(seconds: 15);
  static const finalPhase = Duration(minutes: 5);
}
