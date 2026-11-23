import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';

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

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(authProvider).notice;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.school_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('SmartTest', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  Text('CBT & LMS Informatika', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  if (notice != null && _error == null) ...[
                    Text(notice, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.tertiary)),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _id,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email atau NIM', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pw,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(padding: const EdgeInsets.all(12), child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Masuk')),
                  ),
                  const SizedBox(height: 16),
                  Text('Lupa password? Gunakan menu "Lupa password" di situs web.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ganti password'), actions: [
          TextButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: const Text('Keluar')),
        ]),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Anda memakai password sementara. Buat password baru (minimal 10 karakter, kombinasi huruf dan angka).'),
          const SizedBox(height: 20),
          TextField(controller: _current, obscureText: true, decoration: InputDecoration(labelText: 'Password saat ini', errorText: _fields['currentPassword'], border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _next, obscureText: true, decoration: InputDecoration(labelText: 'Password baru', errorText: _fields['newPassword'], border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _confirm, obscureText: true, decoration: InputDecoration(labelText: 'Ulangi password baru', errorText: _fields['confirm'], border: const OutlineInputBorder())),
          if (_error != null && _fields.isEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: const Padding(padding: EdgeInsets.all(12), child: Text('Simpan password'))),
        ]),
      );
}
