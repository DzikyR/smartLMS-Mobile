import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../shared/widgets.dart';
import 'exam_package.dart';
import 'exam_repository.dart';
import 'exam_session.dart';

/// Lembar ujian. Tombol kembali dinonaktifkan; keluar hanya lewat Kumpulkan.
class ExamRunnerPage extends ConsumerStatefulWidget {
  const ExamRunnerPage({super.key, required this.data});
  final ExamSessionData data;

  @override
  ConsumerState<ExamRunnerPage> createState() => _ExamRunnerPageState();
}

class _ExamRunnerPageState extends ConsumerState<ExamRunnerPage> {
  late final ExamSession _session;
  final _text = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    final s = ref.read(servicesProvider);
    _session = ExamSession(data: widget.data, repo: s.exams, db: s.db, clock: s.clock)..begin();
    Future.microtask(() => ref.read(examActiveProvider.notifier).state = true);
  }

  @override
  void dispose() {
    _session.dispose();
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _leave() {
    ref.read(examActiveProvider.notifier).state = false;
    Navigator.of(context).pop();
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _session.questions.length - _session.answeredCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kumpulkan ujian?'),
        content: Text(unanswered > 0 ? 'Masih ada $unanswered soal belum dijawab. Jawaban tidak dapat diubah setelah dikumpulkan.' : 'Jawaban tidak dapat diubah setelah dikumpulkan.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Periksa lagi')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kumpulkan'))],
      ),
    );
    if (ok == true) await _session.submit();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) => _session.finished ? _resultView() : _sheet(),
        ),
      );

  Widget _sheet() {
    final s = _session;
    final left = s.remaining;
    final theme = Theme.of(context);
    final urgent = left != null && left.inMinutes < 5;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(left == null ? 'Tanpa batas waktu' : formatDuration(left), style: TextStyle(color: urgent ? theme.colorScheme.error : null, fontFeatures: const [FontFeature.tabularFigures()])),
        actions: [
          _SyncBadge(state: s.syncState, last: s.lastSyncedAt),
          IconButton(tooltip: 'Daftar soal', icon: const Icon(Icons.grid_view), onPressed: _openGrid),
        ],
      ),
      body: Stack(children: [
        Column(children: [
          if (s.notice != null)
            MaterialBanner(content: Text(s.notice!), actions: [TextButton(onPressed: () => setState(() => s.notice = null), child: const Text('Tutup'))]),
          LinearProgressIndicator(value: s.questions.isEmpty ? 0 : s.answeredCount / s.questions.length),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final q in s.pageQuestions) _question(q, s.questions.indexOf(q) + 1),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                OutlinedButton(onPressed: s.page > 0 ? () => s.goTo(s.page - 1) : null, child: const Text('Sebelumnya')),
                const Spacer(),
                Text('${s.page + 1} / ${s.pageCount}'),
                const Spacer(),
                if (s.page < s.pageCount - 1)
                  FilledButton(onPressed: () => s.goTo(s.page + 1), child: const Text('Berikutnya'))
                else
                  FilledButton(onPressed: s.submitting ? null : _confirmSubmit, child: s.submitting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kumpulkan')),
              ]),
            ),
          ),
        ]),
        // Aplikasi di latar belakang / direkam / layar terbagi → soal ditutup.
        if (s.covered) Positioned.fill(child: ColoredBox(color: theme.colorScheme.surface, child: const Center(child: Text('Soal disembunyikan')))),
      ]),
    );
  }

  Widget _question(PackageQuestion q, int no) {
    final s = _session;
    final answer = s.answerOf(q.id);
    final theme = Theme.of(context);
    Widget input;
    switch (q.type) {
      case 'MULTIPLE_CHOICE':
        input = RadioGroup<String>(
          groupValue: answer,
          onChanged: (v) => s.answer(q.id, v),
          child: Column(children: [
            for (final (i, o) in q.options.indexed)
              RadioListTile<String>(value: o.id, title: Text('${String.fromCharCode(65 + i)}. ${o.text}'), contentPadding: EdgeInsets.zero),
          ]),
        );
      case 'TRUE_FALSE':
        input = RadioGroup<String>(
          groupValue: answer,
          onChanged: (v) => s.answer(q.id, v),
          child: const Column(children: [
            RadioListTile<String>(value: 'true', title: Text('Benar'), contentPadding: EdgeInsets.zero),
            RadioListTile<String>(value: 'false', title: Text('Salah'), contentPadding: EdgeInsets.zero),
          ]),
        );
      default:
        final c = _text.putIfAbsent(q.id, () => TextEditingController(text: answer ?? ''));
        input = TextField(
          controller: c,
          maxLength: 5000,
          minLines: q.type == 'ESSAY' ? 5 : 1,
          maxLines: q.type == 'ESSAY' ? 12 : 1,
          // Tempel/salin dimatikan seperti pengamanan web (blockCopyPaste).
          contextMenuBuilder: (_, _) => const SizedBox.shrink(),
          decoration: InputDecoration(border: const OutlineInputBorder(), hintText: q.type == 'ESSAY' ? 'Tulis jawaban Anda' : 'Jawaban singkat'),
          onChanged: (v) => s.answer(q.id, v),
        );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Soal $no', style: theme.textTheme.labelLarge),
            Text('  · ${q.points % 1 == 0 ? q.points.toInt() : q.points} poin', style: theme.textTheme.labelSmall),
            const Spacer(),
            FilterChip(label: const Text('Ragu-ragu'), selected: s.isFlagged(q.id), onSelected: (_) => s.toggleFlag(q.id)),
          ]),
          const SizedBox(height: 8),
          Text(q.prompt, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          input,
        ]),
      ),
    );
  }

  void _openGrid() => showModalBottomSheet<void>(
        context: context,
        builder: (c) => ListenableBuilder(
          listenable: _session,
          builder: (c, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, q) in _session.questions.indexed)
                ActionChip(
                  label: Text('${i + 1}'),
                  avatar: _session.isFlagged(q.id) ? const Icon(Icons.flag, size: 16) : null,
                  backgroundColor: (_session.answerOf(q.id)?.isNotEmpty ?? false) ? Theme.of(c).colorScheme.primaryContainer : null,
                  onPressed: () {
                    _session.goTo(i ~/ _session.perPage);
                    Navigator.pop(c);
                  },
                ),
            ]),
          ),
        ),
      );

  Widget _resultView() {
    final r = _session.result!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(r.pending ? Icons.cloud_upload_outlined : Icons.check_circle_outline, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(r.pending ? 'Menunggu koneksi' : 'Ujian terkumpul', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(r.message ?? '', textAlign: TextAlign.center),
              if (r.score != null) ...[const SizedBox(height: 16), Text('Nilai: ${r.score}', style: Theme.of(context).textTheme.headlineMedium)],
              const SizedBox(height: 24),
              if (r.pending)
                FilledButton.tonal(onPressed: _session.submitting ? null : _session.retryPendingSubmit, child: const Text('Kirim sekarang'))
              else
                FilledButton(onPressed: _leave, child: const Text('Selesai')),
              if (r.pending) TextButton(onPressed: _leave, child: const Text('Tutup (dikirim otomatis nanti)')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.state, required this.last});
  final SyncState state;
  final DateTime? last;

  @override
  Widget build(BuildContext context) {
    final (icon, tip) = switch (state) {
      SyncState.syncing => (Icons.sync, 'Menyimpan…'),
      SyncState.offline => (Icons.cloud_off, 'Offline — jawaban aman di perangkat'),
      SyncState.error => (Icons.error_outline, 'Gagal menyimpan'),
      SyncState.idle => (Icons.cloud_done_outlined, last == null ? 'Belum tersinkron' : 'Tersimpan di server'),
    };
    return Tooltip(message: tip, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(icon)));
  }
}
