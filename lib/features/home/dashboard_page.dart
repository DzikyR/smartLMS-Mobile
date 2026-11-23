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
import '../exam/prefetch.dart';
import '../lms/lms_repository.dart';

/// Dashboard peserta — sama dengan /dashboard di web.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Future<Cached<Map<String, dynamic>>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = ref.read(servicesProvider);
    setState(() {
      _data = s.lms.dashboard().then((c) {
        schedulePrefetch(s, (c.data['exams'] as List).cast<Map<String, dynamic>>());
        return c;
      });
    });
  }

  @override
  Widget build(BuildContext context) => AppShell(
    location: '/dashboard',
    onRefresh: () async => _load(),
    child: AsyncBody<Cached<Map<String, dynamic>>>(future: _data, onRetry: _load, builder: _content),
  );

  Widget _content(BuildContext context, Cached<Map<String, dynamic>> c) {
    final site = ref.watch(siteProvider);
    final user = ref.watch(authProvider).user;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final stats = c.data['stats'] as Map? ?? const {};
    final available = stats['available'] as int? ?? 0;
    final classes = (c.data['classes'] as List).cast<Map<String, dynamic>>();
    final exams = (c.data['exams'] as List).cast<Map<String, dynamic>>();
    final firstName = (user?.name ?? '').split(' ').first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (c.stale) const StaleBanner(),
        HeroCard(
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 18, color: p.onPrimary.withValues(alpha: 0.85)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(site.t('dashboard.greeting'), style: t.bodyMedium?.copyWith(color: p.onPrimary.withValues(alpha: 0.85))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Halo, $firstName!',
              style: t.headlineMedium?.copyWith(color: p.onPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.6),
            ),
            const SizedBox(height: 8),
            Text(
              available > 0 ? site.t('dashboard.participant.available', {'n': available}) : site.t('dashboard.participant.idle'),
              style: t.bodyLarge?.copyWith(color: p.onPrimary.withValues(alpha: 0.9)),
            ),
            if (available > 0) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: p.primary, shape: const StadiumBorder()),
                  onPressed: () => context.go('/ujian'),
                  icon: const Icon(LucideIcons.monitorCheck, size: 20),
                  label: Text(site.t('dashboard.participant.cta')),
                ),
              ),
            ],
          ],
        ),
        SectionHeader('Kelas Saya', action: 'Lihat semua', onAction: () => context.go('/kelas')),
        if (classes.isEmpty)
          const EmptyNote('Belum mengikuti kelas. Minta kode kelas ke pengajar, lalu gabung lewat situs web.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in classes)
                ActionChip(
                  onPressed: k['status'] == 'ACTIVE' ? () => context.push('/kelas/${k['id']}', extra: k) : null,
                  backgroundColor: p.card,
                  side: BorderSide(color: p.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusXl)),
                  label: Text.rich(
                    TextSpan(
                      children: [
                        if (k['subject'] != null)
                          TextSpan(
                            text: '${k['subject']['code']}  ',
                            style: t.labelSmall?.copyWith(color: p.mutedForeground, fontFamily: 'monospace'),
                          ),
                        TextSpan(
                          text: k['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (k['status'] == 'PENDING')
                          TextSpan(
                            text: ' · menunggu',
                            style: TextStyle(color: p.mutedForeground),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 20),
        StatCard(label: 'Bisa dikerjakan', value: '$available', icon: LucideIcons.monitorCheck, tint: 'green'),
        const SizedBox(height: 12),
        StatCard(label: 'Akan datang', value: '${stats['upcoming'] ?? 0}', icon: LucideIcons.calendarClock, tint: 'sky'),
        const SizedBox(height: 12),
        StatCard(label: 'Rata-rata nilai', value: stats['mean'] == null ? '—' : '${stats['mean']}', icon: LucideIcons.trophy, tint: 'violet', hint: '${stats['scored'] ?? 0} ujian bernilai'),
        SectionHeader('Ujian untuk Anda', action: 'Lihat semua', onAction: () => context.go('/ujian')),
        if (exams.isEmpty) const EmptyNote('Belum ada ujian yang dibuka atau dijadwalkan.'),
        for (final e in exams) ExamCard(exam: e, onTap: () => context.push('/ujian/${e['id']}')),
      ],
    );
  }
}
