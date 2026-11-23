import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';

/// Tujuan navigasi dari data notifikasi (`type`, `groupId`, `materialId`, `examId`).
String? routeForNotification(Map<String, dynamic> data) {
  final type = data['type'];
  final materialId = data['materialId'];
  final examId = data['examId'];
  if ((type == 'TUGAS_KUIS') && examId is String) return '/ujian/$examId';
  if (materialId is String) return '/materi/$materialId';
  return null;
}

@pragma('vm:entry-point')
Future<void> _background(RemoteMessage message) async {
  // Notifikasi dengan blok `notification` ditampilkan OS; tidak ada kerja tambahan.
}

/// FCM: token didaftarkan ke server (POST /devices) yang mengurus langganan topik kelas.
/// Tanpa konfigurasi Firebase (google-services.json / GoogleService-Info.plist), layanan ini
/// diam saja — aplikasi tetap berjalan normal.
class PushService {
  PushService({required this.api, required this.navigate, required this.examActive});

  final ApiClient api;
  final void Function(String route) navigate;

  /// Saat ujian berlangsung notifikasi tidak ditampilkan & tidak menavigasi.
  final bool Function() examActive;

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static Future<bool> initFirebase() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_background);
      return true;
    } catch (e) {
      debugPrint('[push] Firebase belum dikonfigurasi: $e');
      return false;
    }
  }

  Future<void> start() async {
    if (_ready || Firebase.apps.isEmpty) return;
    _ready = true;
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings()),
      onDidReceiveNotificationResponse: (r) => _open(jsonDecode(r.payload ?? '{}') as Map<String, dynamic>),
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
      const AndroidNotificationChannel('kelas', 'Kelas', description: 'Materi, tugas, dan kuis baru', importance: Importance.high),
    );

    await register();
    // getToken/onTokenRefresh ditandai deprecated di firebase_messaging 17 (diganti FID via register/onRegistered),
    // tetapi langganan TOPIK dari server (firebase-admin subscribeToTopic) masih memerlukan registration token.
    // ignore: deprecated_member_use
    fm.onTokenRefresh.listen((_) => register());
    final initial = await fm.getInitialMessage();
    if (initial != null) _open(initial.data);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null || examActive()) return;
      _local.show(
        id: m.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('kelas', 'Kelas', importance: Importance.high, priority: Priority.high),
        ),
        payload: jsonEncode(m.data),
      );
    });
  }

  /// Daftarkan token & samakan topik kelas. Panggil juga setelah bergabung ke kelas.
  Future<void> register() async {
    if (Firebase.apps.isEmpty) return;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.postJson('/devices', {'fcmToken': token}, retry: true);
    } catch (e) {
      debugPrint('[push] gagal mendaftarkan token: $e');
    }
  }

  void _open(Map<String, dynamic> data) {
    if (examActive()) return;
    final route = routeForNotification(data);
    if (route != null) navigate(route);
  }
}
