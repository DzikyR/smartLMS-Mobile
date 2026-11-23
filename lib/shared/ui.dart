import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/site.dart';
import '../app/theme.dart';
import 'widgets.dart';

/// Komponen yang meniru tampilan web (shadcn + Tailwind di smartTest/src/components).

/// "SmartTest" → "Smart" + "Test" berwarna primary (BrandName di web); nama lain apa adanya.
class BrandName extends StatelessWidget {
  const BrandName(this.name, {super.key, this.style});
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? Theme.of(context).textTheme.titleLarge)!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4);
    final m = RegExp(r'^([A-Z][a-z0-9]+)([A-Z]\w*)$').firstMatch(name);
    if (m == null) return Text(name, style: base, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: m.group(1)),
          TextSpan(
            text: m.group(2),
            style: TextStyle(color: context.palette.primary),
          ),
        ],
      ),
    );
  }
}

/// Logo aplikasi: gambar unggahan Super Admin (Tampilan Situs), atau ikon + nama bawaan.
class BrandLogo extends ConsumerWidget {
  const BrandLogo({super.key, this.size = 36, this.showName = true, this.inverse = false});
  final double size;
  final bool showName;
  final bool inverse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(siteProvider);
    final dark = inverse || Theme.of(context).brightness == Brightness.dark;
    final url = site.logoUrl(dark: dark);
    if (url != null) {
      return CachedNetworkImage(imageUrl: url, height: size, fit: BoxFit.contain, alignment: Alignment.centerLeft, errorWidget: (_, _, _) => _fallback(context, site));
    }
    return _fallback(context, site);
  }

  Widget _fallback(BuildContext context, SiteConfig site) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: inverse ? Colors.white.withValues(alpha: 0.15) : p.primary,
            borderRadius: BorderRadius.circular(size * 0.33),
            boxShadow: inverse ? null : [BoxShadow(color: p.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Icon(LucideIcons.graduationCap, color: inverse ? Colors.white : p.onPrimary, size: size * 0.55),
        ),
        if (showName) ...[
          SizedBox(width: size * 0.3),
          Flexible(
            child: BrandName(
              site.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: inverse ? Colors.white : null, fontSize: size * 0.56),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kartu putih ber-ring tipis (Card web: rounded-2xl ring-1 ring-border/60).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.margin});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius2xl),
          side: BorderSide(color: p.border.withValues(alpha: 0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Panel berwarna primary bergradien (sapaan dashboard, kepala kelas & ujian).
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadius2xl),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.primary, Color.lerp(p.primary, Colors.black, 0.07)!, p.primaryDeep]),
        ),
        child: Stack(
          children: [
            Positioned(right: -60, top: -40, child: _circle(220)),
            Positioned(left: 60, bottom: -110, child: _circle(200)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: p.onPrimary),
                child: IconTheme.merge(
                  data: IconThemeData(color: p.onPrimary),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
  );
}

/// Chip transparan di atas HeroCard (Latihan · 20 menit · 10 soal).
class HeroChip extends StatelessWidget {
  const HeroChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(kRadiusXl)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.palette.onPrimary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.palette.onPrimary, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

class TintIcon extends StatelessWidget {
  const TintIcon({super.key, required this.icon, this.tint = 'violet', this.size = 44});
  final IconData icon;
  final String tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = context.palette.tint(tint);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.tint, this.hint});
  final String label;
  final String value;
  final IconData icon;
  final String tint;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          TintIcon(icon: icon, tint: tint),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.bodyMedium?.copyWith(color: context.palette.mutedForeground)),
                Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (hint != null) Text(hint!, style: t.bodySmall?.copyWith(color: context.palette.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status ujian peserta (warna sama dengan web).
class StatusPill extends StatelessWidget {
  const StatusPill(this.state, {super.key});
  final String state;

  static const labels = {'running': 'Sedang dikerjakan', 'available': 'Bisa dikerjakan', 'upcoming': 'Akan datang', 'done': 'Selesai', 'missed': 'Terlewat'};
  static const tints = {'running': 'orange', 'available': 'green', 'upcoming': 'sky', 'done': 'violet', 'missed': 'rose'};

  @override
  Widget build(BuildContext context) => Pill(label: labels[state] ?? state, tint: tints[state] ?? 'violet');
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.tint = 'violet'});
  final String label;
  final String tint;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = context.palette.tint(tint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

const kindLabels = {'KUIS': 'Kuis', 'UTS': 'UTS', 'UAS': 'UAS', 'TRYOUT': 'Try Out', 'LATIHAN': 'Latihan', 'LAINNYA': 'Lainnya'};

/// Kartu ujian (participant-exam-card.tsx di web).
class ExamCard extends StatelessWidget {
  const ExamCard({super.key, required this.exam, required this.onTap});
  final Map<String, dynamic> exam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final e = exam;
    final kind = (e['category'] as String?) ?? kindLabels[e['kind']] ?? 'Ujian';
    // Server lama (sebelum /site) mengirim subject sebagai teks nama — tetap didukung.
    final raw = e['subject'];
    final subject = raw is Map ? raw : {'name': raw};
    final subjectLine = [subject['code'], subject['name']].whereType<String>().join(' · ');
    final endAt = e['endAt'] as int?;
    final note = switch (e['mobile']) {
      'not_allowed' => 'Hanya di laptop/PC',
      'integrity_required' => 'Wajib Safe Exam Browser',
      'web_only' => 'Dikerjakan di web',
      _ => null,
    };
    final meta = t.bodyMedium?.copyWith(color: p.mutedForeground);
    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(kRadiusXl)),
                child: Text(
                  kind,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: t.labelMedium?.copyWith(color: p.onPrimary, fontWeight: FontWeight.w700, height: 1.1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subjectLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: p.mutedForeground),
                    ),
                    const SizedBox(height: 2),
                    Text(e['title'] as String, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(e['state'] as String? ?? ''),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              if (e['workType'] != 'ASSIGNMENT')
                _Meta(icon: LucideIcons.clock, text: e['timed'] == false || e['durationMinutes'] == null ? 'Tanpa batas durasi' : '${e['durationMinutes']} menit', style: meta),
              if (e['questionCount'] != null && e['workType'] != 'ASSIGNMENT') _Meta(icon: LucideIcons.fileQuestion, text: '${e['questionCount']} soal', style: meta),
              if (e['best'] != null) _Meta(icon: LucideIcons.trophy, text: 'Nilai ${e['best']}', style: meta),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.calendarClock, size: 16, color: p.mutedForeground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note ?? (endAt == null ? 'Tanpa batas waktu tutup' : 'Ditutup ${formatTime(endAt)}'),
                  style: t.bodySmall?.copyWith(color: note != null ? p.tint('orange').$2 : p.mutedForeground),
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: p.mutedForeground),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.style});
  final IconData icon;
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: style?.color),
      const SizedBox(width: 6),
      Text(text, style: style),
    ],
  );
}

