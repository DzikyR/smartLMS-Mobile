import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/site.dart';
import '../../app/theme.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import 'prefetch.dart';

/// Ujian Saya — sama dengan /ujian di web: dikelompokkan Sedang berlangsung / Akan datang / Selesai.
class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  Future<List<Map<String, dynamic>>>? _exams;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = ref.read(servicesProvider);
    setState(() {
      _exams = s.exams.list().then((l) {
        schedulePrefetch(s, l);
        return l;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteProvider);
    return AppShell(
      location: '/ujian',
      onRefresh: () async => _load(),
      child: AsyncBody<List<Map<String, dynamic>>>(
        future: _exams,
        onRetry: _load,
        builder: (context, exams) {
          final now = exams.where((e) => e['state'] == 'running' || e['state'] == 'available').toList();
          final upcoming = exams.where((e) => e['state'] == 'upcoming').toList();
          final past = exams.where((e) => e['state'] == 'done' || e['state'] == 'missed').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              PageTitle(site.t('nav.ujian'), subtitle: 'Kuis, UTS, UAS, dan tes yang ditujukan untuk Anda. Siapkan koneksi stabil sebelum memulai.'),
              if (exams.isEmpty) ...[const SizedBox(height: 16), const EmptyNote('Belum ada ujian untuk Anda.')],
              ..._group(context, 'Sedang berlangsung', now),
              ..._group(context, 'Akan datang', upcoming),
              ..._group(context, 'Selesai', past),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _group(BuildContext context, String title, List<Map<String, dynamic>> items) => items.isEmpty
      ? const []
      : [
          SectionHeader(
            title,
            trailing: Text('(${items.length})  ', style: TextStyle(color: context.palette.mutedForeground)),
          ),
          for (final e in items) ExamCard(exam: e, onTap: () => context.push('/ujian/${e['id']}')),
        ];
}

/// Hasil Ujian — sama dengan /hasil di web.
class ResultsPage extends ConsumerStatefulWidget {
  const ResultsPage({super.key});

  @override
  ConsumerState<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends ConsumerState<ResultsPage> {
  Future<List<Map<String, dynamic>>>? _exams;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
    _exams = ref.read(servicesProvider).exams.list();
  });

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteProvider);
    return AppShell(
      location: '/hasil',
      onRefresh: () async => _load(),
      child: AsyncBody<List<Map<String, dynamic>>>(
        future: _exams,
        onRetry: _load,
        builder: (context, exams) {
          final done = exams.where((e) => (e['attempts'] as int? ?? 0) > 0).toList();
          final p = context.palette;
          final t = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              PageTitle(site.t('nav.hasil'), subtitle: 'Nilai ujian yang sudah Anda kerjakan.'),
              const SizedBox(height: 12),
              if (done.isEmpty) const EmptyNote('Belum ada ujian yang dikumpulkan.'),
              for (final e in done)
                AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  onTap: () => context.push('/ujian/${e['id']}'),
                  child: Row(
                    children: [
                      TintIcon(icon: LucideIcons.trophy, tint: e['best'] == null ? 'orange' : 'violet'),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${e['subject']['code']} · ${e['subject']['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(color: p.mutedForeground),
                            ),
                            Text(e['title'] as String, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                            Text('${e['attempts']}× dikerjakan', style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      e['best'] != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${e['best']}', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                                if (e['passingScore'] != null)
                                  Pill(label: (e['best'] as num) >= (e['passingScore'] as num) ? 'Lulus' : 'Belum lulus', tint: (e['best'] as num) >= (e['passingScore'] as num) ? 'green' : 'rose'),
                              ],
                            )
                          : Pill(label: e['pendingScore'] == true ? 'Menunggu nilai' : 'Disembunyikan', tint: 'orange'),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
