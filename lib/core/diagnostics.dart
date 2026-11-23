import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Catatan error terakhir di perangkat — ditampilkan di Profil → "Laporan error" agar
/// pengguna bisa menyalin & mengirimkannya ke pengembang (tanpa perlu kabel USB/adb).
class Diagnostics {
  Diagnostics._();

  static final List<String> _log = [];
  static List<String> get entries => List.unmodifiable(_log.reversed);

  static void record(Object error, [StackTrace? stack, String? where]) {
    final time = DateTime.now().toIso8601String().substring(0, 19);
    final lines = (stack ?? StackTrace.empty).toString().split('\n').where((l) => l.trim().isNotEmpty).take(8).join('\n');
    _log.add('[$time]${where == null ? '' : ' $where'}\n$error\n$lines');
    if (_log.length > 20) _log.removeAt(0);
    debugPrint('[diagnostics] $error');
  }

  /// Pasang penangkap error global (main.dart).
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, details.context?.toDescription());
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, 'async');
      return true;
    };
  }

  static Future<void> copy() => Clipboard.setData(ClipboardData(text: entries.join('\n\n')));
}