/// Judul bagian + tautan "Lihat semua".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.trailing});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        ?trailing,
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

/// Judul halaman (PageHeader web).
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4)),
          if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: t.bodyMedium?.copyWith(color: context.palette.mutedForeground))],
        ],
      ),
    );
  }
}

/// "← Kelas" di atas halaman detail.
class BackLink extends StatelessWidget {
  const BackLink(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.arrowLeft, size: 18),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    ),
  );
}

/// Tab berbentuk pil (Tabs web): "Ujian & Tugas | Materi".
class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(kRadiusXl),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, l) in labels.indexed)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: i == index ? p.primary : Colors.transparent, borderRadius: BorderRadius.circular(kRadius)),
                child: Text(
                  l,
                  style: TextStyle(color: i == index ? p.onPrimary : p.mutedForeground, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Avatar inisial (PU untuk "Peserta Uji").
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = parts.take(2).map((s) => s[0].toUpperCase()).join();
    final (bg, fg) = context.palette.tint('violet');
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bg,
      child: Text(
        initials,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: size * 0.36),
      ),
    );
  }
}

/// Kotak kosong bergaris putus-putus (empty state web).
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(kRadius2xl),
      border: Border.all(color: context.palette.border),
    ),
    child: Text(text, style: TextStyle(color: context.palette.mutedForeground)),
  );
}
