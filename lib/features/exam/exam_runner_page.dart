import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import 'exam_package.dart';
import 'exam_repository.dart';
import 'exam_session.dart';

const _typeLabel = {'MULTIPLE_CHOICE': 'Pilihan ganda', 'TRUE_FALSE': 'Benar/Salah', 'SHORT_ANSWER': 'Isian singkat', 'ESSAY': 'Esai'};

/// Lembar ujian — tampilan sama dengan lembar CBT web (toolbar timer, kartu soal bernomor, pilihan A–D,
/// Ragu-ragu, navigasi halaman). Tombol kembali dinonaktifkan; keluar hanya lewat Kumpulkan.
class ExamRunnerPage extends ConsumerStatefulWidget {
  const ExamRunnerPage({super.key, required this.data});
  final ExamSessionData data;

  @override
  ConsumerState<ExamRunnerPage> createState() => _ExamRunnerPageState();
}

class _ExamRunnerPageState extends ConsumerState<ExamRunnerPage> {
  late final ExamSession _session;
  final _text = <String, TextEditingController>{};
  final _scroll = ScrollController();
  double _fontScale = 1;

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
    _scroll.dispose();
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _leave() {
    ref.read(examActiveProvider.notifier).state = false;
    Navigator.of(context).pop();
  }

