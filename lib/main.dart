import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/services.dart';
import 'core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id');
  final services = await AppServices.create();
  await PushService.initFirebase();
  runApp(ProviderScope(overrides: [servicesProvider.overrideWithValue(services)], child: const SmartLmsApp()));
}

class SmartLmsApp extends ConsumerStatefulWidget {
  const SmartLmsApp({super.key});

  @override
  ConsumerState<SmartLmsApp> createState() => _SmartLmsAppState();
}

class _SmartLmsAppState extends ConsumerState<SmartLmsApp> {
  PushService? _push;

  @override
  void initState() {
    super.initState();
    // Notifikasi aktif setelah login; token didaftarkan ulang setiap aplikasi dibuka.
    ref.listenManual(authProvider, (_, next) {
      if (next.status != AuthStatus.signedIn || next.user?.mustChangePassword == true) return;
      _push ??= PushService(
        api: ref.read(servicesProvider).api,
        navigate: (route) => ref.read(routerProvider).push(route),
        examActive: () => ref.read(examActiveProvider),
      );
      _push!.start();
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5));
    return MaterialApp.router(
      title: 'SmartTest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5), brightness: Brightness.dark), useMaterial3: true),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
