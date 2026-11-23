# SmartTest Mobile

Aplikasi Android & iOS (Flutter) untuk **SmartTest** — CBT & LMS Informatika
(<https://informatikatsu.my.id>). Tahap 1: **mahasiswa** — ujian CBT yang tahan sinyal putus-nyambung
dan LMS (baca materi, lampiran, notifikasi).

Backend-nya adalah repo web [`DzikyR/smartTest`](https://github.com/DzikyR/smartTest) — endpoint
`/api/v1/mobile/*` memakai mesin ujian yang sama dengan web. **Kontrak API lengkap:
[`docs/API-MOBILE.md`](https://github.com/DzikyR/smartTest/blob/fitur/api-mobile/docs/API-MOBILE.md)**.

## Menjalankan

```bash
flutter pub get
flutter run                                              # server produksi (informatikatsu.my.id)
flutter run --dart-define=API_BASE=http://10.0.2.2:3000  # server lokal dari emulator Android
```

Build: `flutter build apk --release --split-per-abi` (Android), `flutter build ipa` (iOS, di macOS).

## Arsitektur

```
lib/
├── main.dart                  bootstrap: layanan, Firebase (opsional), ProviderScope
├── app/                       services.dart (DI), providers.dart (sesi/auth, force update), router.dart (go_router)
├── core/
│   ├── api/api_client.dart    Dio: header perangkat, Bearer + refresh tunggal saat 401, retry + jitter
│   ├── storage/               secure_store.dart (Keystore/Keychain), local_db.dart (SQLite TERENKRIPSI)
│   ├── time/server_clock.dart jam server + jam monotonic (mengubah jam HP tidak berpengaruh)
│   ├── security/exam_guard.dart  FLAG_SECURE, screen pinning, deteksi keluar aplikasi/split-screen/rekam layar
│   └── push/push_service.dart FCM: token → server (topik kelas dikelola server), buka layar dari notifikasi
└── features/
    ├── auth/                  login, ganti password sementara
    ├── home/                  beranda, daftar ujian, kelas, akun, layar force update/perawatan
    ├── exam/                  paket soal terenkripsi, repository (delta/outbox), sesi ujian, UI lembar ujian
    └── lms/                   postingan kelas, materi, unduh lampiran (ber-ETag)
```

- **State**: Riverpod (tanpa codegen). **Penyimpanan lokal**: `sqlite3` + SQLite3MultipleCiphers
  (ChaCha20, `hooks.user_defines` di `pubspec.yaml`), kunci 256-bit di secure storage.
- **Native**: kanal `smartlms/guard` di `android/.../MainActivity.kt` dan `ios/Runner/AppDelegate.swift`.

## Alur ujian (hemat server & kuota)

1. Daftar ujian dibuka → paket soal **terenkripsi** diunduh tersebar acak 0–2 menit (bukan serentak).
2. **Mulai** → server hanya mengirim tata letak acak + kunci 32 byte; soal didekripsi di perangkat.
3. Setiap klik jawaban → database lokal (0 permintaan jaringan).
4. Sinkron **delta bernomor urut** tiap 60 dtk (15 dtk di 5 menit terakhir), saat sinyal kembali, dan saat
   aplikasi ke belakang — aman diulang; respons hilang tidak menyebabkan jawaban hilang.
5. **Kumpul** → masuk antrean lokal dulu; offline = dikirim otomatis saat online (server idempotent).
6. Timer = jam server; waktu habis → kumpul otomatis. Aturan sama dengan web: lewat batas waktu + 2 menit,
   server hanya menilai jawaban yang **sudah tersinkron**.

## Notifikasi (FCM)

Aktif setelah menambahkan konfigurasi Firebase (tidak di-commit):
1. Firebase Console → tambah aplikasi Android `id.my.informatikatsu.smartlms` (dan iOS) → unduh
   `google-services.json` ke `android/app/`, `GoogleService-Info.plist` ke `ios/Runner/`.
2. Pasang plugin Gradle `com.google.gms.google-services` (atau `flutterfire configure`).
3. Di server: isi `FCM_CREDENTIALS` (service account) — lihat `.env.example` repo web.

Tanpa konfigurasi ini aplikasi tetap berjalan; hanya notifikasi yang nonaktif.

## Pengujian

```bash
flutter analyze
flutter test                     # unit: dekripsi paket (fixture dari kode server), DB terenkripsi, jam,
                                 # klien API (refresh/retry/force update), sinkron delta & antrean kumpul
# Uji kontrak terhadap server SmartTest lokal (DB hasil seed, `npm start -- -p 3123`):
flutter test test/live --dart-define=LIVE_API=http://localhost:3123 --dart-define=LIVE_USER=2401004 --dart-define=LIVE_PASSWORD=<dari .akun-demo.txt>
```

`test/fixtures/package_fixture.json` dibuat dari `sealPackage()` milik server; buat ulang bila format paket berubah.

## Belum dikerjakan

- iOS belum pernah di-build/diuji (dikembangkan di Windows) — perlu macOS + Xcode.
- Ujian tingkat 2 (UTS/UAS): menunggu verifikasi Play Integrity / App Attest di server; saat ini ditolak dengan pesan
  agar memakai Safe Exam Browser.
- Login Google, Tugas unggah berkas, komentar materi, gabung kelas dari aplikasi, fitur pengajar.
- Ikon aplikasi, splash, dan keystore rilis.
