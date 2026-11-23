import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Force update: versi aplikasi di bawah MOBILE_MIN_VERSION server.
class UpdatePage extends ConsumerWidget {
  const UpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(authProvider).upgrade ?? const {};
    final store = info['storeUrl'] as Map? ?? const {};
    final url = (Platform.isIOS ? store['ios'] : store['android']) as String?;
    return _StatusScaffold(
      icon: Icons.system_update,
      title: 'Perbarui aplikasi',
      message: '${info['message'] ?? 'Versi aplikasi ini sudah tidak didukung.'}\nVersi minimum: ${info['minVersion'] ?? '-'}',
      action: url == null ? null : FilledButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('Buka toko aplikasi')),
    );
  }
}

class MaintenancePage extends ConsumerWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _StatusScaffold(
        icon: Icons.construction,
        title: 'Sedang perawatan',
        message: ref.watch(authProvider).notice ?? 'Coba lagi beberapa saat lagi.',
        action: FilledButton.tonal(onPressed: () => ref.read(authProvider.notifier).retry(), child: const Text('Coba lagi')),
      );
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                if (action != null) ...[const SizedBox(height: 24), action!],
              ]),
            ),
          ),
        ),
      );
}
