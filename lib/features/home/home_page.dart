import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../shared/widgets.dart';
import '../lms/lms_repository.dart';

const _postLabel = {'MATERI': 'Materi', 'TUGAS': 'Tugas', 'TUGAS_KUIS': 'Kuis', 'PERTANYAAN': 'Pertanyaan'};
const _postIcon = {'MATERI': Icons.menu_book_outlined, 'TUGAS': Icons.assignment_outlined, 'TUGAS_KUIS': Icons.quiz_outlined, 'PERTANYAAN': Icons.help_outline};

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tab = 0;
  Future<Cached<Map<String, dynamic>>>? _dash;
  Future<List<Map<String, dynamic>>>? _exams;
  final _prefetched = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final s = ref.read(servicesProvider);
    setState(() {
      _dash = s.lms.dashboard();
      _exams = s.exams.list().then((list) {
        _schedulePrefetch(list);
        return list;
      });
    });
  }

  /// Unduh paket soal ujian yang akan/sedang dibuka, tersebar acak 0–2 menit agar
  /// ratusan peserta tidak mengunduh di detik yang sama (thundering herd).
  void _schedulePrefetch(List<Map<String, dynamic>> exams) {
    final s = ref.read(servicesProvider);
    for (final e in exams) {
      final id = e['id'] as String;
      final ready = e['mobile'] == 'ok' && e['workType'] != 'ASSIGNMENT' && const ['available', 'upcoming', 'running'].contains(e['state']);
      if (!ready || !_prefetched.add(id)) continue;
      Timer(Duration(seconds: Random().nextInt(120)), () async {
        try {
          final detail = await s.exams.detail(id);
          final pkg = detail['package'] as Map?;
          if (pkg != null) await s.exams.prefetchPackage(id, version: pkg['version'] as String);
        } catch (_) {
          _prefetched.remove(id); // dicoba lagi saat muat ulang
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user != null && !user.isStudent) {
      return Scaffold(
        appBar: AppBar(title: const Text('SmartTest')),
        body: ErrorView(message: 'Aplikasi tahap ini untuk mahasiswa. Pengajar & admin silakan memakai situs web.', onRetry: () => ref.read(authProvider.notifier).logout()),
      );
    }
    final pages = [_dashboardTab(), _examsTab(), _classesTab(), _accountTab()];
    return Scaffold(
      appBar: AppBar(title: Text(const ['Beranda', 'Ujian', 'Kelas', 'Akun'][_tab])),
      body: RefreshIndicator(onRefresh: () async => _reload(), child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Ujian'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Kelas'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Akun'),
        ],
      ),
    );
  }

  Widget _dashboardTab() => AsyncBody<Cached<Map<String, dynamic>>>(
        future: _dash,
        onRetry: _reload,
        builder: (context, c) {
          final exams = (c.data['exams'] as List).cast<Map<String, dynamic>>();
          final posts = (c.data['posts'] as List).cast<Map<String, dynamic>>();
          return ListView(children: [
            if (c.stale) const StaleBanner(),
            const _Header('Ujian & pekerjaan aktif'),
            if (exams.isEmpty) const ListTile(title: Text('Tidak ada ujian aktif.')),
            for (final e in exams) _examTile(e),
            const _Header('Postingan terbaru'),
            if (posts.isEmpty) const ListTile(title: Text('Belum ada postingan.')),
            for (final p in posts)
              ListTile(
                leading: Icon(_postIcon[p['kind']] ?? Icons.article_outlined),
                title: Text(p['title'] as String),
                subtitle: Text('${_postLabel[p['kind']] ?? ''} · ${p['className']} · ${formatTime(p['publishedAt'] as int?)}'),
                onTap: () => context.push('/material/${p['id']}'),
              ),
          ]);
        },
      );

  Widget _examsTab() => AsyncBody<List<Map<String, dynamic>>>(
        future: _exams,
        onRetry: _reload,
        builder: (context, exams) => exams.isEmpty
            ? const ErrorView(message: 'Belum ada ujian untuk Anda.')
            : ListView(children: [for (final e in exams) _examTile(e)]),
      );

  Widget _examTile(Map<String, dynamic> e) {
    const stateLabel = {'running': 'Sedang dikerjakan', 'available': 'Tersedia', 'upcoming': 'Terjadwal', 'done': 'Selesai', 'missed': 'Terlewat'};
    final mobile = e['mobile'] as String?;
    final note = switch (mobile) {
      'not_allowed' => ' · hanya di laptop/PC',
      'integrity_required' => ' · wajib Safe Exam Browser',
      'web_only' => ' · kerjakan di web',
      _ => '',
    };
    return ListTile(
      leading: Icon(e['state'] == 'running' ? Icons.play_circle : Icons.quiz_outlined, color: e['state'] == 'running' ? Theme.of(context).colorScheme.primary : null),
      title: Text(e['title'] as String),
      subtitle: Text('${stateLabel[e['state']] ?? e['state']}$note${e['startAt'] != null ? ' · ${formatTime(e['startAt'] as int?)}' : ''}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/exam/${e['id']}'),
    );
  }

  Widget _classesTab() => AsyncBody<Cached<Map<String, dynamic>>>(
        future: _dash,
        onRetry: _reload,
        builder: (context, c) {
          final classes = (c.data['classes'] as List).cast<Map<String, dynamic>>();
          if (classes.isEmpty) return const ErrorView(message: 'Belum mengikuti kelas. Gabung kelas memakai kode dari pengajar di situs web.');
          return ListView(children: [
            if (c.stale) const StaleBanner(),
            for (final k in classes)
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(k['name'] as String),
                subtitle: Text([k['subject']?['name'], k['owner'], k['term'], if (k['status'] == 'PENDING') 'menunggu persetujuan'].whereType<String>().join(' · ')),
                enabled: k['status'] == 'ACTIVE',
                onTap: () => context.push('/class/${k['id']}', extra: k['name']),
              ),
          ]);
        },
      );

  Widget _accountTab() {
    final user = ref.watch(authProvider).user;
    final s = ref.read(servicesProvider);
    return ListView(children: [
      ListTile(leading: const Icon(Icons.person), title: Text(user?.name ?? '-'), subtitle: Text([user?.username, user?.email].whereType<String>().join(' · '))),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('Versi aplikasi'), subtitle: Text(s.appVersion)),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Keluar'),
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Keluar dari aplikasi?'),
              content: const Text('Ujian yang belum dikumpulkan tetap tersimpan di perangkat ini.'),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keluar'))],
            ),
          );
          if (ok == true) ref.read(authProvider.notifier).logout();
        },
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
