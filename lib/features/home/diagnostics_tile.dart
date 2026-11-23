import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/diagnostics.dart';

/// Profil → "Laporan error": error terakhir di perangkat, bisa disalin untuk dikirim ke pengembang.
class DiagnosticsTile extends StatelessWidget {
  const DiagnosticsTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(LucideIcons.bug),
    title: const Text('Laporan error'),
    subtitle: Text(Diagnostics.entries.isEmpty ? 'Tidak ada error tercatat' : '${Diagnostics.entries.length} error tercatat'),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: Text('Laporan error', style: Theme.of(c).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: Diagnostics.entries.isEmpty
                      ? null
                      : () async {
                          await Diagnostics.copy();
                          if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Disalin — tempel & kirim ke pengembang.')));
                        },
                  icon: const Icon(LucideIcons.copy, size: 18),
                  label: const Text('Salin'),
                ),
              ],
            ),
            if (Diagnostics.entries.isEmpty) const Text('Belum ada error.'),
            for (final e in Diagnostics.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
          ],
        ),
      ),
    ),
  );
}
