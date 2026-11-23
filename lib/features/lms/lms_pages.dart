import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../shared/widgets.dart';
import 'lms_repository.dart';

const _kindLabel = {'MATERI': 'Materi', 'TUGAS': 'Tugas', 'TUGAS_KUIS': 'Tugas Kuis', 'PERTANYAAN': 'Pertanyaan'};

/// Tab Materi kelas: postingan terbit dikelompokkan per topik (seperti halaman kelas di web).
class ClassPage extends ConsumerStatefulWidget {
  const ClassPage({super.key, required this.classId, this.title});
  final String classId;
  final String? title;

  @override
  ConsumerState<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends ConsumerState<ClassPage> {
  Future<Cached<Map<String, dynamic>>>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _posts = ref.read(servicesProvider).lms.classPosts(widget.classId));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'Kelas')),
        body: RefreshIndicator(
          onRefresh: () async => _load(),
          child: AsyncBody<Cached<Map<String, dynamic>>>(
            future: _posts,
            onRetry: _load,
            builder: (context, c) {
              final topics = (c.data['topics'] as List).cast<Map<String, dynamic>>();
              final posts = (c.data['posts'] as List).cast<Map<String, dynamic>>();
              final groups = <String?, List<Map<String, dynamic>>>{null: [], for (final t in topics) t['id'] as String: []};
              for (final p in posts) {
                (groups[p['topicId']] ?? groups[null]!).add(p);
              }
              final names = {for (final t in topics) t['id'] as String: t['name'] as String};
              return ListView(children: [
                if (c.stale) const StaleBanner(),
                if (posts.isEmpty) const ListTile(title: Text('Belum ada postingan.')),
                for (final entry in [...groups.entries.where((e) => e.key != null), groups.entries.first])
                  if (entry.value.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Text(entry.key == null ? 'Tanpa topik' : names[entry.key]!, style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final p in entry.value)
                      ListTile(
                        leading: Icon(p['done'] == true ? Icons.check_circle : Icons.article_outlined),
                        title: Text(p['title'] as String),
                        subtitle: Text([
                          _kindLabel[p['kind']],
                          if (p['work']?['dueAt'] != null) 'tenggat ${formatTime(p['work']['dueAt'] as int?)}',
                          if ((p['attachments'] as List).isNotEmpty) '${(p['attachments'] as List).length} lampiran',
                        ].whereType<String>().join(' · ')),
                        onTap: () => context.push('/material/${p['id']}'),
                      ),
                  ],
              ]);
            },
          ),
        ),
      );
}

class MaterialPage extends ConsumerStatefulWidget {
  const MaterialPage({super.key, required this.materialId});
  final String materialId;

  @override
  ConsumerState<MaterialPage> createState() => _MaterialPageState();
}

class _MaterialPageState extends ConsumerState<MaterialPage> {
  Future<Map<String, dynamic>>? _m;
  final _downloading = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _m = ref.read(servicesProvider).lms.material(widget.materialId));

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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Postingan')),
        body: AsyncBody<Map<String, dynamic>>(
          future: _m,
          onRetry: _load,
          builder: (context, m) {
            final work = m['work'] as Map<String, dynamic>?;
            final attachments = (m['attachments'] as List).cast<Map<String, dynamic>>();
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(_kindLabel[m['kind']] ?? '', style: Theme.of(context).textTheme.labelLarge),
              Text(m['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
              if (m['topic'] != null) Text('Topik: ${m['topic']}'),
              Text(formatTime(m['publishedAt'] as int?), style: Theme.of(context).textTheme.bodySmall),
              if (m['content'] != null) ...[const SizedBox(height: 16), SelectableText(m['content'] as String)],
              if (work != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: Text(work['title'] as String? ?? 'Pekerjaan'),
                    subtitle: Text(work['dueAt'] != null ? 'Tenggat ${formatTime(work['dueAt'] as int?)}' : 'Tanpa tenggat'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/exam/${work['examId']}'),
                  ),
                ),
              ],
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Lampiran', style: Theme.of(context).textTheme.titleMedium),
                for (final a in attachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (a['type']) { 'YOUTUBE' => Icons.ondemand_video, 'LINK' => Icons.link, _ => Icons.insert_drive_file_outlined }),
                    title: Text(a['name'] as String),
                    subtitle: a['size'] != null ? Text('${((a['size'] as int) / 1024).ceil()} KB') : null,
                    trailing: _downloading.contains(a['id']) ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                    onTap: () => _open(a),
                  ),
              ],
              if (m['kind'] == 'MATERI') ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      await ref.read(servicesProvider).lms.setDone(widget.materialId, m['done'] != true);
                      _load();
                    } catch (e) {
                      if (context.mounted) showSnack(context, errorText(e));
                    }
                  },
                  icon: Icon(m['done'] == true ? Icons.undo : Icons.check),
                  label: Text(m['done'] == true ? 'Batalkan selesai dibaca' : 'Tandai selesai dibaca'),
                ),
              ],
            ]);
          },
        ),
      );
}
