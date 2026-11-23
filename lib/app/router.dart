import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/exam/exam_detail_page.dart';
import '../features/exam/exam_repository.dart';
import '../features/exam/exam_runner_page.dart';
import '../features/home/home_page.dart';
import '../features/home/status_pages.dart';
import '../features/lms/lms_pages.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final at = state.matchedLocation;
      String? only(String path) => at == path ? null : path;
      switch (auth.status) {
        case AuthStatus.loading:
          return only('/splash');
        case AuthStatus.upgrade:
          // Ujian yang sedang berjalan tidak diputus oleh force update.
          return at.endsWith('/run') ? null : only('/update');
        case AuthStatus.maintenance:
          return only('/maintenance');
        case AuthStatus.signedOut:
          return only('/login');
        case AuthStatus.signedIn:
          if (auth.user?.mustChangePassword == true) return only('/password');
          return const ['/login', '/splash', '/password', '/update', '/maintenance'].contains(at) ? '/' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/password', builder: (_, _) => const ChangePasswordPage()),
      GoRoute(path: '/update', builder: (_, _) => const UpdatePage()),
      GoRoute(path: '/maintenance', builder: (_, _) => const MaintenancePage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(path: '/exam/:id', builder: (_, s) => ExamDetailPage(examId: s.pathParameters['id']!)),
      GoRoute(path: '/exam/:id/run', builder: (_, s) => ExamRunnerPage(data: s.extra! as ExamSessionData)),
      GoRoute(path: '/class/:id', builder: (_, s) => ClassPage(classId: s.pathParameters['id']!, title: s.extra as String?)),
      GoRoute(path: '/material/:id', builder: (_, s) => MaterialPage(materialId: s.pathParameters['id']!)),
    ],
  );
});
