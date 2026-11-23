import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/ui.dart';
import 'providers.dart';
import 'theme.dart';

/// Ikon menu (sama dengan src/components/shell/nav.ts di web).
const navIcons = <String, IconData>{
  '/dashboard': LucideIcons.layoutDashboard,
  '/kelas': LucideIcons.school,
  '/ujian': LucideIcons.monitorCheck,
  '/hasil': LucideIcons.trophy,
  '/profil': LucideIcons.userRound,
};

/// Kerangka halaman seperti web di HP: header (menu ☰, logo, avatar) + laci navigasi.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child, this.onRefresh});

  /// Menu aktif, mis. "/ujian" (halaman detail memakai menu induknya).
  final String location;
  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final user = ref.watch(authProvider).user;
    final body = onRefresh == null ? child : RefreshIndicator(onRefresh: onRefresh!, child: child);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        title: const BrandLogo(size: 36),
        leading: Builder(
          builder: (c) => IconButton(icon: const Icon(LucideIcons.menu), tooltip: 'Menu', onPressed: () => Scaffold.of(c).openDrawer()),
        ),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(customBorder: const CircleBorder(), onTap: () => context.go('/profil'), child: InitialsAvatar(user.name, size: 40)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: p.border),
        ),
      ),
      drawer: _NavDrawer(location: location),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _NavDrawer extends ConsumerWidget {
  const _NavDrawer({required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final menu = ref.watch(authProvider).menu;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Row(
              children: [
                const Expanded(child: BrandLogo(size: 32, showName: true)),
                IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            for (final section in menu) ...[
              if (section.title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                  child: Text(
                    section.title!.toUpperCase(),
                    style: t.labelSmall?.copyWith(color: p.mutedForeground, letterSpacing: 1.1, fontWeight: FontWeight.w600),
                  ),
                ),
              for (final item in section.items) _item(context, item.href, item.label),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, String href, String label) {
    final p = context.palette;
    final active = location == href || (href != '/dashboard' && location.startsWith('$href/'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? p.primary : Colors.transparent,
        elevation: active ? 2 : 0,
        shadowColor: p.primary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(kRadiusXl),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusXl),
          onTap: () {
            Navigator.pop(context);
            context.go(href);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(navIcons[href] ?? LucideIcons.circle, size: 22, color: active ? p.onPrimary : p.mutedForeground),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: active ? p.onPrimary : p.foreground, fontWeight: active ? FontWeight.w600 : FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
