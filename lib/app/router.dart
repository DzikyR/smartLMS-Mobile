import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/exam/exam_detail_page.dart';
import '../features/exam/exam_repository.dart';
import '../features/exam/exam_runner_page.dart';
import '../features/exam/exams_page.dart';
import '../features/home/dashboard_page.dart';
import '../features/home/status_pages.dart';
import '../features/lms/lms_pages.dart';
import 'providers.dart';

/// Halaman utama tanpa animasi geser (berpindah lewat menu, seperti web).
Page<void> _flat(Widget child) => NoTransitionPage<void>(child: child);

/// Path sama dengan web (/dashboard, /kelas, /ujian, /hasil, /profil) agar menu dari server langsung cocok.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
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
          return at.endsWith('/kerjakan') ? null : only('/update');
        case AuthStatus.maintenance:
          return only('/maintenance');
        case AuthStatus.signedOut:
          return only('/login');
        case AuthStatus.signedIn:
          if (auth.user?.mustChangePassword == true) return only('/ganti-password');
          return const ['/', '/login', '/splash', '/ganti-password', '/update', '/maintenance'].contains(at) ? '/dashboard' : null;
      }
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/ganti-password', builder: (_, _) => const ChangePasswordPage()),
      GoRoute(path: '/update', builder: (_, _) => const UpdatePage()),
      GoRoute(path: '/maintenance', builder: (_, _) => const MaintenancePage()),
      GoRoute(path: '/dashboard', pageBuilder: (_, _) => _flat(const DashboardPage())),
      GoRoute(path: '/kelas', pageBuilder: (_, _) => _flat(const ClassesPage())),
      GoRoute(
        path: '/kelas/:id',
        builder: (_, s) => ClassPage(classId: s.pathParameters['id']!, info: s.extra as Map<String, dynamic>?),
      ),
      GoRoute(
        path: '/materi/:id',
        builder: (_, s) => PostPage(materialId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/ujian', pageBuilder: (_, _) => _flat(const ExamsPage())),
      GoRoute(
        path: '/ujian/:id',
        builder: (_, s) => ExamDetailPage(examId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/ujian/:id/kerjakan',
        builder: (_, s) => ExamRunnerPage(data: s.extra! as ExamSessionData),
      ),
      GoRoute(path: '/hasil', pageBuilder: (_, _) => _flat(const ResultsPage())),
      GoRoute(path: '/profil', pageBuilder: (_, _) => _flat(const ProfilePage())),
    ],
  );
});
