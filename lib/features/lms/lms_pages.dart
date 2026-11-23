import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/site.dart';
import '../../app/theme.dart';
import '../../shared/ui.dart';
import '../../shared/widgets.dart';
import '../auth/login_page.dart' show ChangePasswordForm;
import '../home/diagnostics_tile.dart';
import 'lms_repository.dart';

const _kindLabel = {'MATERI': 'Materi', 'TUGAS': 'Tugas', 'TUGAS_KUIS': 'Tugas Kuis', 'PERTANYAAN': 'Pertanyaan'};
const _kindIcon = {'MATERI': LucideIcons.bookOpenText, 'TUGAS': LucideIcons.clipboardList, 'TUGAS_KUIS': LucideIcons.monitorCheck, 'PERTANYAAN': LucideIcons.messageCircleQuestion};
const _kindTint = {'MATERI': 'violet', 'TUGAS': 'orange', 'TUGAS_KUIS': 'green', 'PERTANYAAN': 'sky'};
const _tints = ['violet', 'sky', 'green', 'orange', 'rose'];

/// Kelas Saya — sama dengan /kelas di web.
class ClassesPage extends ConsumerStatefulWidget {
  const ClassesPage({super.key});

  @override
  ConsumerState<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends ConsumerState<ClassesPage> {
  Future<Cached<Map<String, dynamic>>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
    _data = ref.read(servicesProvider).lms.dashboard();
  });

  @override
  Widget build(BuildContext context) => AppShell(
    location: '/kelas',
    onRefresh: () async => _load(),
    child: AsyncBody<Cached<Map<String, dynamic>>>(
      future: _data,
      onRetry: _load,
      builder: (context, c) {
        final classes = (c.data['classes'] as List).cast<Map<String, dynamic>>();
        final p = context.palette;
        final t = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            if (c.stale) const StaleBanner(),
            const PageTitle('Kelas Saya', subtitle: 'Kelas perkuliahan yang Anda ikuti. Masuk ke kelas baru memakai kode dari pengajar.'),
            const SizedBox(height: 12),
            if (classes.isEmpty) const EmptyNote('Belum mengikuti kelas. Minta kode kelas ke pengajar, lalu gabung lewat situs web.'),
            for (final (i, k) in classes.indexed)
              AppCard(
                margin: const EdgeInsets.only(bottom: 12),
                onTap: k['status'] == 'ACTIVE' ? () => context.push('/kelas/${k['id']}', extra: k) : null,
                child: Row(
                  children: [
                    TintIcon(icon: LucideIcons.school, tint: _tints[i % _tints.length]),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(k['name'] as String, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            [k['subject']?['code'], k['owner'], k['term']].whereType<String>().join(' · ').ifEmpty('${k['members']} anggota'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: p.mutedForeground),
                          ),
                          if (k['status'] == 'PENDING') ...[const SizedBox(height: 6), const Pill(label: 'Menunggu persetujuan', tint: 'orange')],
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 18, color: p.mutedForeground),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Halaman kelas — kepala berwarna + tab "Ujian & Tugas" / "Materi" (seperti /kelas/[id] web).
class ClassPage extends ConsumerStatefulWidget {
  const ClassPage({super.key, required this.classId, this.info});
  final String classId;
  final Map<String, dynamic>? info;

  @override
  ConsumerState<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends ConsumerState<ClassPage> {
  int _tab = 0;
  Future<List<Map<String, dynamic>>>? _exams;
  Future<Cached<Map<String, dynamic>>>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = ref.read(servicesProvider);
    setState(() {
      _exams = s.exams.list(classId: widget.classId);
      _posts = s.lms.classPosts(widget.classId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final info = widget.info ?? const {};
    return AppShell(
      location: '/kelas',
      onRefresh: () async => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          BackLink('Kelas', onTap: () => context.canPop() ? context.pop() : context.go('/kelas')),
          const SizedBox(height: 8),
          HeroCard(
            children: [
              Row(
                children: [
                  Icon(LucideIcons.school, size: 18, color: p.onPrimary.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Text('Kelas', style: t.bodyMedium?.copyWith(color: p.onPrimary.withValues(alpha: 0.85))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                info['name'] as String? ?? 'Kelas',
                style: t.headlineMedium?.copyWith(color: p.onPrimary, fontWeight: FontWeight.w800),
              ),
              if (info['description'] != null) ...[const SizedBox(height: 8), Text(info['description'] as String, style: t.bodyLarge?.copyWith(color: p.onPrimary.withValues(alpha: 0.9)))],
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: PillTabs(labels: const ['Ujian & Tugas', 'Materi'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          const SizedBox(height: 16),
          if (_tab == 0)
            AsyncBody<List<Map<String, dynamic>>>(
              future: _exams,
              onRetry: _load,
              builder: (context, exams) => Column(
                children: [
                  if (exams.isEmpty) const EmptyNote('Belum ada ujian atau tugas di kelas ini.'),
                  for (final e in exams) ExamCard(exam: e, onTap: () => context.push('/ujian/${e['id']}')),
                ],
              ),
            )
          else
            AsyncBody<Cached<Map<String, dynamic>>>(future: _posts, onRetry: _load, builder: _postsView),
        ],
      ),
    );
  }

  Widget _postsView(BuildContext context, Cached<Map<String, dynamic>> c) {
    final topics = (c.data['topics'] as List).cast<Map<String, dynamic>>();
    final posts = (c.data['posts'] as List).cast<Map<String, dynamic>>();
    final t = Theme.of(context).textTheme;
    final names = {for (final x in topics) x['id'] as String: x['name'] as String};
    final order = [...topics.map((x) => x['id'] as String?), null];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.stale) const StaleBanner(),
        if (posts.isEmpty) const EmptyNote('Belum ada materi di kelas ini.'),
        for (final topic in order)
          if (posts.any((x) => x['topicId'] == topic)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Text(topic == null ? 'Tanpa topik' : names[topic] ?? '', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final x in posts.where((x) => x['topicId'] == topic)) PostCard(post: x),
          ],
      ],
    );
  }
}

/// Kartu postingan kelas (Materi / Tugas / Tugas Kuis / Pertanyaan).
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final kind = post['kind'] as String;
    final work = post['work'] as Map?;
    final attachments = (post['attachments'] as List? ?? const []).length;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => context.push('/materi/${post['id']}'),
      child: Row(
        children: [
          TintIcon(icon: post['done'] == true ? LucideIcons.circleCheck : (_kindIcon[kind] ?? LucideIcons.fileText), tint: post['done'] == true ? 'green' : (_kindTint[kind] ?? 'violet')),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post['title'] as String, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [_kindLabel[kind], if (work?['dueAt'] != null) 'Tenggat ${formatTime(work!['dueAt'] as int?)}', if (attachments > 0) '$attachments lampiran'].whereType<String>().join(' · '),
                  style: t.bodySmall?.copyWith(color: p.mutedForeground),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.mutedForeground),
        ],
      ),
    );
  }
}

/// Detail postingan (/kelas/[id]/materi/[materiId] di web).
class PostPage extends ConsumerStatefulWidget {
  const PostPage({super.key, required this.materialId});
  final String materialId;

  @override
  ConsumerState<PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<PostPage> {
  Future<Map<String, dynamic>>? _m;
  final _downloading = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
    _m = ref.read(servicesProvider).lms.material(widget.materialId);
  });

  Future<void> _open(Map<String, dynamic> a) async {
    if (a['type'] != 'FILE') {
      await launchUrl(Uri.parse(a['url'] as String), mode: LaunchMode.externalApplication);
      return;
    }
    setState(() => _downloading.add(a['id'] as String));
    try {
      final file = await ref.read(servicesProvider).lms.downloadAttachment(a['id'] as String, a['name'] as String);
      final r = await OpenFilex.open(file.path);
      if (r.type != ResultType.done && mounted) showSnack(context, 'Berkas tersimpan, tetapi tidak ada aplikasi untuk membukanya.');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _downloading.remove(a['id']));
    }
  }

  @override
  Widget build(BuildContext context) => AppShell(
    location: '/kelas',
    child: AsyncBody<Map<String, dynamic>>(
      future: _m,
      onRetry: _load,
      builder: (context, m) {
        final p = context.palette;
        final t = Theme.of(context).textTheme;
        final kind = m['kind'] as String;
        final work = m['work'] as Map<String, dynamic>?;
        final attachments = (m['attachments'] as List).cast<Map<String, dynamic>>();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            BackLink('Kelas', onTap: () => context.canPop() ? context.pop() : context.go('/kelas')),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TintIcon(icon: _kindIcon[kind] ?? LucideIcons.fileText, tint: _kindTint[kind] ?? 'violet'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text([_kindLabel[kind], m['topic']].whereType<String>().join(' · '), style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(m['title'] as String, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(formatTime(m['publishedAt'] as int?), style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                  if (m['content'] != null) ...[const SizedBox(height: 14), SelectableText(m['content'] as String, style: t.bodyLarge?.copyWith(height: 1.5))],
                ],
              ),
            ),
            if (work != null) ...[
              const SizedBox(height: 12),
              AppCard(
                onTap: () => context.push('/ujian/${work['examId']}'),
                child: Row(
                  children: [
                    const TintIcon(icon: LucideIcons.clipboardList, tint: 'orange'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(work['title'] as String? ?? 'Pekerjaan', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          Text(work['dueAt'] != null ? 'Tenggat ${formatTime(work['dueAt'] as int?)}' : 'Tanpa tenggat', style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 18, color: p.mutedForeground),
                  ],
                ),
              ),
            ],
            if (attachments.isNotEmpty) ...[
              const SectionHeader('Lampiran'),
              for (final a in attachments)
                AppCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => _open(a),
                  child: Row(
                    children: [
                      TintIcon(
                        icon: switch (a['type']) {
                          'YOUTUBE' => LucideIcons.squarePlay,
                          'LINK' => LucideIcons.link,
                          _ => LucideIcons.paperclip,
                        },
                        tint: a['type'] == 'YOUTUBE' ? 'rose' : 'sky',
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a['name'] as String, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                            if (a['size'] != null) Text('${((a['size'] as int) / 1024).ceil()} KB', style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                          ],
                        ),
                      ),
                      if (_downloading.contains(a['id']))
                        const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(a['type'] == 'FILE' ? LucideIcons.download : LucideIcons.externalLink, size: 18, color: p.mutedForeground),
                    ],
                  ),
                ),
            ],
            if (kind == 'MATERI') ...[
              const SizedBox(height: 16),
              m['done'] == true
                  ? OutlinedButton.icon(onPressed: () => _toggle(false), icon: const Icon(LucideIcons.undo2, size: 18), label: const Text('Batalkan selesai dibaca'))
                  : FilledButton.icon(onPressed: () => _toggle(true), icon: const Icon(LucideIcons.check, size: 18), label: const Text('Tandai selesai dibaca')),
            ],
          ],
        );
      },
    ),
  );

  Future<void> _toggle(bool done) async {
    try {
      await ref.read(servicesProvider).lms.setDone(widget.materialId, done);
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }
}

/// Profil & Password (/profil di web) + laporan error perangkat.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final site = ref.watch(siteProvider);
    final s = ref.read(servicesProvider);
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return AppShell(
      location: '/profil',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          PageTitle(site.t('nav.profil')),
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                InitialsAvatar(user?.name ?? '', size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '-', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(user?.email ?? '', style: t.bodySmall?.copyWith(color: p.mutedForeground)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          Pill(label: site.t('role.PESERTA')),
                          if (user?.username != null) Pill(label: 'NIM ${user!.username}', tint: 'sky'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Ganti password'),
          const AppCard(child: ChangePasswordForm()),
          const SectionHeader('Aplikasi'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(leading: const Icon(LucideIcons.info), title: const Text('Versi aplikasi'), trailing: Text(s.appVersion)),
                const Divider(),
                const DiagnosticsTile(),
                const Divider(),
                ListTile(
                  leading: Icon(LucideIcons.logOut, color: p.destructive),
                  title: Text(
                    'Keluar',
                    style: TextStyle(color: p.destructive, fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Keluar dari aplikasi?'),
                        content: const Text('Ujian yang belum dikumpulkan tetap tersimpan di perangkat ini.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keluar')),
                        ],
                      ),
                    );
                    if (ok == true) ref.read(authProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
