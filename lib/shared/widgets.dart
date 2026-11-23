import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api/api_client.dart';

final _dateTime = DateFormat('EEE, d MMM yyyy HH:mm', 'id');

String formatTime(int? ms) => ms == null ? '-' : _dateTime.format(DateTime.fromMillisecondsSinceEpoch(ms));

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String errorText(Object e) => e is ApiException ? e.message : 'Terjadi kesalahan. Coba lagi.';

/// Isi layar: memuat / galat (dengan tombol coba lagi) / data.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.future, required this.builder, required this.onRetry});

  final Future<T>? future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return ErrorView(message: errorText(snap.error!), onRetry: onRetry);
      return builder(context, snap.data as T);
    },
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[const SizedBox(height: 16), FilledButton.tonal(onPressed: onRetry, child: const Text('Coba lagi'))],
        ],
      ),
    ),
  );
}

/// Pita "data offline" saat menampilkan cache.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialBanner(content: const Text('Offline — menampilkan data terakhir yang tersimpan.'), leading: const Icon(Icons.wifi_off), actions: const [SizedBox.shrink()]);
}

void showSnack(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));
