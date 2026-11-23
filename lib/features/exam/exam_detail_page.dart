import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/site.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/diagnostics.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';

/// Detail ujian — sama dengan /ujian/[id] di web: kepala berwarna, Petunjuk, Tata tertib, Mulai.
class ExamDetailPage extends ConsumerStatefulWidget {
  const ExamDetailPage({super.key, required this.examId});
  final String examId;

  @override
  ConsumerState<ExamDetailPage> createState() => _ExamDetailPageState();
}

class _ExamDetailPageState extends ConsumerState<ExamDetailPage> {
  Future<Map<String, dynamic>>? _detail;
  final _token = TextEditingController();
  bool _starting = false;
  String? _error;
  String? _tokenError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = ref.read(servicesProvider);
    setState(() {
      _detail = s.exams.detail(widget.examId).then((d) async {
        final pkg = d['package'] as Map?;
        // Detail dibuka = peserta siap: unduh paket sekarang (bila belum) agar Mulai instan.
        if (pkg != null && d['exam']['mobile'] == 'ok') {
          try {
            await s.exams.prefetchPackage(widget.examId, version: pkg['version'] as String);
          } catch (e, st) {
            Diagnostics.record(e, st, 'prefetch paket'); // dicoba lagi saat Mulai
          }
        }
        return d;
      });
    });
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
      _tokenError = null;
    });
    try {
      final session = await ref.read(servicesProvider).exams.start(widget.examId, token: _token.text.trim());
      if (!mounted) return;
      await context.push('/ujian/${widget.examId}/kerjakan', extra: session);
      _load();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _tokenError = e.fields['token'];
      });
    } catch (e, st) {
      // Error di perangkat (paket rusak, kanal native, dll.): tampilkan & catat agar bisa dilaporkan.
      Diagnostics.record(e, st, 'mulai ujian');
      setState(() => _error = 'Gagal membuka lembar ujian: $e\nDetail tersimpan di Profil → Laporan error.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppShell(
    location: '/ujian',
    onRefresh: () async => _load(),
    child: AsyncBody<Map<String, dynamic>>(future: _detail, onRetry: _load, builder: _content),
  );

  Widget _content(BuildContext context, Map<String, dynamic> d) {
    final site = ref.watch(siteProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final e = d['exam'] as Map<String, dynamic>;
    final running = d['running'] as String?;
    final attempts = (d['attempts'] as List).cast<Map<String, dynamic>>();
    final local = ref.read(servicesProvider).db.package(widget.examId);
    final pkgVersion = (d['package'] as Map?)?['version'];
    final mobile = e['mobile'] as String;
    final open = e['window'] == 'open' && e['sessionActive'] == true;
    final canStart = mobile == 'ok' && (running != null || (open && attempts.length < (e['maxAttempts'] as int)));
    final kind = (e['category'] as String?) ?? kindLabels[e['kind']] ?? 'Ujian';
    final rules = (e['rules'] as List).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        BackLink(site.t('nav.ujian'), onTap: () => context.canPop() ? context.pop() : context.go('/ujian')),
        const SizedBox(height: 8),
        HeroCard(
          children: [
            Text('${e['subject']['code']} · ${e['subject']['name']}', style: t.bodyMedium?.copyWith(color: p.onPrimary.withValues(alpha: 0.85))),
            const SizedBox(height: 6),
            Text(
              e['title'] as String,
              style: t.headlineSmall?.copyWith(color: p.onPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HeroChip(icon: LucideIcons.monitorCheck, label: kind),
                HeroChip(icon: LucideIcons.clock, label: e['timed'] == true ? '${e['durationMinutes']} menit' : 'Tanpa batas durasi'),
                HeroChip(icon: LucideIcons.fileQuestion, label: '${e['questionCount']} soal'),
                if (e['startAt'] != null && e['window'] == 'upcoming') HeroChip(icon: LucideIcons.calendarClock, label: 'Buka ${formatTime(e['startAt'] as int?)}'),
                if (e['endAt'] != null) HeroChip(icon: LucideIcons.calendarClock, label: 'Tutup ${formatTime(e['endAt'] as int?)}'),
              ],
            ),
          ],
        ),
        if (e['instructions'] != null) ...[
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Petunjuk', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(e['instructions'] as String, style: t.bodyLarge?.copyWith(height: 1.5)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.scrollText, color: p.primary, size: 22),
                  const SizedBox(width: 10),
                  Text('Tata tertib', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              for (final (i, r) in [
                ...rules,
                {'text': 'Di aplikasi: tangkapan & rekam layar diblokir; keluar aplikasi atau layar terbagi dicatat sebagai pelanggaran.'},
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text('${i + 1}.', style: t.bodyMedium?.copyWith(color: p.mutedForeground)),
                      ),
                      Expanded(
                        child: Text(r['text'] as String, style: t.bodyMedium?.copyWith(color: r['source'] == 'author' ? p.foreground : p.mutedForeground, height: 1.45)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (attempts.isNotEmpty) ...[
          const SectionHeader('Riwayat pengerjaan'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                for (final a in attempts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Percobaan ${a['no']}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              Text(formatTime(a['submittedAt'] as int?), style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                            ],
                          ),
                        ),
                        a['score'] == null
                            ? Pill(label: a['status'] == 'SUBMITTED' ? 'Menunggu nilai' : 'Nilai disembunyikan', tint: 'orange')
                            : Text('${a['score']}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mobile != 'ok')
                Text(switch (mobile) {
                  'integrity_required' => 'Ujian tingkat 2 (UTS/UAS) dikerjakan dengan Safe Exam Browser di laptop/PC/iPad.',
                  'not_allowed' => 'Pengajar menetapkan ujian ini tidak dapat dikerjakan dari aplikasi. Gunakan laptop/PC.',
                  _ => 'Pekerjaan ini dikerjakan dari situs web.',
                }, style: t.bodyMedium)
              else ...[
                Row(
                  children: [
                    Icon(local?.version == pkgVersion ? LucideIcons.circleCheck : LucideIcons.cloudDownload, size: 18, color: local?.version == pkgVersion ? p.tint('green').$2 : p.mutedForeground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        local?.version == pkgVersion ? 'Soal sudah tersimpan di perangkat — siap walau sinyal lemah.' : 'Soal akan diunduh saat ujian dimulai.',
                        style: t.bodySmall?.copyWith(color: p.mutedForeground),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (running == null && e['needsToken'] == true) ...[
                  Text('Token ujian', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _token,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(hintText: 'Diumumkan pengawas', errorText: _tokenError),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_error != null && _tokenError == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: p.destructive)),
                  ),
                if (!canStart && running == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      !open ? (e['window'] == 'upcoming' ? 'Ujian belum dibuka.' : 'Ujian sudah ditutup.') : 'Batas ${e['maxAttempts']}× kesempatan sudah tercapai.',
                      style: t.bodyMedium?.copyWith(color: p.mutedForeground),
                    ),
                  ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: canStart && !_starting ? _start : null,
                  icon: _starting ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary)) : const Icon(LucideIcons.play, size: 20),
                  label: Text(running != null ? 'Lanjutkan ujian' : 'Mulai ujian'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
