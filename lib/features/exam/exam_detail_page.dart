import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../shared/widgets.dart';

/// Detail ujian: tata tertib, status paket soal, token, tombol Mulai/Lanjutkan.
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
    setState(() => _detail = s.exams.detail(widget.examId).then((d) async {
          final pkg = d['package'] as Map?;
          // Detail dibuka = peserta siap: unduh paket sekarang (bila belum) agar Mulai instan.
          if (pkg != null && d['exam']['mobile'] == 'ok') {
            try {
              await s.exams.prefetchPackage(widget.examId, version: pkg['version'] as String);
            } on ApiException {
              // dicoba lagi saat Mulai
            }
          }
          return d;
        }));
  }

  Future<void> _start(Map<String, dynamic> exam) async {
    setState(() {
      _starting = true;
      _error = null;
      _tokenError = null;
    });
    try {
      final session = await ref.read(servicesProvider).exams.start(widget.examId, token: _token.text.trim());
      if (!mounted) return;
      await context.push('/exam/${widget.examId}/run', extra: session);
      _load();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _tokenError = e.fields['token'];
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Detail ujian')),
        body: AsyncBody<Map<String, dynamic>>(
          future: _detail,
          onRetry: _load,
          builder: (context, d) {
            final e = d['exam'] as Map<String, dynamic>;
            final running = d['running'] as String?;
            final attempts = (d['attempts'] as List).cast<Map<String, dynamic>>();
            final local = ref.read(servicesProvider).db.package(widget.examId);
            final pkgVersion = (d['package'] as Map?)?['version'];
            final mobile = e['mobile'] as String;
            final canStart = mobile == 'ok' && (running != null || (e['window'] == 'open' && e['sessionActive'] == true && attempts.length < (e['maxAttempts'] as int)));
            final theme = Theme.of(context);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(e['title'] as String, style: theme.textTheme.headlineSmall),
              Text('${e['subject']['code']} · ${e['subject']['name']}'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text('${e['questionCount']} soal')),
                Chip(label: Text(e['timed'] == true ? '${e['durationMinutes']} menit' : 'Tanpa batas durasi')),
                if (e['startAt'] != null) Chip(label: Text('Buka ${formatTime(e['startAt'] as int?)}')),
                if (e['endAt'] != null) Chip(label: Text('Tutup ${formatTime(e['endAt'] as int?)}')),
                Chip(
                  avatar: Icon(local?.version == pkgVersion ? Icons.download_done : Icons.downloading, size: 18),
                  label: Text(local?.version == pkgVersion ? 'Soal siap (offline)' : 'Soal belum terunduh'),
                ),
              ]),
              if (e['instructions'] != null) ...[const SizedBox(height: 12), Text(e['instructions'] as String)],
              const SizedBox(height: 16),
              Text('Tata tertib', style: theme.textTheme.titleMedium),
              for (final r in (e['rules'] as List).cast<Map<String, dynamic>>())
                Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(r['text'] as String))])),
              const Padding(padding: EdgeInsets.only(top: 6), child: Text('•  Di aplikasi: tangkapan/rekam layar diblokir, keluar aplikasi atau layar terbagi dicatat sebagai pelanggaran.')),
              if (attempts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Riwayat', style: theme.textTheme.titleMedium),
                for (final a in attempts)
                  ListTile(contentPadding: EdgeInsets.zero, title: Text('Percobaan ${a['no']}'), subtitle: Text('${a['status']} · ${formatTime(a['submittedAt'] as int?)}'), trailing: Text(a['score'] == null ? '—' : '${a['score']}')),
              ],
              const SizedBox(height: 20),
              if (mobile != 'ok')
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(switch (mobile) {
                  'integrity_required' => 'Ujian tingkat 2 (UTS/UAS) dikerjakan dengan Safe Exam Browser di laptop/PC/iPad.',
                  'not_allowed' => 'Pengajar menetapkan ujian ini tidak dapat dikerjakan dari aplikasi. Gunakan laptop/PC.',
                  _ => 'Pekerjaan ini dikerjakan dari situs web.',
                })))
              else ...[
                if (running == null && e['needsToken'] == true)
                  TextField(controller: _token, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'Token ujian dari pengawas', errorText: _tokenError, border: const OutlineInputBorder())),
                if (_error != null && _tokenError == null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canStart && !_starting ? () => _start(e) : null,
                  icon: _starting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                  label: Padding(padding: const EdgeInsets.all(12), child: Text(running != null ? 'Lanjutkan ujian' : 'Mulai ujian')),
                ),
              ],
            ]);
          },
        ),
      );
}
