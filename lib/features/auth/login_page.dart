import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/site.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../shared/ui.dart';

/// Layar masuk — sama dengan /login di web (teks dari Tampilan Situs).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = 'Isi email/NIM dan password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_id.text, _pw.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _web(String path) => launchUrl(Uri.parse('${AppConfig.apiBase}$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteProvider);
    final notice = ref.watch(authProvider).notice;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    Widget label(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
          ),
          ?trailing,
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 40)),
                    const SizedBox(height: 32),
                    Text(site.t('login.title'), style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                    const SizedBox(height: 6),
                    Text(site.t('login.subtitle'), style: t.bodyLarge?.copyWith(color: p.mutedForeground)),
                    const SizedBox(height: 28),
                    if (notice != null && _error == null) _Alert(notice, tint: 'sky'),
                    if (_error != null) _Alert(_error!, tint: 'rose'),
                    label('Email atau NIM / Username'),
                    TextField(controller: _id, autofillHints: const [AutofillHints.username], textInputAction: TextInputAction.next, keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 18),
                    label(
                      'Password',
                      trailing: GestureDetector(
                        onTap: () => _web('/lupa-password'),
                        child: Text(
                          'Lupa password?',
                          style: t.bodyMedium?.copyWith(color: p.primary, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    TextField(
                      controller: _pw,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(icon: Icon(_hide ? LucideIcons.eye : LucideIcons.eyeOff, size: 20), onPressed: () => setState(() => _hide = !_hide)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _busy ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary)) : Text(site.t('login.cta')),
                    ),
                    if (site.registrationOpen) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: Text.rich(
                          TextSpan(
                            style: t.bodyMedium?.copyWith(color: p.mutedForeground),
                            children: [
                              const TextSpan(text: 'Belum punya akun? '),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () => _web('/daftar'),
                                  child: Text(
                                    'Daftar',
                                    style: t.bodyMedium?.copyWith(color: p.primary, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert(this.text, {required this.tint});
  final String text;
  final String tint;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = context.palette.tint(tint);
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(kRadiusXl)),
      child: Text(text, style: TextStyle(color: fg)),
    );
  }
}

/// Ganti password (wajib untuk password sementara; juga dari halaman Profil).
class ChangePasswordForm extends ConsumerStatefulWidget {
  const ChangePasswordForm({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  ConsumerState<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, String> _fields = const {};

  Future<void> _submit() async {
    if (_next.text != _confirm.text) {
      setState(() => _fields = {'confirm': 'Konfirmasi tidak sama'});
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fields = const {};
    });
    try {
      await ref.read(authProvider.notifier).changePassword(_current.text, _next.text);
      _current.clear();
      _next.clear();
      _confirm.clear();
      widget.onDone?.call();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _fields = e.fields;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget field(String label, TextEditingController c, String key) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
          ),
          TextField(
            controller: c,
            obscureText: true,
            decoration: InputDecoration(errorText: _fields[key]),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field('Password saat ini', _current, 'currentPassword'),
        field('Password baru', _next, 'newPassword'),
        field('Ulangi password baru', _confirm, 'confirm'),
        Text('Minimal 10 karakter, kombinasi huruf dan angka. Semua perangkat lain akan keluar.', style: t.bodySmall?.copyWith(color: context.palette.mutedForeground)),
        if (_error != null && _fields.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: context.palette.destructive)),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan password')),
      ],
    );
  }
}

/// Layar wajib ganti password sementara.
class ChangePasswordPage extends ConsumerWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const Expanded(child: BrandLogo(size: 36)),
              TextButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: const Text('Keluar')),
            ],
          ),
          const SizedBox(height: 28),
          const PageTitle('Ganti password', subtitle: 'Anda memakai password sementara. Buat password baru untuk melanjutkan.'),
          const SizedBox(height: 16),
          const AppCard(child: ChangePasswordForm()),
        ],
      ),
    ),
  );
}