  void _goTo(int page) {
    _session.goTo(page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _session.questions.length - _session.answeredCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kumpulkan ujian?'),
        content: Text(unanswered > 0 ? 'Masih ada $unanswered soal belum dijawab. Jawaban tidak dapat diubah setelah dikumpulkan.' : 'Jawaban tidak dapat diubah setelah dikumpulkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Periksa lagi')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kumpulkan')),
        ],
      ),
    );
    if (ok == true) await _session.submit();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          title: const BrandLogo(size: 34),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: context.palette.border),
          ),
        ),
        body: _session.finished ? _resultView() : _sheet(),
      ),
    ),
  );

  Widget _sheet() {
    final s = _session;
    final p = context.palette;
    return Stack(
      children: [
        Column(
          children: [
            _toolbar(),
            if (s.notice != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                decoration: BoxDecoration(color: p.tint('orange').$1, borderRadius: BorderRadius.circular(kRadiusXl)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s.notice!, style: TextStyle(color: p.tint('orange').$2)),
                    ),
                    IconButton(icon: const Icon(LucideIcons.x, size: 18), onPressed: () => setState(() => s.notice = null)),
                  ],
                ),
              ),
            Expanded(
              child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [for (final q in s.pageQuestions) _question(q, s.questions.indexOf(q) + 1), _pager()]),
            ),
          ],
        ),
        // Aplikasi di latar belakang / direkam / layar terbagi → soal ditutup.
        if (s.covered)
          Positioned.fill(
            child: ColoredBox(
              color: p.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.eyeOff, size: 40, color: p.mutedForeground),
                    const SizedBox(height: 8),
                    const Text('Soal disembunyikan'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Toolbar lengket seperti web: judul, ukuran huruf, timer, panel nomor soal.
  Widget _toolbar() {
    final s = _session;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final left = s.remaining;
    final urgent = left != null && left.inMinutes < 5;
    final (syncIcon, syncText, syncColor) = switch (s.syncState) {
      SyncState.syncing => (LucideIcons.refreshCw, 'Menyimpan…', p.mutedForeground),
      SyncState.offline => (LucideIcons.cloudOff, 'Offline — jawaban aman di perangkat', p.tint('orange').$2),
      SyncState.error => (LucideIcons.triangleAlert, 'Gagal menyimpan', p.destructive),
      SyncState.idle => (LucideIcons.cloudCheck, s.lastSyncedAt == null ? 'Jawaban tersimpan di perangkat' : 'Tersimpan di server', p.tint('green').$2),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(
          children: [
            Row(
              children: [
                _ToolButton(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _fontScale = (_fontScale - 0.1).clamp(0.8, 1.6)),
                        child: const Padding(padding: EdgeInsets.all(6), child: Icon(LucideIcons.minus, size: 18)),
                      ),
                      Text('A', style: t.labelLarge),
                      InkWell(
                        onTap: () => setState(() => _fontScale = (_fontScale + 0.1).clamp(0.8, 1.6)),
                        child: const Padding(padding: EdgeInsets.all(6), child: Icon(LucideIcons.plus, size: 18)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: urgent ? p.destructive : p.primary, borderRadius: BorderRadius.circular(kRadiusXl)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.clock, size: 18, color: p.onPrimary),
                            const SizedBox(width: 6),
                            Text(
                              left == null ? '∞' : formatDuration(left),
                              style: t.titleMedium?.copyWith(color: p.onPrimary, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  onTap: _openGrid,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.layoutGrid, size: 18),
                        const SizedBox(width: 6),
                        Text('${s.answeredCount}/${s.questions.length}', style: t.labelLarge),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(syncIcon, size: 14, color: syncColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(syncText, style: t.bodySmall?.copyWith(color: syncColor)),
                ),
                if (s.data.maxLeaves != null) Text('Pelanggaran ${s.leaveCount}/${s.data.maxLeaves}', style: t.bodySmall?.copyWith(color: p.mutedForeground)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _question(PackageQuestion q, int no) {
    final s = _session;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final answer = s.answerOf(q.id);
    final body = t.bodyLarge?.copyWith(fontSize: (t.bodyLarge?.fontSize ?? 16) * _fontScale, height: 1.45);
    Widget input;
    switch (q.type) {
      case 'MULTIPLE_CHOICE':
        input = Column(
          children: [for (final (i, o) in q.options.indexed) _OptionTile(letter: String.fromCharCode(65 + i), text: o.text, selected: answer == o.id, style: body, onTap: () => s.answer(q.id, o.id))],
        );
      case 'TRUE_FALSE':
        input = Column(
          children: [
            _OptionTile(letter: 'B', text: 'Benar', selected: answer == 'true', style: body, onTap: () => s.answer(q.id, 'true')),
            _OptionTile(letter: 'S', text: 'Salah', selected: answer == 'false', style: body, onTap: () => s.answer(q.id, 'false')),
          ],
        );
      default:
        final c = _text.putIfAbsent(q.id, () => TextEditingController(text: answer ?? ''));
        input = TextField(
          controller: c,
          maxLength: 5000,
          minLines: q.type == 'ESSAY' ? 6 : 1,
          maxLines: q.type == 'ESSAY' ? 14 : 1,
          style: body,
          // Tempel/salin dimatikan seperti pengamanan web (blockCopyPaste).
          contextMenuBuilder: (_, _) => const SizedBox.shrink(),
          decoration: InputDecoration(hintText: q.type == 'ESSAY' ? 'Tulis jawaban Anda' : 'Jawaban singkat'),
          onChanged: (v) => s.answer(q.id, v),
        );
    }
    final flagged = s.isFlagged(q.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius2xl),
          side: BorderSide(color: flagged ? p.tint('orange').$2 : p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: p.muted,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(9)),
                    child: Text(
                      '$no',
                      style: t.labelLarge?.copyWith(color: p.onPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('dari ${s.questions.length}', style: t.titleSmall?.copyWith(color: p.mutedForeground)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_typeLabel[q.type] ?? q.type} · ${q.points % 1 == 0 ? q.points.toInt() : q.points} poin',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: p.mutedForeground),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.prompt, style: body),
                  const SizedBox(height: 16),
                  input,
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => s.toggleFlag(q.id),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
                      decoration: BoxDecoration(
                        color: flagged ? p.tint('orange').$1 : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: flagged ? p.tint('orange').$2 : p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(flagged ? LucideIcons.squareCheck : LucideIcons.square, size: 20, color: flagged ? p.tint('orange').$2 : p.mutedForeground),
                          const SizedBox(width: 8),
                          Icon(LucideIcons.flag, size: 18, color: flagged ? p.tint('orange').$2 : p.foreground),
                          const SizedBox(width: 6),
                          Text(
                            'Ragu-ragu',
                            style: t.titleSmall?.copyWith(color: flagged ? p.tint('orange').$2 : p.foreground, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pager() {
    final s = _session;
    final p = context.palette;
    final last = s.page >= s.pageCount - 1;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: p.muted),
            onPressed: s.page > 0 ? () => _goTo(s.page - 1) : null,
            icon: const Icon(LucideIcons.chevronLeft),
            tooltip: 'Sebelumnya',
          ),
          Expanded(
            child: Text(
              'Halaman ${s.page + 1} dari ${s.pageCount}',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.mutedForeground),
            ),
          ),
          if (!last)
            IconButton.filled(onPressed: () => _goTo(s.page + 1), icon: const Icon(LucideIcons.chevronRight), tooltip: 'Berikutnya')
          else
            FilledButton(
              onPressed: s.submitting ? null : _confirmSubmit,
              child: s.submitting ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary)) : const Text('Kumpulkan'),
            ),
        ],
      ),
    );
  }

  void _openGrid() => showModalBottomSheet<void>(
    context: context,
    builder: (c) => ListenableBuilder(
      listenable: _session,
      builder: (c, _) {
        final p = c.palette;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nomor soal', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Terjawab · Ragu-ragu · Kosong', style: TextStyle(color: p.mutedForeground)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (i, q) in _session.questions.indexed)
                    _GridCell(
                      no: i + 1,
                      answered: _session.answerOf(q.id)?.isNotEmpty ?? false,
                      flagged: _session.isFlagged(q.id),
                      onTap: () {
                        _goTo(i ~/ _session.perPage);
                        Navigator.pop(c);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    _confirmSubmit();
                  },
                  child: const Text('Kumpulkan ujian'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _resultView() {
    final r = _session.result!;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TintIcon(icon: r.pending ? LucideIcons.cloudUpload : LucideIcons.circleCheck, tint: r.pending ? 'orange' : 'green', size: 72),
              const SizedBox(height: 16),
              Text(r.pending ? 'Menunggu koneksi' : 'Ujian terkumpul', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                r.message ?? '',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: p.mutedForeground),
              ),
              if (r.score != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${r.score}',
                  style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: p.primary),
                ),
                Text('Nilai', style: TextStyle(color: p.mutedForeground)),
              ],
              const SizedBox(height: 24),
              if (r.pending) ...[
                FilledButton(onPressed: _session.submitting ? null : _session.retryPendingSubmit, child: const Text('Kirim sekarang')),
                TextButton(onPressed: _leave, child: const Text('Tutup (dikirim otomatis nanti)')),
              ] else
                FilledButton(
                  onPressed: _leave,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Selesai'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.muted,
    borderRadius: BorderRadius.circular(kRadiusXl),
    child: InkWell(
      borderRadius: BorderRadius.circular(kRadiusXl),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child),
    ),
  );
}

/// Pilihan jawaban: kotak bergaris dengan huruf dalam lingkaran (seperti web).
class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.letter, required this.text, required this.selected, required this.onTap, this.style});
  final String letter;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? p.tint('violet').$1 : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusXl),
          side: BorderSide(color: selected ? p.primary : p.border, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusXl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? p.primary : p.muted),
                  child: Text(
                    letter,
                    style: TextStyle(color: selected ? p.onPrimary : p.foreground, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(text, style: style)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.no, required this.answered, required this.flagged, required this.onTap});
  final int no;
  final bool answered;
  final bool flagged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = flagged ? p.tint('orange').$1 : (answered ? p.primary : p.muted);
    final fg = flagged ? p.tint('orange').$2 : (answered ? p.onPrimary : p.foreground);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              '$no',
              style: TextStyle(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
